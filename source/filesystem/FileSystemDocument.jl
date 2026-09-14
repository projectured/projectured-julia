"""
    FileSystemModule

The file-system document domain — `FileSystemFile` (leaf) and
`FileSystemDirectory` (node holding `elements` in a `CellVector`). Both carry
their `pathname` as identity.
"""
module FileSystemModule

using ..CellModule
using ..DocumentModule
using ..CollectionModule
using ..ReferenceModule
export FileSystemDocument, make_filesystem_pathname
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
using ..ProjectionModule
using ..TextModule
using ..StyleModule
using ..SyntaxModule
using ..ProjectionAlgebraModule
using ..IoMapModule
using ..OperationModule
using ..PrimitiveModule
using ..PrinterContextModule
export FileSystemFileToSyntaxLeaf, FileSystemDirectoryToSyntaxNode, FileSystemToSyntax,
       is_filesystem_marker_eligible
using ..NaturalModule
using ..WidgetModule
using ..GestureBindingModule
export FileSystemToWidgetTree, FileSystemToWidget
export FileSystemFile, FileSystemDirectory



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


include("FileSystemToSyntax.jl")
include("FileSystemToWidget.jl")

end # module
