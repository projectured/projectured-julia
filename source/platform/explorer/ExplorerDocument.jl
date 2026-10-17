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

Use it as the root of an [`Explorer`](@ref), and to group the entries in it.

# Example

    section_1 = ExplorerSection("Tools", Any[get_session_task_group_list()])

See also `Explorer` and `get_session_explorer_content`.
"""
@document struct ExplorerSection <: Document
    title::String
    entries::CellVector = CellVector(Any[])
end

get_document_title(section::ExplorerSection) = section.title

get_tree_children_steps(::ExplorerSection) = ((FieldReferenceStep("entries"),),)
format_tree_node_label(section::ExplorerSection) = section.title
get_document_decoration(::ExplorerSection) = DocumentDecoration(; icon = :layers)

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
