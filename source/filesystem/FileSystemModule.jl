"""
    FileSystemModule

The file-system document domain — `FileSystemFile` (leaf) and
`FileSystemDirectory` (node holding `elements` in a `CellVector`). Both carry
their `pathname` as identity.

`Workspace` groups one or more named folder roots (`WorkspaceFolder`) into a
single container; `WorkspaceToFileSystem` projects it onto a file-system tree.
A workspace is the tool view a person opens by typing `explorer`, seeded with
the working directory. `OpenFileOperation` names a file to open without
naming where: the slice that knows the destination defines
`evaluate_operation` for it.
"""
module FileSystemModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EventPatternModule
using ..GestureBindingModule
using ..IoMapModule
using ..NaturalModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SerializationModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title
import ..DomainModule: get_insertion_aliases, make_insertion_document
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..SerializationModule: make_pred_document

export FileSystemDocument, make_filesystem_pathname, OpenFileOperation
export FileSystemFileToSyntaxLeaf, FileSystemDirectoryToSyntaxNode, FileSystemToSyntax,
       is_filesystem_marker_eligible
export FileSystemToWidgetTree, FileSystemToWidget
export FileSystemFile, FileSystemDirectory
export WorkspaceDocument, Workspace, WorkspaceFolder
export WorkspaceFolderToFileSystemDirectory, WorkspaceToFileSystem


include("FileSystemDocument.jl")
include("Workspace.jl")
include("WorkspaceToFileSystem.jl")
include("FileSystemToSyntax.jl")
include("FileSystemToWidget.jl")

end # module
