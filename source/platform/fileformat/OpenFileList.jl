# Fragment of `FileFormatModule` — the open files of an editor: the page or the
# document of each file that a tab or a page shows, once each. An open of a file
# that the list holds reaches that document, so one file is one document in an
# editor, and the explorer lists the files that are open.

"""
    OpenFileList()

The files that an editor holds open: for each file, the [`FilePage`](@ref) that a
tab or a page shows, or the file document when no page holds it. The acquire of a
file page or a file document adds it, and the release of its last holder takes
it away, so the list is what the editor shows now. Each editor has its own
([`get_session_open_file_list`](@ref)).

Use it to know which files are open and whether they have unsaved edits.

# Example

    [get_document_title(file) for file in get_session_open_file_list().files]

See also `find_open_file_document` and `get_session_open_file_list`.
"""
@document struct OpenFileList <: Document
    files::CellVector = CellVector(Any[])
end

get_document_title(::OpenFileList) = "Open files"
accepts_pasted_document(::OpenFileList) = false
has_document_duplicate(::OpenFileList) = false

# The list counts its files that have edits that no save wrote.
function get_document_decoration(list::OpenFileList)
    unsaved = count(file -> any(condition -> condition.name in (:unsaved, :conflict),
                                get_document_decoration(file).conditions), list.files)
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
made at the first call. With no editor, a new list, which nothing fills.

Use it to read the files that a window shows, as the explorer does.

# Example

    length(get_session_open_file_list().files)

See also `OpenFileList` and `find_open_file_document`.
"""
function get_session_open_file_list end

get_session_open_file_list(; editor = find_evaluation_editor()) =
    editor isa Editor ? get_session_document!(OpenFileList, editor, OpenFileList) : OpenFileList()

"""
    find_open_file_document(path; editor = find_evaluation_editor()) -> FilePage, FileDocument or nothing

The page or the document of the file at `path` that `editor` holds open, or
`nothing` when no tab and no page of it shows that file. An open of a file asks it
first, so a file that is open is not read a second time.

Use it to reach the document of a file that is open.

# Example

    find_open_file_document("notes.json")

See also `OpenFileList`.
"""
function find_open_file_document end

function find_open_file_document(path::AbstractString; editor = find_evaluation_editor())
    editor isa Editor || return nothing
    target = abspath(path)
    for document in get_session_open_file_list(; editor).files
        file = document isa FilePage ? find_page_file(document) : document
        file === nothing || abspath(String(get_filename(file))) == target && return document
    end
    nothing
end

# The list takes `document`, a page or a file, unless it holds it or the page that
# shows it already. A tab acquires its outer layer first, so the page of a file
# comes before the file.
function add_open_file!(editor, document)
    editor isa Editor || return nothing
    list = get_session_open_file_list(; editor)
    for listed in list.files
        listed === document && return nothing
        listed isa FilePage && find_page_file(listed) === document && return nothing
    end
    push!(list.files, document)
    nothing
end

# The list lets `document` go, once nothing holds it.
function remove_open_file!(editor, document)
    editor isa Editor || return nothing
    files = get_session_open_file_list(; editor).files
    index = findfirst(listed -> listed === document, collect(files))
    index === nothing || deleteat!(files, index)
    nothing
end
