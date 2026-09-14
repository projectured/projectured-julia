"""
    FileSystemModule

The file-system document domain — `FileSystemFile` (leaf) and
`FileSystemDirectory` (node holding `elements` in a `CellVector`). Both carry
their `pathname` as identity.
"""
module FileSystemModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..GestureBindingModule
using ..IoMapModule
using ..NaturalModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export FileSystemDocument, make_filesystem_pathname
export FileSystemFileToSyntaxLeaf, FileSystemDirectoryToSyntaxNode, FileSystemToSyntax,
       is_filesystem_marker_eligible
export FileSystemToWidgetTree, FileSystemToWidget
export FileSystemFile, FileSystemDirectory


include("FileSystemDocument.jl")
include("FileSystemToSyntax.jl")
include("FileSystemToWidget.jl")

end # module
