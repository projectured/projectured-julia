# Fragment of `HelpModule` — the groups of a tree of the help, built from the
# loaded modules, and the nodes that the tree slice draws.
#
# A tree stores its groups. The acquire of a tree builds them, and builds them
# again after a change of the loaded program, because no computation may read
# the loaded modules (`PAR-PURE-THUNK`). A build keeps the object of a group and
# of an entry that stays, so the open nodes of a tree and the address of a
# navigator stay too.

const _HelpList = Union{DocumentTypeList, ProjectionList}

# The types of a tree: what an empty tab can make, or every concrete projection.
_collect_help_types(::DocumentTypeList) = get_insertion_candidates(Document)
_collect_help_types(::ProjectionList) = compute_concrete_subtypes(Projection)

"""
    update_help_groups!(list) -> list

Build the groups of a [`DocumentTypeList`](@ref) or a [`ProjectionList`](@ref)
from the modules that are loaded now, and store them in `list.children`:

- one [`HelpGroup`](@ref) for each package that defines a type of the list, the
  kernel first, then the platform, then the other packages by name;
- in a package with more than one module that defines such a type, one group for
  each module, by name, and in any other group the entries of its types, by
  name with no regard to case.

A group and an entry that a build before made keep their object, and a field
that has the same value is not written. The acquire of the list calls it when
the world counter moved after the last build. Call it for a script or a test
that shows a list with no editor. It reads the loaded modules, so it never runs
in a print.
"""
function update_help_groups!(list::_HelpList)
    old_groups, old_entries = _index_help_nodes(list)
    typed = list isa DocumentTypeList
    packages = Dict{Module, Dict{Module, Vector{Any}}}()
    for T in _collect_help_types(list)
        defining = parentmodule(T)
        modules = get!(() -> Dict{Module, Vector{Any}}(), packages, Base.moduleroot(defining))
        push!(get!(() -> Any[], modules, defining), T)
    end
    groups = Any[]
    for package in _sort_help_packages(collect(keys(packages)))
        modules = packages[package]
        title = _get_help_package_title(package)
        entry_columns = typed ? _HELP_DOCUMENT_COLUMNS : _HELP_PROJECTION_COLUMNS
        children, columns = if length(modules) == 1
            (_build_help_entries(only(values(modules)), old_entries; typed), entry_columns)
        else
            (Any[_update_help_group!(old_groups, string(title, "/", _get_help_module_title(m)),
                                     _get_help_module_title(m), compute_docstring_summary(m),
                                     _build_help_entries(modules[m], old_entries; typed), entry_columns)
                 for m in _sort_help_modules(collect(keys(modules)))], _HELP_GROUP_COLUMNS)
        end
        description = compute_docstring_summary(package)
        isempty(description) && length(modules) == 1 &&
            (description = compute_docstring_summary(only(keys(modules))))
        push!(groups, _update_help_group!(old_groups, title, title, description, children, columns))
    end
    _write_help_children!(list, groups)
    getfield(list, :table)[] === nothing && (list.table = _make_help_table(list, _HELP_GROUP_COLUMNS))
    list.world = Base.get_world_counter()
    list
end

# The columns of the table of a page: a group, a document type or a projection.
const _HELP_GROUP_COLUMNS = ["name", "count", "description"]
const _HELP_DOCUMENT_COLUMNS = ["name", "typed", "description"]
const _HELP_PROJECTION_COLUMNS = ["name", "description"]

# The roster of the children of `holder`, which its page draws: a double click on
# a row opens the page of the row.
_make_help_table(holder, columns) =
    link_roster!(Roster(CollectionItems(extend_reference(EmptyReference(), FieldReferenceStep("children")));
                        columns, title = get_document_title(holder)), holder)

# The groups of a list by their path of names, such as "Platform/Widget", and the
# entries by their type.
function _index_help_nodes(list::_HelpList)
    groups = Dict{String, Any}()
    entries = IdDict{Any, Any}()
    function visit(node, path)
        if node isa HelpGroup
            place = isempty(path) ? node.name : string(path, "/", node.name)
            groups[place] = node
            foreach(child -> visit(child, place), node.children)
        elseif node isa HelpEntry
            entries[node.type] = node
        end
    end
    foreach(child -> visit(child, ""), list.children)
    (groups, entries)
end

# The group at `place`, with the fields of a new build: the one a build before
# made, or a new one, whose table has `columns`.
function _update_help_group!(old_groups, place, name, description, children, columns)
    count = sum((child isa HelpGroup ? child.count : 1 for child in children); init = 0)
    group = get(old_groups, place, nothing)
    if group === nothing
        group = HelpGroup(name, count, description, CellVector(Any[children...]), nothing)
        group.table = _make_help_table(group, columns)
        return group
    end
    group.count == count || (group.count = count)
    group.description == description || (group.description = description)
    _write_help_children!(group, children)
    group
end

# A new collection only when the children are other objects, so the readers of a
# collection that stays compute nothing.
function _write_help_children!(holder, children)
    current = holder.children
    (length(current) == length(children) && all(k -> current[k] === children[k], eachindex(children))) ||
        (holder.children = CellVector(Any[children...]))
    nothing
end

# The entries of `types`, by name with no regard to case. A permutation of plain
# strings, because a sort of the entries by a key compiles the sort for their
# type at the first build.
function _build_help_entries(types, old_entries; typed::Bool)
    names = [String(nameof(T)) for T in types]
    order = sortperm([lowercase(name) for name in names])
    Any[_update_help_entry!(old_entries, types[k], names[k]; typed) for k in order]
end

function _update_help_entry!(old_entries, @nospecialize(T), name; typed::Bool)
    words = typed ? join(_get_typed_names(T), ", ") : ""
    description = compute_docstring_summary(T)
    text = something(find_docstring_text(T), "")
    entry = get(old_entries, T, nothing)
    entry === nothing && return HelpEntry(name, T, words, description, text)
    entry.typed == words || (entry.typed = words)
    entry.description == description || (entry.description = description)
    entry.text == text || (entry.text = text)
    entry
end

# The names a person types into an empty tab to make a `T`, without the name of
# the type itself: the words of the name, and the aliases. `T` is not
# specialized on, so one method serves every type of the list.
function _get_typed_names(@nospecialize(T::Type))
    own = String(nameof(T))
    filter(!=(own), get_insertion_names(T))
end

# The kernel and the platform first, because every other package builds on them;
# then the others by name.
function _sort_help_packages(packages)
    first_names = ("ProjecturedKernel", "ProjecturedPlatform")
    rank(package) = something(findfirst(==(String(nameof(package))), first_names), length(first_names) + 1)
    names = [string(rank(package), " ", lowercase(String(nameof(package)))) for package in packages]
    packages[sortperm(names)]
end

_sort_help_modules(modules) = modules[sortperm([lowercase(_get_help_module_title(m)) for m in modules])]

# "ProjecturedJSON" is JSON, and "WidgetModule" is Widget: the names that the
# loaded program holds, also in a binary, and that the folders of the source need
# not match.
_get_help_package_title(package::Module) = _remove_name_part(String(nameof(package)), "Projectured", true)
_get_help_module_title(m::Module) = _remove_name_part(String(nameof(m)), "Module", false)

function _remove_name_part(name::String, part::String, at_start::Bool)
    length(name) > length(part) || return name
    at_start ? (startswith(name, part) ? name[(length(part) + 1):end] : name) :
               (endswith(name, part) ? name[1:(end - length(part))] : name)
end

# The acquire builds the groups when the program changed after the last build,
# such as when a package loaded or a session defined a type.
function acquire_document!(editor, list::_HelpList)
    list.world == Base.get_world_counter() || update_help_groups!(list)
    nothing
end

# A tree has groups once its acquire built them, so its row shows a chevron and
# reads nothing before.
get_tree_children_steps(::_HelpList) = ((FieldReferenceStep("children"),),)
get_tree_children_steps(::HelpGroup) = ((FieldReferenceStep("children"),),)
has_tree_children(::_HelpList) = true
