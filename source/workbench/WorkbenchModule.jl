"""
    WorkbenchModule

The workspace document domain. A workspace groups one or more named folder
roots (WorkspaceFolder) into a single container (Workspace). Each folder
carries a display name and a filesystem pathname; the actual directory
contents are produced by projection (WorkspaceFolderToFileSystemDirectory),
not stored in the document.
"""
module WorkbenchModule

using ..AssistantModule
using ..CellModule
using ..CollectionModule
using ..ConversationModule
using ..DocumentModule
using ..EventModule
using ..FileFormatModule
using ..FileSystemModule
using ..GestureBindingModule
using ..IoMapModule
using ..LayoutModule
using ..LlmModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..StyleModule
using ..TextModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..CellModule: set_cell_function!
import ..OperationModule: evaluate_operation
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export WorkspaceDocument
export WorkbenchDocument, get_workbench_title, set_cell_function!, DEFAULT_ASSISTANT_SYSTEM,
       WorkbenchOpenDocumentOperation, WorkbenchCloseDocumentOperation
export WorkspaceFolderToFileSystemDirectory, WorkspaceToFileSystem
export WorkbenchWorkbenchToWidgetShell,    WorkbenchWorkbenchToWidgetShellIoMap,
       WorkbenchPageToWidgetTabbedPane,    WorkbenchPageToWidgetTabbedPaneIoMap,
       WorkbenchNavigatorToWidgetScrollPane, WorkbenchNavigatorToWidgetScrollPaneIoMap,
       WorkbenchConsoleToWidgetScrollPane,
       WorkbenchDescriptorToWidgetScrollPane,
       WorkbenchOperatorToWidgetScrollPane,
       WorkbenchSearcherToWidgetScrollPane,
       WorkbenchEvaluatorToWidgetScrollPane,
       WorkbenchEditorToWidgetScrollPane,
       WorkbenchToWidget
export SaveWorkbenchEditorOperation, ReloadWorkbenchEditorOperation
export Workspace, WorkspaceFolder, WorkbenchWorkbench, WorkbenchPage, WorkbenchEditor


include("Workspace.jl")
include("WorkbenchDocument.jl")
include("WorkspaceToFileSystem.jl")
include("WorkbenchToWidget.jl")
include("WorkbenchFile.jl")

end # module
