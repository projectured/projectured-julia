"""
    FileSystemModule

This slice of `ProjecturedPlatform` holds the documents of the file system —
`FileSystemFile` (leaf) and `FileSystemDirectory` (node holding `elements` in
a `CellVector`). Both carry their `pathname` as identity.

`Workspace` groups one or more named folder roots (`WorkspaceFolder`) into a
single container; `WorkspaceToFileSystem` projects it onto a file-system tree.
A workspace is the tool view a person opens by typing `explorer`, seeded with
the working directory. The slice evaluates `OpenFileOperation`: it reads the
file into the document of its type and opens it in a new tab.
"""
module FileSystemModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EventModule
using ..FileChangeModule
using ..FileFormatModule
using ..FocusModule
using ..GestureBindingModule
using ..GestureModule
using ..GraphicsModule
using ..IntentModule
using ..IoMapModule
using ..LayoutModule
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
using ..TreeModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title, has_document_duplicate, copy_document
import ..DomainModule: get_insertion_aliases, make_insertion_document, accepts_opened_file,
                       acquire_document!, release_document!, get_document_decoration
import ..FileChangeModule: receive_folder_change!
import ..OperationModule: evaluate_operation
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..WidgetModule: make_graphics_projection
import ..SerializationModule: make_pred_document, pred_arguments
import ..TreeModule: get_tree_children_steps, format_tree_node_label, has_tree_children

export FileSystemDocument, make_filesystem_pathname, read_filesystem_folder!, has_folder_entries,
       ApplyFolderListingOperation, ApplyFolderEmptinessOperation
export FileSystemTheme, ScaledFileSystemTheme
export FileSystemFileToSyntaxLeaf, FileSystemDirectoryToSyntaxNode, FileSystemToSyntax,
       is_filesystem_marker_eligible
export FileSystemToWidgetTree, FileSystemToWidget
export FileSystemFile, FileSystemDirectory
export FileSystemChooser, make_filesystem_chooser, get_chosen_path
export FileSystemChooserToWidget, WriteChosenNameOperation
export FileSystemDirectoryToWidget
export WorkspaceDocument, Workspace, WorkspaceFolder, WorkspaceExplorer
export WorkspaceFolderToFileSystemDirectory, WorkspaceToFileSystem


include("FileSystemDocument.jl")
include("Workspace.jl")
include("WorkspaceToFileSystem.jl")
include("FileSystemTheme.jl")
include("FileSystemToSyntax.jl")
include("FileSystemToWidget.jl")
include("FileSystemChooserToWidget.jl")
include("FileSystemTree.jl")
include("FileSystemDirectoryToWidget.jl")

end # module
