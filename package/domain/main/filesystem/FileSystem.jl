"""
    FileSystemModule

The file-system document domain — `FileSystemFile` (leaf) and
`FileSystemDirectory` (node holding `elements` in a `CellVector`). Both carry
their `pathname` as identity.
"""
module FileSystemModule

import ..CellModule: Cell, ComputedCell
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
export FileSystemDocument, make_filesystem_pathname

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
