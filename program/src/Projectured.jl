"""
    Projectured

Root module. Assembles all sub-modules in dependency order and re-exports
the public API. Import this module to access the full pred library.
"""
module Projectured

# ── API (abstract types + function stubs) ────────────────────────────────

include("api/Backend.jl")
include("api/Device.jl")
include("api/Projection.jl")
include("api/Operation.jl")
include("api/Document.jl")
include("api/IoMap.jl")

# ── Infrastructure ────────────────────────────────────────────────────────

include("common/Reactive.jl")
include("common/Document.jl")
include("common/IoMap.jl")

# ── Document types ────────────────────────────────────────────────────────

include("reference/Reference.jl")
include("reference/ReferenceCase.jl")
include("reference/ReferenceBuilder.jl")
include("context/ProjectionContext.jl")
include("common/Operation.jl")
include("document/Collection.jl")
include("document/Font.jl")
include("document/Color.jl")
include("document/Geometry.jl")
include("document/Text.jl")
include("document/Primitive.jl")
include("document/Syntax.jl")
include("document/Graphics.jl")
include("document/Json.jl")
include("document/Math.jl")
include("document/Julia.jl")
include("document/Tabular.jl")
include("document/Table.jl")
include("document/Xml.jl")
include("document/FileSystem.jl")
include("document/Workspace.jl")
include("document/Clipboard.jl")
include("document/Widget.jl")
include("document/Layout.jl")
include("document/Book.jl")
include("document/Conversation.jl")
# LLM backend (used as a field type by `WorkbenchAssistant`). Loads early
# because no document or projection layer depends on it; it only needs
# HTTP/JSON3 (external packages) and access to the Anthropic SSE client.
include("editor/Anthropic.jl")
include("editor/Llm.jl")
include("document/Workbench.jl")
include("document/Image.jl")
include("document/Screen.jl")
include("document/Tooltip.jl")

# ── Higher-order projections ──────────────────────────────────────────────

include("projection/higherorder/Sequential.jl")
include("projection/higherorder/TypeDispatching.jl")
include("projection/higherorder/Recursive.jl")
include("projection/higherorder/Alternative.jl")
include("projection/higherorder/PredicateDispatching.jl")
include("projection/higherorder/ReferenceDispatching.jl")
include("projection/higherorder/Nesting.jl")
include("projection/higherorder/WindowManager.jl")
include("projection/higherorder/TooltipDecorator.jl")

# ── Generic projections ───────────────────────────────────────────────────

include("common/Projection.jl")
include("projection/generic/Preserving.jl")
include("projection/generic/Reversing.jl")
include("projection/generic/Filtering.jl")
include("projection/generic/Sorting.jl")
include("projection/generic/Copying.jl")
include("projection/generic/Invariably.jl")

# ── Devices (needed by projections) ──────────────────────────────────────

include("device/Modifiers.jl")
include("device/Keyboard.jl")
include("device/Mouse.jl")
include("device/EventCase.jl")
include("projection/generic/Focusing.jl")

# ── Primitive projections ─────────────────────────────────────────────────

include("projection/primitive/SyntaxToText.jl")
include("projection/primitive/TextToGraphics.jl")
include("projection/primitive/GraphicsCaching.jl")
include("projection/primitive/JsonToSyntax.jl")
include("projection/primitive/TableToGraphics.jl")
include("projection/primitive/XmlToSyntax.jl")
include("projection/primitive/FileSystemToSyntax.jl")
include("projection/primitive/WorkspaceToFileSystem.jl")
include("projection/primitive/TextToString.jl")
include("projection/primitive/ObjectToSyntax.jl")
include("projection/primitive/WidgetToGraphics.jl")
include("projection/primitive/LayoutToGraphics.jl")
include("projection/primitive/BookToSyntax.jl")
include("projection/primitive/LineNumbering.jl")
include("projection/primitive/WordWrapping.jl")
include("projection/primitive/PrimitiveToSyntax.jl")
include("projection/primitive/PrimitiveToText.jl")
include("projection/primitive/ReferenceToText.jl")
include("projection/primitive/MathToSyntax.jl")
include("projection/primitive/JuliaToSyntax.jl")
include("projection/primitive/CollectionToSyntax.jl")
include("projection/primitive/ConversationToSyntax.jl")
include("projection/primitive/ConversationToWidget.jl")
include("projection/primitive/WorkbenchToWidget.jl")

# ── Compound projections ─────────────────────────────────────────────────

include("projection/compound/HigherOrder.jl")
include("projection/compound/Generic.jl")

# ── Devices, backend, and editor ──────────────────────────────────────────

include("device/Screen.jl")
include("backend/Sdl.jl")
include("editor/ToolRegistry.jl")
include("editor/Mcp.jl")
include("editor/WorkbenchAssistant.jl")
include("editor/Editor.jl")

# ── Public API ────────────────────────────────────────────────────────────

# Import modules with Base extensions to ensure they're loaded when Projectured is imported
# This makes Base method extensions (like getindex for CellVector) available in contexts
# that import Projectured, such as the MCP execution environment.
using .DocumentModule: @document
using .ProjectionModule: @projection
using .IoMapModule: @iomap
using .CollectionModule
using .JsonModule
using .TabularModule
using .TableModule
using .ReferenceModule
using .SyntaxModule
using .FileSystemModule
using .XmlModule
using .TextModule
using .PrimitiveModule
using .MathModule
using .FontModule
using .ColorModule
using .ImageModule
using .ScreenDocumentModule
using .ReactiveModule: Cell, setval!, setfn!, isuptodate
using .ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
using .ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference,
                       TypeReference, FunctionReference, ProjectionReference, PointReference,
                       TextRectangularReference,
                       ReferencePath, EmptyReferencePath,
                       is_valid_reference, evaluate_reference, append_reference, collect_references,
                       is_element_reference, is_position_reference, is_range_reference,
                       reference_equal, is_prefix_of
using .ProjectionContextModule: ProjectionContext, child_context, with_available_size,
                                 with_property, get_property
using .DocumentApiModule: set_selection!, clear_selection!
using .OperationModule: ReplaceSelectionOperation, QuitEditorOperation, replace_selection!,
                        OpenWindowOperation, CloseWindowOperation
using .ReferenceCaseModule: var"@reference_case", when, prefix
using .EventCaseModule: var"@event_case"
using .ReferenceBuilderModule: var"@reference", var"@step"
using .OperationApiModule: Operation, evaluate_operation
using .JsonModule: JsonDocument, JsonInsertion, JsonNull, JsonBool, JsonNumber, JsonString, JsonArray,
                   JsonObject, JsonObjectEntry, jsonvalue, entries
using .TabularModule: TabularDocument, TabularCell, TabularRow, TabularGrid,
                      tabular_cell, tabular_column,
                      insert_row!, delete_row!, insert_column!, delete_column!
using .TableModule: TableDocument, TableCell, TableRow, TableColumn, TableTable
using .XmlModule: XmlDocument, XmlInsertion, XmlText, XmlAttribute, XmlElement, xmlattr,
                  setattr!, deleteattr!
using .FileSystemModule: FileSystemDocument, FileSystemInsertion,
                         FileSystemFile, FileSystemDirectory, make_filesystem_pathname
using .WorkspaceModule: WorkspaceDocument, WorkspaceFolder, Workspace
using .TextModule: TextDocument, TextInsertion, TextText, TextString, TextNewline, TextGraphics
using .PrimitiveModule: PrimitiveDocument, PrimitiveInsertion,
                        PrimitiveBool, PrimitiveNumber, PrimitiveString,
                        NumberReplaceRangeOperation, StringReplaceRangeOperation
using .MathModule: MathDocument, MathInsertion, MathVariable, MathBinaryOperation,
                   MathParenthesized, MathAssignment
using .JuliaModule: JuliaDocument, JuliaIdentifier, JuliaInteger, JuliaBinaryOp, JuliaCall,
                    JuliaIf, JuliaFunction, JuliaBlock
using .SyntaxModule: SyntaxDocument, SyntaxInsertion, SyntaxLeaf, SyntaxNode, render
using .GraphicsModule: GraphicsDocument, GraphicsInsertion,
                       GraphicsText, GraphicsRect, GraphicsCanvas, GraphicsViewport, GraphicsImage,
                       GraphicsFence, LayoutDirection, layout_none, layout_horizontal, layout_vertical,
                       hit_element_at
using .ModifiersModule: Modifiers
using .KeyboardModule: KeyDown, KeyUp, KeyPress, is_ctrl, is_shift, is_alt, is_meta
using .MouseModule: MouseDown, MouseUp, MousePress, MouseMove, MouseScroll
using .BackendModule: Backend, init!, quit!, measure_text
using .SdlBackendModule: SdlBackend, sdl_measure_text, sdl_render_canvas,
                          sdl_display_size,
                          write_image, GraphicsCanvasToImageFile,
                          sdl_decode_image, decode_image_file!
using .DeviceModule: Device, write_to_device, read_from_device, write_to_devices, read_from_devices
using .ScreenModule: Screen, QuitEvent
using .IoMapApiModule: IoMap
using .IoMapModule: SimpleIoMap, ChildrenIoMap, ContentIoMap
using .TypeDispatchingModule: TypeDispatchingProjection
using .RecursiveProjectionModule: RecursiveProjection
using .SequentialProjectionModule: SequentialProjection, SequentialProjectionIoMap
using .AlternativeProjectionModule: AlternativeProjection, AlternativeProjectionIoMap
using .PredicateDispatchingModule: PredicateDispatchingProjection
using .PreservingProjectionModule: PreservingProjection
using .InvariablyProjectionModule: InvariablyProjection
using .ReferenceDispatchingModule: ReferenceDispatchingProjection, ReferenceDispatchingIoMap
using .HigherOrderCompoundModule: ApplyAtProjection
using .GenericCompoundModule: SortingAtProjection
using .NestingProjectionModule: NestingProjection, NestingProjectionIoMap
using .WindowManagerProjectionModule: WindowManagerProjection, WindowManagerProjectionIoMap
using .TooltipDecoratorProjectionModule: TooltipDecoratorProjection, TooltipDecoratorProjectionIoMap
using .ReversingProjectionModule: ReversingProjection
using .FilteringProjectionModule: FilteringProjection, FilteringProjectionIoMap
using .SortingProjectionModule: SortingProjection, SortingProjectionIoMap
using .CopyingProjectionModule: CopyingProjection, CopyingProjectionIoMap
using .FocusingProjectionModule: FocusingProjection, ReplaceFocusPartOperation
using .JsonToSyntaxModule: JsonToSyntax, JsonStringToSyntaxLeaf,
                               JsonNullToSyntaxLeaf, JsonBoolToSyntaxLeaf,
                               JsonNumberToSyntaxLeaf, JsonArrayToSyntaxNode,
                               JsonObjectToSyntaxNode,
                               JsonInsertionToSyntaxLeaf
using .TableToGraphicsModule: TableToGraphics, TableTableToGraphicsCanvas
using .XmlToSyntaxModule: XmlToSyntax, XmlTextToSyntaxLeaf, XmlElementToSyntaxNode
using .FileSystemToSyntaxModule: FileSystemFileToSyntaxLeaf, FileSystemDirectoryToSyntaxNode, FileSystemToSyntax,
                                 filesystem_marker_eligible
using .WorkspaceToFileSystemModule: WorkspaceFolderToFileSystemDirectory, WorkspaceToFileSystem
using .ObjectToSyntaxModule: ObjectToSyntax, NothingToSyntaxLeaf, BoolToSyntaxLeaf,
                              NumberToSyntaxLeaf, StringToSyntaxLeaf, SymbolToSyntaxLeaf,
                              CharToSyntaxLeaf, ObjectNodeToSyntaxNode, print_object
using .BookToSyntaxModule: BookBookToSyntaxNode, BookChapterToSyntaxNode,
                            BookParagraphToSyntaxLeaf, BookListToSyntaxNode,
                            BookPictureToSyntaxLeaf, BookToSyntax
using .ClipboardModule: ClipboardDocument, ClipboardInsertion,
                        ClipboardSlice, ClipboardCollection
using .CollectionModule: CellVector, ListNode, CollectionDocument, left_tail, right_tail, cell_at, take_first_n
using .BookModule: BookDocument, BookInsertion,
                   BookBook, BookChapter, BookParagraph, BookList, BookPicture
using .WorkbenchModule: WorkbenchDocument, WorkbenchInsertion,
                        WorkbenchWorkbench, WorkbenchPage,
                        WorkbenchNavigator, WorkbenchConsole, WorkbenchDescriptor,
                        WorkbenchOperator, WorkbenchSearcher, WorkbenchEvaluator,
                        WorkbenchAssistant,
                        WorkbenchEditor
using .ColorModule: StyleColor
using .GeometryModule: Inset, Point2D,
                      inset_default, inset_size, inset_width, inset_height,
                      inset_top_left, inset_top_right, inset_bottom_left, inset_bottom_right
using .WidgetModule: WidgetDocument, WidgetInsertion,
                     WidgetLabel, WidgetText, WidgetCheckbox, WidgetButton,
                     WidgetTooltip, WidgetMenu, WidgetMenuItem, WidgetComposite,
                     WidgetShell, WidgetTitlePane, WidgetSplitPane, WidgetTabbedPane,
                     WidgetScrollPane, WidgetToolbar, WidgetScrollBar,
                     HideWidgetOperation, ShowWidgetOperation,
                     ScrollWidgetOperation, SelectTabOperation, SetScrollBarValueOperation
using .LayoutModule: LayoutDocument,
                     HorizontalLayout, VerticalLayout, GridLayout, FlowLayout,
                     LayoutConstraint, allocate_axis,
                     layout_min, layout_max, layout_preferred, layout_weight
using .ImageModule: ImageDocument, ImageInsertion, ImageFile, ImageMemory
using .ScreenDocumentModule: ScreenDocument, WindowDocument, EventEnvelope, WindowCloseRequest
using .TooltipDocumentModule: TooltipSource
using .TextToStringModule: TextToString, TextTextToString, TextStringToString, TextNewlineToString
using .TextLineNumberingModule: LineNumbering, TextLineNumbering
using .WordWrappingModule: WordWrapping, WordWrappingIoMap, WrapSeg
using .SyntaxToTextModule: SyntaxToText, SyntaxNodeToTextIoMap,
                                       SyntaxLeafToText, SyntaxListToText
using .PrimitiveToSyntaxModule: PrimitiveToSyntax, PrimitiveBoolToSyntaxLeaf,
                                 PrimitiveNumberToSyntaxLeaf, PrimitiveStringToSyntaxLeaf
using .PrimitiveToTextModule: PrimitiveToText, PrimitiveBoolToText,
                               PrimitiveNumberToText, PrimitiveStringToText
using .ReferenceToTextModule: ReferenceToText, ReferenceToHumanReadableText
using .MathToSyntaxModule: MathToSyntax, MathInsertionToSyntaxLeaf, MathVariableToSyntaxLeaf,
                            MathBinaryOperationToSyntaxNode, MathParenthesizedToSyntaxNode,
                            MathAssignmentToSyntaxNode
using .JuliaToSyntaxModule: JuliaToSyntax, JuliaIdentifierToSyntaxLeaf, JuliaIntegerToSyntaxLeaf,
                             JuliaBinaryOpToSyntaxNode, JuliaCallToSyntaxNode,
                             JuliaIfToSyntaxNode, JuliaFunctionToSyntaxNode,
                             JuliaBlockToSyntaxNode
using .CollectionToSyntaxModule: CollectionToSyntax, CollectionCellVectorToSyntax,
                                  CollectionListNodeToSyntax
using .TextToGraphicsModule: TextToGraphics, TextToGraphicsIoMap
using .LayoutToGraphicsModule: HorizontalLayoutToGraphicsCanvas,
                               VerticalLayoutToGraphicsCanvas,
                               GridLayoutToGraphicsCanvas,
                               FlowLayoutToGraphicsCanvas,
                               LayoutConstraintToGraphicsCanvas,
                               LayoutToGraphics
using .WidgetToGraphicsModule: WidgetLabelToGraphicsCanvas, WidgetTextToGraphicsCanvas,
                               WidgetCheckboxToGraphicsCanvas, WidgetButtonToGraphicsCanvas,
                               WidgetTooltipToGraphicsCanvas, WidgetMenuToGraphicsCanvas,
                               WidgetMenuItemToGraphicsCanvas, WidgetCompositeToGraphicsCanvas,
                               WidgetShellToGraphicsCanvas, WidgetTitlePaneToGraphicsCanvas,
                               WidgetSplitPaneToGraphicsCanvas, WidgetTabbedPaneToGraphicsCanvas,
                               WidgetScrollPaneToGraphicsCanvas, WidgetScrollPaneToGraphicsCanvasIoMap,
                               WidgetToolbarToGraphicsCanvas, WidgetScrollBarToGraphicsCanvas,
                               WidgetToGraphics,
                               WidgetScrollPaneToGraphicsViewport, WidgetScrollPaneToGraphicsViewportIoMap
using .WorkbenchToWidgetModule: WorkbenchWorkbenchToWidgetShell,    WorkbenchWorkbenchToWidgetShellIoMap,
                                WorkbenchPageToWidgetTabbedPane,    WorkbenchPageToWidgetTabbedPaneIoMap,
                                WorkbenchNavigatorToWidgetScrollPane, WorkbenchNavigatorToWidgetScrollPaneIoMap,
                                WorkbenchConsoleToWidgetScrollPane,
                                WorkbenchDescriptorToWidgetScrollPane,
                                WorkbenchOperatorToWidgetScrollPane,
                                WorkbenchSearcherToWidgetScrollPane,
                                WorkbenchEvaluatorToWidgetScrollPane,
                                WorkbenchAssistantToWidgetSplitPane,
                                WorkbenchEditorToWidgetScrollPane,
                                WorkbenchToWidget
using .GraphicsCachingModule: GraphicsCanvasToGraphicsImage, GraphicsCaching
using .EditorModule: Editor, run!
using .McpModule: McpServer, mcp_start!, mcp_stop!
using .ToolRegistryModule: Tool, Resource,
                            register_tool!, register_tools!, list_tools, call_tool,
                            register_resource!, register_resources!, list_resources, read_resource,
                            anthropic_tool_schema, mcp_tools, mcp_resources
using .AnthropicModule: stream_message
using .LlmModule: LlmBackend, AnthropicLlm, FakeLlm, stream_turn
using .ConversationModule: ConversationDocument, ConversationConversation,
                            ConversationMessage,
                            ConversationUserMessage, ConversationAssistantMessage,
                            ConversationCodeExecution,
                            ConversationBlock,
                            ConversationTextBlock, ConversationCodeBlock,
                            ConversationHeadingBlock, ConversationListBlock
using .ConversationToSyntaxModule: ConversationToSyntax,
                                    ConversationConversationToSyntaxNode,
                                    ConversationUserMessageToSyntaxNode,
                                    ConversationAssistantMessageToSyntaxNode,
                                    ConversationCodeExecutionToSyntaxNode,
                                    ConversationTextBlockToSyntaxLeaf,
                                    ConversationCodeBlockToSyntaxNode,
                                    ConversationHeadingBlockToSyntaxLeaf,
                                    ConversationListBlockToSyntaxNode
using .ConversationToWidgetModule: ConversationToWidget,
                                    ConversationConversationToWidgetComposite,
                                    ConversationUserMessageToWidgetComposite,
                                    ConversationAssistantMessageToWidgetComposite,
                                    ConversationCodeExecutionToWidgetComposite,
                                    ConversationTextBlockToText,
                                    ConversationCodeBlockToWidget,
                                    ConversationHeadingBlockToText,
                                    ConversationListBlockToWidgetComposite
using .WorkbenchAssistantModule: SubmitProseOperation, SubmitJuliaOperation,
                                   ClearInputOperation, ResetConversationOperation,
                                   build_messages, assistant_tool_schemas,
                                   dispatch_assistant_tool, parse_markdown_blocks

export @document, @projection, @iomap
export Cell, setval!, setfn!, isuptodate, take_first_n
export projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
export ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, TypeReference,
       FunctionReference, ProjectionReference, PointReference, ReferencePath, EmptyReferencePath,
       is_valid_reference, evaluate_reference, append_reference, collect_references,
       is_element_reference, is_position_reference, is_range_reference,
       reference_equal, is_prefix_of
export ProjectionContext, child_context, with_available_size, with_property, get_property
export set_selection!, clear_selection!, replace_selection!
export @reference_case, when, prefix
export @event_case
export @reference, @step
export ReplaceSelectionOperation
export OpenWindowOperation, CloseWindowOperation
export JsonDocument, JsonInsertion, JsonNull, JsonBool, JsonNumber, JsonString, JsonArray, JsonObject, JsonObjectEntry, jsonvalue, entries
export TabularDocument, TabularCell, TabularRow, TabularGrid,
       tabular_cell, tabular_column,
       insert_row!, delete_row!, insert_column!, delete_column!
export TableDocument, TableCell, TableRow, TableColumn, TableTable
export XmlDocument, XmlInsertion, XmlText, XmlAttribute, XmlElement, xmlattr, setattr!, deleteattr!
export FileSystemDocument, FileSystemInsertion, FileSystemFile, FileSystemDirectory, make_filesystem_pathname
export WorkspaceDocument, WorkspaceFolder, Workspace
export TextDocument, TextInsertion, TextText, TextString, TextNewline, TextGraphics
export StyleFont, make_style_font
export font_inconsolata_regular_18
export font_ubuntu_monospace_regular_14, font_ubuntu_monospace_italic_14, font_ubuntu_monospace_bold_14
export font_ubuntu_monospace_regular_16, font_ubuntu_monospace_italic_16, font_ubuntu_monospace_bold_16
export font_ubuntu_monospace_regular_18, font_ubuntu_monospace_italic_18, font_ubuntu_monospace_bold_18
export font_ubuntu_monospace_regular_20, font_ubuntu_monospace_italic_20, font_ubuntu_monospace_bold_20
export font_ubuntu_monospace_regular_22, font_ubuntu_monospace_italic_22, font_ubuntu_monospace_bold_22
export font_ubuntu_monospace_regular_24, font_ubuntu_monospace_italic_24, font_ubuntu_monospace_bold_24
export font_ubuntu_monospace_regular_36, font_ubuntu_monospace_italic_36, font_ubuntu_monospace_bold_36
export font_ubuntu_monospace_regular_48, font_ubuntu_monospace_italic_48, font_ubuntu_monospace_bold_48
export font_ubuntu_regular_14, font_ubuntu_italic_14, font_ubuntu_bold_14
export font_ubuntu_regular_16, font_ubuntu_italic_16, font_ubuntu_bold_16
export font_ubuntu_regular_18, font_ubuntu_italic_18, font_ubuntu_bold_18
export font_ubuntu_regular_20, font_ubuntu_italic_20, font_ubuntu_bold_20
export font_ubuntu_regular_22, font_ubuntu_italic_22, font_ubuntu_bold_22
export font_ubuntu_regular_24, font_ubuntu_italic_24, font_ubuntu_bold_24
export font_ubuntu_regular_36, font_ubuntu_italic_36, font_ubuntu_bold_36
export font_liberation_sans_regular_14, font_liberation_sans_italic_14, font_liberation_sans_bold_14
export font_liberation_sans_regular_16, font_liberation_sans_italic_16, font_liberation_sans_bold_16
export font_liberation_sans_regular_18, font_liberation_sans_italic_18, font_liberation_sans_bold_18
export font_liberation_sans_regular_20, font_liberation_sans_italic_20, font_liberation_sans_bold_20
export font_liberation_sans_regular_22, font_liberation_sans_italic_22, font_liberation_sans_bold_22
export font_liberation_sans_regular_24, font_liberation_sans_italic_24, font_liberation_sans_bold_24
export font_liberation_sans_regular_30, font_liberation_sans_italic_30, font_liberation_sans_bold_30
export font_liberation_sans_regular_36, font_liberation_sans_italic_36, font_liberation_sans_bold_36
export font_liberation_serif_regular_14, font_liberation_serif_italic_14, font_liberation_serif_bold_14
export font_liberation_serif_regular_16, font_liberation_serif_italic_16, font_liberation_serif_bold_16
export font_liberation_serif_regular_18, font_liberation_serif_italic_18, font_liberation_serif_bold_18
export font_liberation_serif_regular_20, font_liberation_serif_italic_20, font_liberation_serif_bold_20
export font_liberation_serif_regular_22, font_liberation_serif_italic_22, font_liberation_serif_bold_22
export font_liberation_serif_regular_24, font_liberation_serif_italic_24, font_liberation_serif_bold_24
export font_liberation_serif_regular_30, font_liberation_serif_italic_30, font_liberation_serif_bold_30
export font_liberation_serif_regular_36, font_liberation_serif_italic_36, font_liberation_serif_bold_36
export font_liberation_serif_regular_42, font_liberation_serif_italic_42, font_liberation_serif_bold_42
export font_dejavu_monospace_regular_14, font_dejavu_monospace_italic_14, font_dejavu_monospace_bold_14
export font_dejavu_monospace_regular_16, font_dejavu_monospace_italic_16, font_dejavu_monospace_bold_16
export font_dejavu_monospace_regular_18, font_dejavu_monospace_italic_18, font_dejavu_monospace_bold_18
export font_dejavu_monospace_regular_20, font_dejavu_monospace_italic_20, font_dejavu_monospace_bold_20
export font_dejavu_monospace_regular_22, font_dejavu_monospace_italic_22, font_dejavu_monospace_bold_22
export font_dejavu_monospace_regular_24, font_dejavu_monospace_italic_24, font_dejavu_monospace_bold_24
export font_dejavu_monospace_regular_36, font_dejavu_monospace_italic_36, font_dejavu_monospace_bold_36
export font_dejavu_monospace_regular_48, font_dejavu_monospace_italic_48, font_dejavu_monospace_bold_48
export font_dejavu_sans_regular_14, font_dejavu_sans_italic_14, font_dejavu_sans_bold_14
export font_dejavu_sans_regular_16, font_dejavu_sans_italic_16, font_dejavu_sans_bold_16
export font_dejavu_sans_regular_18, font_dejavu_sans_italic_18, font_dejavu_sans_bold_18
export font_dejavu_sans_regular_20, font_dejavu_sans_italic_20, font_dejavu_sans_bold_20
export font_dejavu_sans_regular_22, font_dejavu_sans_italic_22, font_dejavu_sans_bold_22
export font_dejavu_sans_regular_24, font_dejavu_sans_italic_24, font_dejavu_sans_bold_24
export font_dejavu_sans_regular_36, font_dejavu_sans_italic_36, font_dejavu_sans_bold_36
export PrimitiveDocument, PrimitiveInsertion,
       PrimitiveBool, PrimitiveNumber, PrimitiveString,
       NumberReplaceRangeOperation, StringReplaceRangeOperation
export MathDocument, MathInsertion, MathVariable, MathBinaryOperation,
       MathParenthesized, MathAssignment
export JuliaDocument, JuliaIdentifier, JuliaInteger, JuliaBinaryOp, JuliaCall,
       JuliaIf, JuliaFunction, JuliaBlock
export SyntaxDocument, SyntaxInsertion, SyntaxLeaf, SyntaxNode, render
export GraphicsDocument, GraphicsInsertion,
       GraphicsText, GraphicsRect, GraphicsCanvas, GraphicsViewport, GraphicsImage,
       GraphicsFence, LayoutDirection, layout_none, layout_horizontal, layout_vertical, hit_element_at
export Modifiers
export KeyDown, KeyUp, KeyPress, is_ctrl, is_shift, is_alt, is_meta
export MouseDown, MouseUp, MousePress, MouseMove, MouseScroll
export Backend, init!, quit!, measure_text
export Screen
export SdlBackend, sdl_measure_text, sdl_render_canvas, sdl_display_size,
       write_image, GraphicsCanvasToImageFile, sdl_decode_image, decode_image_file!
export Device, write_to_device, read_from_device, write_to_devices, read_from_devices
export IoMap, SimpleIoMap, ChildrenIoMap, ContentIoMap
export TypeDispatchingProjection, RecursiveProjection
export SequentialProjection, SequentialProjectionIoMap
export AlternativeProjection, AlternativeProjectionIoMap
export PredicateDispatchingProjection
export PreservingProjection
export InvariablyProjection
export ReferenceDispatchingProjection, ReferenceDispatchingIoMap
export ApplyAtProjection
export SortingAtProjection
export NestingProjection, NestingProjectionIoMap
export WindowManagerProjection, WindowManagerProjectionIoMap
export TooltipDecoratorProjection, TooltipDecoratorProjectionIoMap
export ReversingProjection
export FilteringProjection, FilteringProjectionIoMap
export SortingProjection, SortingProjectionIoMap
export CopyingProjection, CopyingProjectionIoMap
export FocusingProjection, ReplaceFocusPartOperation
export JsonToSyntax, JsonStringToSyntaxLeaf,
       JsonNullToSyntaxLeaf, JsonBoolToSyntaxLeaf,
       JsonNumberToSyntaxLeaf, JsonArrayToSyntaxNode, JsonObjectToSyntaxNode,
       JsonInsertionToSyntaxLeaf
export TableToGraphics, TableTableToGraphicsCanvas
export XmlToSyntax, XmlTextToSyntaxLeaf, XmlElementToSyntaxNode
export FileSystemFileToSyntaxLeaf, FileSystemDirectoryToSyntaxNode, FileSystemToSyntax, filesystem_marker_eligible
export WorkspaceFolderToFileSystemDirectory, WorkspaceToFileSystem
export ObjectToSyntax, NothingToSyntaxLeaf, BoolToSyntaxLeaf,
       NumberToSyntaxLeaf, StringToSyntaxLeaf, SymbolToSyntaxLeaf,
       CharToSyntaxLeaf, ObjectNodeToSyntaxNode, print_object
export BookBookToSyntaxNode, BookChapterToSyntaxNode,
       BookParagraphToSyntaxLeaf, BookListToSyntaxNode,
       BookPictureToSyntaxLeaf, BookToSyntax
export ClipboardDocument, ClipboardInsertion, ClipboardSlice, ClipboardCollection
export CellVector, ListNode, CollectionDocument, left_tail, right_tail, cell_at
export Inset, StyleColor, Point2D, color_default
export WidgetDocument, WidgetInsertion,
       WidgetLabel, WidgetText, WidgetCheckbox, WidgetButton,
       WidgetTooltip, WidgetMenu, WidgetMenuItem, WidgetComposite,
       WidgetShell, WidgetTitlePane, WidgetSplitPane, WidgetTabbedPane,
       WidgetScrollPane, WidgetToolbar, WidgetScrollBar
export HideWidgetOperation, ShowWidgetOperation, ScrollWidgetOperation, SelectTabOperation, SetScrollBarValueOperation
export Operation, evaluate_operation
export inset_default, inset_size, inset_width, inset_height,
       inset_top_left, inset_top_right, inset_bottom_left, inset_bottom_right
export BookDocument, BookInsertion, BookBook, BookChapter, BookParagraph, BookList, BookPicture
export WorkbenchDocument, WorkbenchInsertion,
       WorkbenchWorkbench, WorkbenchPage,
       WorkbenchNavigator, WorkbenchConsole, WorkbenchDescriptor,
       WorkbenchOperator, WorkbenchSearcher, WorkbenchEvaluator,
       WorkbenchAssistant,
       WorkbenchEditor
export ImageDocument, ImageInsertion, ImageFile, ImageMemory
export ScreenDocument, WindowDocument, EventEnvelope, WindowCloseRequest
export TooltipSource
export TextToString, TextTextToString, TextStringToString, TextNewlineToString
export LineNumbering, TextLineNumbering
export WordWrapping, WordWrappingIoMap, WrapSeg
export SyntaxToText, SyntaxLeafToText, SyntaxListToText
export PrimitiveToSyntax, PrimitiveBoolToSyntaxLeaf,
       PrimitiveNumberToSyntaxLeaf, PrimitiveStringToSyntaxLeaf
export PrimitiveToText, PrimitiveBoolToText,
       PrimitiveNumberToText, PrimitiveStringToText
export ReferenceToText, ReferenceToHumanReadableText
export MathToSyntax, MathInsertionToSyntaxLeaf, MathVariableToSyntaxLeaf,
       MathBinaryOperationToSyntaxNode, MathParenthesizedToSyntaxNode,
       MathAssignmentToSyntaxNode
export JuliaToSyntax, JuliaIdentifierToSyntaxLeaf, JuliaIntegerToSyntaxLeaf,
       JuliaBinaryOpToSyntaxNode, JuliaCallToSyntaxNode,
       JuliaIfToSyntaxNode, JuliaFunctionToSyntaxNode,
       JuliaBlockToSyntaxNode
export CollectionToSyntax, CollectionCellVectorToSyntax, CollectionListNodeToSyntax
export TextToGraphics, WidgetToGraphics
export SyntaxNodeToTextIoMap, TextToGraphicsIoMap
export WidgetLabelToGraphicsCanvas, WidgetTextToGraphicsCanvas,
       WidgetCheckboxToGraphicsCanvas, WidgetButtonToGraphicsCanvas,
       WidgetTooltipToGraphicsCanvas, WidgetMenuToGraphicsCanvas,
       WidgetMenuItemToGraphicsCanvas, WidgetCompositeToGraphicsCanvas,
       WidgetShellToGraphicsCanvas, WidgetTitlePaneToGraphicsCanvas,
       WidgetSplitPaneToGraphicsCanvas, WidgetTabbedPaneToGraphicsCanvas,
       WidgetScrollPaneToGraphicsCanvas, WidgetScrollPaneToGraphicsCanvasIoMap
export WidgetScrollPaneToGraphicsViewport, WidgetScrollPaneToGraphicsViewportIoMap
export LayoutDocument, HorizontalLayout, VerticalLayout, GridLayout, FlowLayout, LayoutConstraint
export allocate_axis, layout_min, layout_max, layout_preferred, layout_weight
export HorizontalLayoutToGraphicsCanvas, VerticalLayoutToGraphicsCanvas,
       GridLayoutToGraphicsCanvas, FlowLayoutToGraphicsCanvas,
       LayoutConstraintToGraphicsCanvas, LayoutToGraphics
export GraphicsCanvasToGraphicsImage, GraphicsCaching
export WorkbenchWorkbenchToWidgetShell,    WorkbenchWorkbenchToWidgetShellIoMap,
       WorkbenchPageToWidgetTabbedPane,    WorkbenchPageToWidgetTabbedPaneIoMap,
       WorkbenchNavigatorToWidgetScrollPane, WorkbenchNavigatorToWidgetScrollPaneIoMap,
       WorkbenchConsoleToWidgetScrollPane,
       WorkbenchDescriptorToWidgetScrollPane,
       WorkbenchOperatorToWidgetScrollPane,
       WorkbenchSearcherToWidgetScrollPane,
       WorkbenchEvaluatorToWidgetScrollPane,
       WorkbenchAssistantToWidgetSplitPane,
       WorkbenchEditorToWidgetScrollPane,
       WorkbenchToWidget
export Editor, run!
export McpServer, mcp_start!, mcp_stop!
export Tool, Resource, register_tool!, register_tools!, list_tools, call_tool,
       register_resource!, register_resources!, list_resources, read_resource,
       anthropic_tool_schema, mcp_tools, mcp_resources
export stream_message
export LlmBackend, AnthropicLlm, FakeLlm, stream_turn
export ConversationDocument, ConversationConversation,
       ConversationMessage,
       ConversationUserMessage, ConversationAssistantMessage,
       ConversationCodeExecution,
       ConversationBlock,
       ConversationTextBlock, ConversationCodeBlock,
       ConversationHeadingBlock, ConversationListBlock
export ConversationToSyntax,
       ConversationConversationToSyntaxNode,
       ConversationUserMessageToSyntaxNode,
       ConversationAssistantMessageToSyntaxNode,
       ConversationCodeExecutionToSyntaxNode,
       ConversationTextBlockToSyntaxLeaf,
       ConversationCodeBlockToSyntaxNode,
       ConversationHeadingBlockToSyntaxLeaf,
       ConversationListBlockToSyntaxNode
export ConversationToWidget,
       ConversationConversationToWidgetComposite,
       ConversationUserMessageToWidgetComposite,
       ConversationAssistantMessageToWidgetComposite,
       ConversationCodeExecutionToWidgetComposite,
       ConversationTextBlockToText,
       ConversationCodeBlockToWidget,
       ConversationHeadingBlockToText,
       ConversationListBlockToWidgetComposite
export SubmitProseOperation, SubmitJuliaOperation,
       ClearInputOperation, ResetConversationOperation,
       build_messages, assistant_tool_schemas, dispatch_assistant_tool,
       parse_markdown_blocks

end # module Projectured
