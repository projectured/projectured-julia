# Fragment of `ExplorerModule` — the documents of an explorer: a section, which is
# a list of entries that a person controls, and the explorer, which shows one root
# section as a tree beside a navigator. The root section of an editor belongs to
# the editor, as its task list does.

"""
    ExplorerSection(title, entries)

A list of entries with a title. An entry is any document: a folder, the task list
of the editor, a project, a dashboard, another section. A section links its
entries and does not own them, so one document can be an entry of many sections,
and a removal of an entry leaves the document as it is.

Use it to group the entries of an explorer, such as the documents of one study,
and as the root of an [`Explorer`](@ref).

# Example

    section_1 = ExplorerSection("Tools", Any[get_session_task_group_list()])

See also `Explorer` and `find_explorer_content`.
"""
@document struct ExplorerSection <: Document
    title::String
    entries::CellVector = CellVector(Any[])
end

get_document_title(section::ExplorerSection) = section.title

get_tree_children_steps(::ExplorerSection) = ((FieldReferenceStep("entries"),),)
format_tree_node_label(section::ExplorerSection) = section.title
get_document_decoration(section::ExplorerSection) =
    DocumentDecoration(; icon = :layers, tooltip = () -> _make_section_note(section))

# What a row of a section says when the pointer rests on it: how many entries it
# holds, and the keys that rename it and add an entry.
_make_section_note(section::ExplorerSection) =
    TooltipNote(; title = section.title, facts = ["Entries" => string(length(section.entries))],
                keys = vcat(find_bound_keys(Explorer, "Rename"), find_bound_keys(Explorer, "Add an entry")))

# A person adds a new empty section by name, as an entry of a section or in a tab.
get_insertion_aliases(::Type{ExplorerSection}) = ["section"]
make_insertion_document(::Type{ExplorerSection}) = ExplorerSection("New section")
is_explorer_entry_type(::Type{ExplorerSection}) = true

# The kinds that the list of `+` shows, in the order of their names.
_collect_entry_kinds() =
    sort!(Pair{String,Type}[_format_kind_name(type) => type
                            for type in get_insertion_candidates(Document) if is_explorer_entry_type(type)];
          by = first)

# The name of a kind that a person reads: the first insertion alias of the kind,
# else the words of its type name.
function _format_kind_name(type)
    aliases = get_insertion_aliases(type)
    uppercasefirst(isempty(aliases) ? get_insertion_names(type)[2] : first(aliases))
end

# A document that the section holds, at the path of its entry, or at the path that
# the entry answers for it below the entry. Each entry is asked in turn, so a
# section inside a section answers too.
function find_navigator_address(section::ExplorerSection, document)
    entries = section.entries
    for k in eachindex(entries)
        entry = entries[k]
        place = extend_reference(EmptyReference(), FieldReferenceStep("entries"), ElementReferenceStep(k))
        entry === document && return place
        below = find_navigator_address(entry, document)
        below === nothing || return concat_references(place, strip_reference_types(below))
    end
    nothing
end

"""
    Explorer(content)

The explorer of the section `content`: a `DocumentTree` of the section, and
beside it a `Navigator` over the same section, which shows the page of the node
that a person presses. The page of a section shows its entries.

# Fields
- `tree` — the `DocumentTree` of the section: its own open nodes.
- `navigator` — the `Navigator` over the section: its own page and visits.
- `filter` — the [`ExplorerFilter`](@ref) of the explorer.
- `matches` — the `DocumentTree` of the rows that the filter keeps, which shows in
  the place of the tree while the filter keeps rows out, or `nothing`.

Two explorers of one section show the same entries, each with its own open nodes,
its own page and its own filter. A file keeps the section, and not the open nodes,
the page or the filter.

Use it to show what an editor holds in one tab: its files, its tasks, its
assistants, and any document that a person adds.

# Example

    explorer_1 = Explorer(get_session_explorer_content())
    open_pane!(explorer_1)

See also `ExplorerSection` and `get_session_explorer_content`.
"""
@document struct Explorer <: Document
    tree::Any                         # DocumentTree
    navigator::Any                    # Navigator
    filter::Any                       # ExplorerFilter
    matches::Any                      # DocumentTree of the matches, or nothing
end

# The tree marks the row of the page that the navigator shows, also after a link
# inside the page moves the navigator. The tree of the matches follows the filter,
# the open nodes of the tree and the labels of the rows that it read.
function Explorer(content::ExplorerSection; filter::ExplorerFilter = ExplorerFilter())
    navigator = Navigator(content)
    tree = DocumentTree(content; title = "Explorer", current = () -> get_navigator_page_address(navigator))
    explorer = Explorer(Cell(tree), Cell(navigator), Cell(filter), Cell(nothing))
    set_cell_computation!(getfield(explorer, :matches), () -> _make_match_tree(explorer))
    explorer
end

# A file keeps the section, and a load shows it with the root open, on the page of
# the section, with an empty filter.
pred_arguments(explorer::Explorer) = ((getfield(explorer, :tree)[].root,), Pair{Symbol,Any}[])
make_pred_document(::Type{<:Explorer}, positional, keywords) = Explorer(first(positional))

get_document_title(::Explorer) = "Explorer"
get_document_decoration(::Explorer) = DocumentDecoration(; icon = :folder_tree)

# An explorer holds its tree and its navigator, so the open nodes of the tree and
# the page of the navigator start what they need, such as the read of a folder,
# while the explorer is shown.
acquire_document!(editor, explorer::Explorer) =
    hold_documents!(editor, explorer, Any[getfield(explorer, :tree)[], getfield(explorer, :navigator)[]])

release_document!(editor, explorer::Explorer) =
    release_held_documents!(editor, explorer, Any[getfield(explorer, :tree)[], getfield(explorer, :navigator)[]])

# A file opens beside the explorer it was found in, never over it.
accepts_opened_file(::Explorer) = false

# A duplicate shows the same section, with a tree and a navigator of its own: it
# opens with the root of the tree open, on the page of the section, with a copy of
# the filter, which a person then changes on its own.
has_document_duplicate(::Explorer) = true
function copy_document(::DuplicatePolicy, explorer::Explorer)
    filter = getfield(explorer, :filter)[]
    copied = ExplorerFilter(; text = filter.text, kinds = Any[kind for kind in filter.kinds])
    Explorer(getfield(explorer, :tree)[].root; filter = copied)
end

# The name a person types into an empty tab to open an explorer: an explorer of
# the root section of the editor.
get_insertion_aliases(::Type{Explorer}) = ["explorer"]
make_insertion_document(::Type{Explorer}) = Explorer(get_session_explorer_content())

"""
    get_session_explorer_content(; editor = find_evaluation_editor()) -> ExplorerSection

The root section of the explorer of the session of `editor`: by default the
editor of the evaluation, or of the loop that runs the calling code. Each editor
has its own, made at the first call: the section that an explorer in a tab of its
window shows, or else a new empty section. With no editor, such as a script that
runs outside every window, a new section, which nothing keeps.

Use it to read or change the entries that every explorer of the window shows.

# Example

    content_1 = get_session_explorer_content()
    [format_tree_node_label(entry) for entry in content_1.entries]

See also `Explorer` and `ExplorerSection`.
"""
function get_session_explorer_content end

get_session_explorer_content(; editor = find_evaluation_editor()) =
    editor isa Editor ?
        get_session_document!(() -> something(_find_window_explorer_content(editor),
                                              ExplorerSection("Explorer")),
                              editor, ExplorerSection) :
        ExplorerSection("Explorer")

# The root section of an explorer in a tab of the window of `editor`, or `nothing`
# when no tab holds an explorer.
function _find_window_explorer_content(editor::Editor)
    tree = try
        get_window_tree(getfield(editor, :document))
    catch
        nothing
    end
    tree isa PaneTree || return nothing
    for group in get_pane_groups(tree), tab in group.tabs
        found = search_documents(tab.content, document -> document isa Explorer;
                                 maxdepth = _EXPLORER_SEARCH_DEPTH, descend = _is_held_document)
        isempty(found) || return getfield(first(found), :tree)[].root
    end
    nothing
end

# How many documents down the content of a tab the search for an explorer goes: a
# history, a scroll pane and the explorer.
const _EXPLORER_SEARCH_DEPTH = 3

# The search enters a document that a field holds, and no collection, so it reads
# no lazy part of a content.
_is_held_document(_, child) = child isa Document && !is_element_collection(child)

"""
    find_explorer_content(; editor = get_evaluation_editor()) -> ReferencedDocument or nothing

The root section of the explorer of the window, as a part of the window: it acts
like the section and carries its complete reference from the root, through the
first tab that shows an explorer of it. So a verb that edits a collection edits
its entries as a person does, and undo takes the edit back. `nothing` when no tab
shows the explorer.

Use it to read the entries of the explorer, to add a document to it, such as a
dashboard, and to find an entry for `describe_commands` and `open_explorer_page!`.

# Example

    content_1 = find_explorer_content()
    [format_tree_node_label(entry) for entry in content_1.entries]
    insert_elements!(content_1.entries, length(content_1.entries) + 1,
                     [Dashboard("Queue study", [DashboardCard("Tasks", get_session_task_group_list())])])

See also `ExplorerSection`, `Dashboard`, `describe_commands`, `open_explorer_page!`.
"""
function find_explorer_content end

function find_explorer_content(; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "find_explorer_content") do
        root = getfield(editor, :document)
        content = get_session_explorer_content(; editor)
        is_shown = document -> document isa Explorer && getfield(document, :tree)[].root === content
        for tab_reference in search_references(root, node -> node isa PaneTab; descend = is_pane_search_step,
                                               limit = nothing)
            tab = evaluate_reference(root, tab_reference)
            for found in search_references(tab.content, is_shown; maxdepth = _EXPLORER_SEARCH_DEPTH,
                                           descend = _is_held_document, limit = 1)
                steps = (get_reference_steps(strip_reference_types(tab_reference))..., FieldReferenceStep("content"),
                         get_reference_steps(strip_reference_types(found))...,
                         FieldReferenceStep("tree"), FieldReferenceStep("root"))
                return ReferencedDocument(content, annotate_reference_types(root, _make_steps(steps...)))
            end
        end
        nothing
    end
end

"""
    open_explorer_page!(part; editor = get_evaluation_editor()) -> Text

Show the page of `part` in the navigator of the explorer, beside its tree, and open
the rows of the tree above it so its row shows, as a press on a link on a page
does. The selection of the person does not move. `part` is a node of the content
of the explorer, such as an entry of [`find_explorer_content`](@ref), or a part of
a document that an entry holds, such as a task group of the task list, also when
another tab shows it. A part that the explorer does not hold is refused: add its
document to the explorer first.

Use it to show the person a document in the explorer, such as a new dashboard, in
place of a new tab.

# Example

    content_1 = find_explorer_content()
    open_explorer_page!(content_1.entries[1])

See also `find_explorer_content`, `open_page!`.
"""
function open_explorer_page! end

function open_explorer_page!(part::ReferencedDocument; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "open_explorer_page!") do
        content = find_explorer_content(; editor)
        content === nothing && throw(ArgumentError("No tab of the window shows the explorer."))
        address = _find_explorer_address(editor, content, part)
        address === nothing &&
            throw(ArgumentError("The explorer holds no " * describe_document(part) * ". Add it to the explorer " *
                                "first, with an insert into `find_explorer_content().entries`."))
        steps = get_reference_steps(strip_reference_types(get_reference(content)))
        place = annotate_reference_types(getfield(editor, :document), _make_steps(steps[1:(end - 2)]...))
        explorer = evaluate_reference(getfield(editor, :document), place)
        operations = Any[]
        visit = make_navigator_open_operation(getfield(explorer, :navigator)[], address)
        visit === nothing || push!(operations, _get_visit_writes(visit))
        reveal = make_tree_reveal_operation(getfield(explorer, :tree)[], address)
        reveal === nothing || push!(operations, reveal)
        isempty(operations) && return nothing
        rooted = read_rooted_operation(editor, place, CompoundOperation(operations);
                                       description = "Show " * describe_document(part) * " in the explorer")
        rooted === nothing && throw(ArgumentError("The window can not show this part in the explorer."))
        evaluate_operation(editor, rooted)
    end
    Text("The explorer shows the page of " * describe_document(part) * ".")
end

# The path of `part` from the root section `content` of the explorer: the rest of
# its reference when the reference goes through the section; else the path where
# an entry holds the nearest document on the reference of the part
# (`find_navigator_address`), with the rest of the reference after that document;
# `nothing` when the section holds none of them.
function _find_explorer_address(editor, content::ReferencedDocument, part::ReferencedDocument)
    prefix = get_reference_steps(strip_reference_types(get_reference(content)))
    steps = collect(get_reference_steps(strip_reference_types(get_reference(part))))
    length(steps) >= length(prefix) && steps[1:length(prefix)] == collect(prefix) &&
        return _make_steps(steps[(length(prefix) + 1):end]...)
    nodes = Any[getfield(editor, :document)]
    for step in steps
        node = try_evaluate_reference(nodes[end], extend_reference(EmptyReference(), step), missing)
        node === missing && break
        push!(nodes, node)
    end
    for count in (length(nodes) - 1):-1:1
        nodes[count + 1] isa Document || continue
        held = find_navigator_address(get_document(content), nodes[count + 1])
        held === nothing ||
            return concat_references(strip_reference_types(held), _make_steps(steps[(count + 1):end]...))
    end
    nothing
end
