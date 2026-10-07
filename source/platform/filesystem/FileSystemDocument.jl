# Fragment of `FileSystemModule` — the file-system document types: the abstract
# `FileSystemDocument`, its insertion placeholder, and the file and directory
# nodes.

abstract type FileSystemDocument <: Document end

# ── FileSystemInsertion ─────────────────────────────────────────────────

@document struct FileSystemInsertion <: FileSystemDocument
    value::Any = nothing
end

# ── File ──────────────────────────────────────────────────────────────────────

@document struct FileSystemFile <: FileSystemDocument
    pathname::String
end


# ── Directory ─────────────────────────────────────────────────────────────────

@document struct FileSystemDirectory <: FileSystemDocument
    pathname::String
    elements::CellVector
end


# ── Choose a path ─────────────────────────────────────────────────────────────

"""
A place to choose a path: a `directory` to look in, and a `name` a person types.

It is the document behind Open and Save As. It **chooses a path and does nothing
with one**: a path that does not exist yet is a name typed into a directory,
which is what Save As is for, and a path that does exist is a row of the tree,
which is what Open is for. What happens to the chosen path belongs to whoever
opened the chooser.

`name` is the whole of what a person types. A directory row sets `directory` and
a file row sets `name`, so the two together always say one path, and
[`get_chosen_path`](@ref) is that path.
"""
@document struct FileSystemChooser <: FileSystemDocument
    directory::Document
    name::AbstractString = ""
end

"""
    get_chosen_path(chooser) -> String

The path `chooser` names: its directory and the name typed in it. An empty name
answers the directory itself, because a person who has typed nothing has chosen
no file.
"""
get_chosen_path(chooser::FileSystemChooser) =
    isempty(chooser.name) ? chooser.directory.pathname :
                            joinpath(chooser.directory.pathname, chooser.name)

"""
    make_filesystem_chooser(directory) -> FileSystemChooser

A chooser over the directory at `directory`, read from disk.
"""
make_filesystem_chooser(directory::AbstractString) =
    FileSystemChooser(make_filesystem_pathname(abspath(directory)))

# ── Open a file ───────────────────────────────────────────────────────────────

"""
    OpenFileOperation(path; wrap = identity, file_wrap = identity)

Names a file to open at `path`. This slice draws a file tree; it does not know
where an opened file goes — a tab, a pane, a page — so it names the intent and
nothing else. The slice that knows the destination defines
`evaluate_operation` for it.

`wrap` is applied to the content that the file document holds, and `file_wrap`
to the file document: an opener puts a part of its own around the file there,
such as a navigator. When the editor has settings, the evaluation of the open
gives the file a history, whatever started the open: around the part that
`file_wrap` makes, so it records every edit of that part, and else around the
content, inside the file, as a file tab has it.
"""
struct OpenFileOperation <: Operation
    path::String
    wrap::Any
    file_wrap::Any
end

OpenFileOperation(path::AbstractString; wrap = identity, file_wrap = identity) =
    OpenFileOperation(String(path), wrap, file_wrap)

# It carries its own subject and names no reference, so every reader between
# the gesture and the editor passes it up unchanged.
OperationModule.is_self_contained_operation(::OpenFileOperation) = true

# The destination is a pane tree, in a new tab: `make_file_tab` reads the file into
# the document type its extension owns, in a scroll pane, and `get_pane_file_group`
# asks the pane tree where a file belongs. An editor with settings gives the file a
# history (`make_history_wrap`), around the part that the opener puts around the
# file, or around the content. This runs while the editor evaluates the open, so
# the new tab is posted, and the loop evaluates it at the top of the next frame.
function evaluate_operation(editor, op::OpenFileOperation)
    settings = find_editor_settings(; editor)
    history = settings === nothing ? identity : make_history_wrap(settings)
    tab = op.file_wrap === identity ?
          make_file_tab_content(op.path, document -> history(op.wrap(document))) :
          WidgetScrollPane(history(op.file_wrap(make_file_tab(op.path, op.wrap))))
    post_pane_operation!(editor, make_open_pane_operation(tab; group = get_pane_file_group(; editor), editor))
    nothing
end


# ── API ───────────────────────────────────────────────────────────────────────

"""
    make_filesystem_pathname(pathname) -> FileSystemDocument

The file or the folder at `pathname`. A folder is read at the first read of its
`elements`, and each entry at its own first read: a read of the length is one
`readdir`, and a read of an entry is one `isdir` of it. A folder that nothing
reads costs one `isdir`. A folder is read once and not watched.
"""
function make_filesystem_pathname(pathname::AbstractString)
    p = String(pathname)
    isdir(p) || return FileSystemFile(p)
    FileSystemDirectory(p, CellVector(@computation(_read_folder_names(p));
                                      element = name -> make_filesystem_pathname(joinpath(p, name))))
end

# The names in the folder at `p`. A folder that can not be read, because of a
# permission or because it is gone, has no names.
function _read_folder_names(p::String)
    try
        readdir(p)
    catch exception
        exception isa Base.IOError || rethrow()
        String[]
    end
end
