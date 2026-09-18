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


# ── Open a file ───────────────────────────────────────────────────────────────

"""
    OpenFileOperation(path; wrap = identity)

Names a file to open at `path`. This slice draws a file tree; it does not know
where an opened file goes — a tab, a pane, a page — so it names the intent and
nothing else. The slice that knows the destination defines
`evaluate_operation` for it.

`wrap` is applied to the file document before anything holds it. It is how an
application gives every file it opens an overlay of its own — a history, say —
without this slice naming one.
"""
struct OpenFileOperation <: Operation
    path::String
    wrap::Any
end

OpenFileOperation(path::AbstractString; wrap = identity) =
    OpenFileOperation(String(path), wrap)

# It carries its own subject and names no reference, so every reader between
# the gesture and the editor passes it up unchanged.
OperationModule.operation_travels_unchanged(::OpenFileOperation) = true

# The destination is a pane tree, in a new tab: `make_file_tab` reads the file
# into the document type its extension owns, and `get_pane_file_group` asks the
# pane tree where a file belongs.
function evaluate_operation(editor, op::OpenFileOperation)
    tab = make_file_tab(op.path, op.wrap)
    open_pane!(editor, tab; group = get_pane_file_group(editor))
    nothing
end


# ── API ───────────────────────────────────────────────────────────────────────

function make_filesystem_pathname(pathname::AbstractString)
    p = String(pathname)
    if isdir(p)
        children = FileSystemDocument[]
        for entry in readdir(p; join=true)
            push!(children, make_filesystem_pathname(entry))
        end
        FileSystemDirectory(p, children)
    else
        FileSystemFile(p)
    end
end
