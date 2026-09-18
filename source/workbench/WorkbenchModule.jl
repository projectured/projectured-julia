"""
    WorkbenchModule

The workbench application shell: the four-page workbench document
(navigator, editing, information, assistant), its widget projection, and the
file tab (`WorkbenchEditor`) that Ctrl+S saves and Ctrl+O reloads. The
navigator holds a `Workspace`, which is the file-system slice's document —
this module opens one of its files into an editing tab.
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
using ..PaneModule
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

export WorkbenchDocument, get_workbench_title, set_cell_function!, DEFAULT_ASSISTANT_SYSTEM,
       WorkbenchOpenDocumentOperation, WorkbenchCloseDocumentOperation,
       OpenWorkspaceFileOperation, make_workbench_file_editor
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
export WorkbenchWorkbench, WorkbenchPage, WorkbenchEditor


include("WorkbenchDocument.jl")
include("WorkbenchToWidget.jl")
include("WorkbenchFile.jl")

end # module
