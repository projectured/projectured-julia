"""
    FileSystemModule

This slice of `ProjecturedPlatform` holds the documents of the file system —
`FileSystemFile` (leaf) and `FileSystemDirectory` (node holding `elements` in
a `CellVector`). Both carry their `pathname` as identity.

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
using ..EventModule
using ..FileFormatModule
using ..FocusModule
using ..GestureBindingModule
using ..GestureModule
using ..GraphicsModule
using ..IntentModule
using ..IoMapModule
using ..NaturalModule
using ..OperationModule
using ..PaneModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule
using ..SerializationModule
using ..SettingsManagingModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule
using ..UndoModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title, has_document_duplicate
import ..DomainModule: get_insertion_aliases, make_insertion_document, accepts_opened_file
import ..OperationModule: evaluate_operation
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..SerializationModule: make_pred_document

export FileSystemDocument, make_filesystem_pathname, OpenFileOperation
export FileSystemTheme, ScaledFileSystemTheme
export FileSystemFileToSyntaxLeaf, FileSystemDirectoryToSyntaxNode, FileSystemToSyntax,
       is_filesystem_marker_eligible
export FileSystemToWidgetTree, FileSystemToWidget
export FileSystemFile, FileSystemDirectory
export FileSystemChooser, make_filesystem_chooser, get_chosen_path
export FileSystemChooserToWidget, WriteChosenNameOperation
export WorkspaceDocument, Workspace, WorkspaceFolder
export WorkspaceFolderToFileSystemDirectory, WorkspaceToFileSystem


include("FileSystemDocument.jl")
include("Workspace.jl")
include("WorkspaceToFileSystem.jl")
include("FileSystemTheme.jl")
include("FileSystemToSyntax.jl")
include("FileSystemToWidget.jl")
include("FileSystemChooserToWidget.jl")

end # module
