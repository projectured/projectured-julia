# Fragment of `FileFormatModule` — the open files of an editor: the file document
# of each file that a tab or a page shows, once each. An open of a file that the
# list holds reaches that document, so one file is one document in an editor, and
# the explorer lists the files that are open.

"""
    OpenFileList()

The files that an editor holds open: for each file, the file document that a tab
or a page shows. The acquire of a file document adds it, and the release of its
last holder takes it away, so the list is what the editor shows now. Each editor has its own
([`get_session_open_file_list`](@ref)).

`table` is the table of the files, which the page of the list shows: an
arrangement with no entry around a roster of `files`, with the columns `name`,
`folder` and `state`. A person filters and sorts it in its bar. The list of a
session has it; a list that `OpenFileList()` makes has `nothing`.

Use it to know which files are open and whether they have unsaved edits.

# Example

    [get_document_title(file) for file in get_session_open_file_list().files]

See also `find_open_file_document` and `get_session_open_file_list`.
"""
@document struct OpenFileList <: Document
    files::CellVector = CellVector(Any[])
    table::Any = nothing
end

get_document_title(::OpenFileList) = "Open files"
accepts_pasted_document(::OpenFileList) = false
has_document_duplicate(::OpenFileList) = false

# The open files that have edits that no save wrote.
_count_unsaved_files(list::OpenFileList) =
    count(file -> any(condition -> condition.name in (:unsaved, :conflict), get_document_decoration(file).conditions),
          list.files)

# The list counts its files that have edits that no save wrote.
function get_document_decoration(list::OpenFileList)
    unsaved = _count_unsaved_files(list)
    DocumentDecoration(; icon = :file_stack,
                       counts = unsaved == 0 ? DocumentCount[] : [DocumentCount(string(unsaved, " unsaved"))],
                       tooltip = () -> TooltipNote(; title = "Open files", text = "The files that this editor holds open.",
                                                   facts = ["Open" => string(length(list.files)),
                                                            "Unsaved" => string(unsaved)]))
end

get_tree_children_steps(::OpenFileList) = ((FieldReferenceStep("files"),),)

# A file keeps that a tab shows the list, not the files, which belong to a session.
pred_arguments(::OpenFileList) = (), Pair{Symbol,Any}[]
make_pred_document(::Type{<:OpenFileList}, positional, keywords) = get_session_open_file_list()

"""
    get_session_open_file_list(; editor = find_evaluation_editor()) -> OpenFileList

The open files of the session of `editor`: by default the editor of the
evaluation, or of the loop that runs the calling code. Each editor has its own,
made at the first call with its table. With no editor, a new list, which nothing
fills.

Use it to read the files that a window shows, as the explorer does.

# Example

    length(get_session_open_file_list().files)

See also `find_open_file_document` and `has_unsaved_edits`.

For the assistant.
"""
function get_session_open_file_list end

get_session_open_file_list(; editor = find_evaluation_editor()) =
    editor isa Editor ? get_session_document!(_make_open_file_list, editor, OpenFileList) : _make_open_file_list()

# A list with its table: an arrangement of a roster of the files, whose source is
# the collection at `files` of the list.
function _make_open_file_list()
    list = OpenFileList()
    roster = Roster(CollectionItems(extend_reference(EmptyReference(), FieldReferenceStep("files")));
                    columns = ["name", "folder", "state"], title = "Open files")
    link_roster!(roster, list)
    list.table = ArrangementDocument(roster, ArrangementEntry[])
    list
end

"""
    find_open_file_document(path; editor = find_evaluation_editor()) -> FileDocument or nothing

The file document at `path` that `editor` holds open, or `nothing` when no tab and
no page shows that file. An open of a file asks it
first, so a file that is open is not read a second time.

Use it to reach the document of a file that is open.

# Example

    find_open_file_document("notes.json")

See also `get_session_open_file_list`.

For the assistant.
"""
function find_open_file_document end

function find_open_file_document(path::AbstractString; editor = find_evaluation_editor())
    editor isa Editor || return nothing
    target = abspath(path)
    for file in get_session_open_file_list(; editor).files
        abspath(String(get_filename(file))) == target && return file
    end
    nothing
end

"""
    open_file_document!(path; editor = find_evaluation_editor()) -> FileDocument or nothing

The file document that a held file at `path` gets in `editor`: the one that `editor`
holds open for that file, else a new one that reads nothing and reads the file when a
view of it is drawn, with the history of the settings of the editor around its
content. A new one is in the open files of the editor at once. It is not shown: the
view of a file draws it, and the call places it in no tab. `nothing` when no editor
opens it, so a load with no editor keeps each reference to a file as it is.

Use it to get the editor's one document of a file, to hold it in a card or a record
and to show it without a tab.

# Example

    file_1 = open_file_document!("notes.md")
    content_1 = find_explorer_content()
    insert_elements!(content_1.entries, length(content_1.entries) + 1,
                     [Dashboard("Notes", [DashboardCard("notes.md", file_1)])])

See also `open_file!`, `find_open_file_document`, `find_explorer_content`.

For the assistant.
"""
function open_file_document! end

open_file_document!(path::AbstractString; editor = find_evaluation_editor()) = open_file_document!(editor, path)

# A load calls it with the editor that loads; the default opens nothing.
open_file_document!(editor, path::AbstractString) = nothing

"""
    collect_open_file_paths(; editor = find_evaluation_editor()) -> Vector{String}

The absolute paths of the files that `editor` holds open, in the order of its
list of open files.
"""
function collect_open_file_paths end

function collect_open_file_paths(; editor = find_evaluation_editor())
    editor isa Editor || return String[]
    paths = String[]
    for file in get_session_open_file_list(; editor).files
        push!(paths, abspath(String(get_filename(file))))
    end
    paths
end

"""
    find_shown_file_path(content) -> String | Nothing

The absolute path of the file that `content`, the content of a tab, shows,
through the layers that hold it, such as a view, a navigator and a scroll pane, or
`nothing` when it shows no file or a file with no name.
"""
function find_shown_file_path(content)
    file = _find_shown_file(content)
    file === nothing && return nothing
    name = String(get_filename(file))
    isempty(name) ? nothing : abspath(name)
end

# The list takes `file`, unless it holds it already.
function add_open_file!(editor, file)
    editor isa Editor || return nothing
    list = get_session_open_file_list(; editor)
    any(listed -> listed === file, list.files) || push!(list.files, file)
    nothing
end

# The list lets `file` go, once nothing holds it.
function remove_open_file!(editor, file)
    editor isa Editor || return nothing
    files = get_session_open_file_list(; editor).files
    index = findfirst(listed -> listed === file, collect(files))
    index === nothing || deleteat!(files, index)
    nothing
end
