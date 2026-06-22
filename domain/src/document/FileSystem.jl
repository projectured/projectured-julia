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
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
export FileSystemDocument, FileSystemInsertion, FileSystemFile, FileSystemDirectory, make_filesystem_pathname,
       IFileSystemInsertion, IFileSystemFile, IFileSystemDirectory

abstract type FileSystemDocument <: Document end

# ── FileSystemInsertion ─────────────────────────────────────────────────

@document struct FileSystemInsertion <: FileSystemDocument
    value::Any
    selection::Reference
end
FileSystemInsertion() = FileSystemInsertion(Cell(nothing), Cell(nothing))

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

# ── Children access ───────────────────────────────────────────────────────────

Base.length(d::FileSystemDirectory)               = length(d.elements)
Base.isempty(d::FileSystemDirectory)              = isempty(d.elements)
Base.getindex(d::FileSystemDirectory, i::Integer) = d.elements[i]
Base.firstindex(::FileSystemDirectory)            = 1
Base.lastindex(d::FileSystemDirectory)            = length(d)
Base.iterate(d::FileSystemDirectory, state...)    = iterate(d.elements, state...)
Base.eachindex(d::FileSystemDirectory)            = eachindex(d.elements)

function Base.push!(d::FileSystemDirectory, items::FileSystemDocument...)
    for item in items
        push!(d.elements, Cell(item))
    end
    return d
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

end # module
