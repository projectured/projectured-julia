"""
    WorkbenchModule

The workspace document domain. A workspace groups one or more named folder
roots (WorkspaceFolder) into a single container (Workspace). Each folder
carries a display name and a filesystem pathname; the actual directory
contents are produced by projection (WorkspaceFolderToFileSystemDirectory),
not stored in the document.
"""
module WorkbenchModule

using ..CellModule
import ..CellModule: set_cell_function!
using ..DocumentModule
using ..CollectionModule
using ..ReferenceModule
export WorkspaceDocument
using ..TextModule
using ..PrimitiveModule
using ..ConversationModule
using ..LlmModule
using ..OperationModule
import ..OperationModule: evaluate_operation
export WorkbenchDocument, get_workbench_title, set_cell_function!, DEFAULT_ASSISTANT_SYSTEM,
       WorkbenchOpenDocumentOperation, WorkbenchCloseDocumentOperation
using ..ProjectionModule
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
using ..FileSystemModule
using ..IoMapModule
using ..ProjectionAlgebraModule
export WorkspaceFolderToFileSystemDirectory, WorkspaceToFileSystem
using ..AssistantModule
using ..WidgetModule
using ..LayoutModule
using ..StyleModule
using ..EventModule
using ..GestureBindingModule
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
using ..FileFormatModule
export SaveWorkbenchEditorOperation, ReloadWorkbenchEditorOperation
export Workspace, WorkspaceFolder, WorkbenchWorkbench, WorkbenchPage, WorkbenchEditor



abstract type WorkspaceDocument <: Document end

# ── WorkspaceFolder ──────────────────────────────────────────────────────────

@document struct WorkspaceFolder <: WorkspaceDocument
    name::String
    pathname::String
end


# ── Workspace ────────────────────────────────────────────────────────────────

@document struct Workspace <: WorkspaceDocument
    folders::CellVector = CellVector()
end



include("WorkbenchDocument.jl")
include("WorkspaceToFileSystem.jl")
include("WorkbenchToWidget.jl")
include("WorkbenchFile.jl")

end # module
