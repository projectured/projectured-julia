"""
    FileSystemModule

The file-system document domain. A file-system tree is modelled as two
Document types: FileSystemFile (a leaf) and FileSystemDirectory (a node
whose children are stored in a reactive Cell so structural changes are
tracked). Both carry a plain-String pathname (identity) and a reactive
selection Cell.
"""
module FileSystemModule

import ..ReactiveModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
export FileSystemDocument, FileSystemInsertion, FileSystemFile, FileSystemDirectory, make_filesystem_pathname,
       IFileSystemInsertion, IFileSystemFile, IFileSystemDirectory

abstract type FileSystemDocument <: Document end

# ── FileSystemInsertion ─────────────────────────────────────────────────

@document struct FileSystemInsertion <: FileSystemDocument
    value::Any = nothing
    selection::Reference = nothing
end

# ── File ──────────────────────────────────────────────────────────────────────

@document struct FileSystemFile <: FileSystemDocument
    pathname::String
    selection::Reference
end

FileSystemFile(pathname::AbstractString) = FileSystemFile(String(pathname), Cell(nothing))

# ── Directory ─────────────────────────────────────────────────────────────────

@document struct FileSystemDirectory <: FileSystemDocument
    pathname::String
    elements::CellVector
    selection::Reference
end

FileSystemDirectory(pathname::AbstractString) =
    FileSystemDirectory(String(pathname), CellVector(), Cell(nothing))

FileSystemDirectory(pathname::AbstractString, elements::Vector{<:FileSystemDocument}) =
    FileSystemDirectory(String(pathname), CellVector(Cell[Cell(x) for x in elements]), Cell(nothing))

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

end # module
