"""
    FileSystemModule

The file-system document domain — `FileSystemFile` (leaf) and
`FileSystemDirectory` (node holding `elements` in a `CellVector`). Both carry
their `pathname` as identity.
"""
module FileSystemModule

import ..CellModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
export FileSystemDocument, make_filesystem_pathname

abstract type FileSystemDocument <: Document end

# ── FileSystemInsertion ─────────────────────────────────────────────────

@document struct FileSystemInsertion <: FileSystemDocument
    value::Any = nothing
    selection::Reference = nothing
end

# ── File ──────────────────────────────────────────────────────────────────────

@document struct FileSystemFile <: FileSystemDocument
    pathname::String
    selection::Reference = nothing
end


# ── Directory ─────────────────────────────────────────────────────────────────

@document struct FileSystemDirectory <: FileSystemDocument
    pathname::String
    elements::CellVector
    selection::Reference = nothing
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
