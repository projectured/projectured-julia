"""
    WorkbenchModule

The workspace document domain. A workspace groups one or more named folder
roots (WorkspaceFolder) into a single container (Workspace). Each folder
carries a display name and a filesystem pathname; the actual directory
contents are produced by projection (WorkspaceFolderToFileSystemDirectory),
not stored in the document.
"""
module WorkbenchModule

import ..CellModule: Cell, ComputedCell
import ..DocumentModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector, ComputedCellVector
import ..ReferenceModule: Reference
export WorkspaceDocument
import ..CellModule: Cell, ComputedCell, set_cell_function!, set_cell_value!
import ..TextModule: TextBlock
import ..PrimitiveModule: PrimitiveString
import ..ConversationModule: ConversationConversation, ConversationTurn, ConversationPart, ConversationDraft
import ..LlmModule: Llm
import ..ReferenceModule: Reference, ConcreteReference, ElementReferenceStep, RangeReferenceStep, EmptyReference, FieldReferenceStep, is_element_reference_step
import ..OperationModule: Operation, evaluate_operation
import ..OperationModule: insert_elements, delete_elements
export WorkbenchDocument, get_workbench_title, set_cell_function!, DEFAULT_ASSISTANT_SYSTEM,
       WorkbenchOpenDocumentOperation, WorkbenchCloseDocumentOperation
import ..ProjectionApiModule: print_document, print_child, read_intent,
                               map_reference_forward, map_reference_backward, Projection
import ..OperationModule: Operation
import ..FileSystemModule: FileSystemDocument, FileSystemFile, FileSystemDirectory, make_filesystem_pathname
import ..IoMapModule: SimpleIoMap, ChildrenIoMap, reconcile_child_iomaps
import ..IoMapModule: IoMap
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..ReferenceModule: ConcreteReference, ElementReferenceStep, FieldReferenceStep
import ..PrinterContextModule: make_child_context
export WorkspaceFolderToFileSystemDirectory, WorkspaceToFileSystem
import ..AssistantModule: Assistant, ASSISTANT_TITLE
import ..AssistantModule: AssistantToWidgetSplitPane, AssistantToWidgetCard
import ..WidgetModule: WidgetDocument, WidgetLabel, WidgetText, WidgetShell, WidgetSplitPane, WidgetTabbedPane,
                       WidgetScrollPane, WidgetComposite, WidgetCard, Point2D, Inset, inset_default,
                       SelectTabOperation
import ..LayoutModule: VerticalLayout
import ..ReferenceModule: Reference, EmptyReference, ConcreteReference,
                          FieldReferenceStep, RangeReferenceStep, get_reference_steps
import ..LayoutModule: LayoutConstraint
import ..TextModule: TextBlock, TextString
import ..StyleModule: font_ubuntu_monospace_regular_20
import ..StyleModule: StyleColor, color_default
import ..IoMapModule: SimpleIoMap, ContentIoMap, ChildrenIoMap,
                      reconcile_child_iomap, reconcile_child_iomaps, var"@iomap"
import ..CellModule: Cell, ComputedCell, set_cell_function!
import ..OperationModule: ReplaceSelectionOperation, ReplaceReferencedValueOperation, CompoundOperation
import ..OperationModule: reroot_operation
import ..PrimitiveModule: ReplaceStringRangeOperation, ReplaceNumberRangeOperation
import ..EventModule: KeyDown, KeyPress
import ..GestureBindingModule: read_gesture
import ..ReferenceModule: Reference, ConcreteReference, ElementReferenceStep, PositionReferenceStep, RangeReferenceStep, EmptyReference, FieldReferenceStep, extend_reference, try_evaluate_reference
import ..ReferenceModule: var"@reference", var"@reference_step"
import ..ReferenceModule: annotate_reference_types
import ..ReferenceModule: var"@reference_case"
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
import ..FileFormatModule: write_document_file, read_document_file
import ..EventModule: KeyDown
import ..GestureBindingModule: var"@gestures"
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
