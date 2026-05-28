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
include("document/Table.jl")
include("document/Xml.jl")
include("document/FileSystem.jl")
include("document/Clipboard.jl")
include("document/Widget.jl")
include("document/Book.jl")
include("document/Conversation.jl")
include("document/Workbench.jl")
include("document/Image.jl")

# ── Higher-order projections ──────────────────────────────────────────────

include("projection/higherorder/Sequential.jl")
include("projection/higherorder/TypeDispatching.jl")
include("projection/higherorder/Recursive.jl")
include("projection/higherorder/Alternative.jl")
include("projection/higherorder/PredicateDispatching.jl")
include("projection/higherorder/ReferenceDispatching.jl")
include("projection/higherorder/Nesting.jl")

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
include("projection/generic/Focusing.jl")

# ── Primitive projections ─────────────────────────────────────────────────

include("projection/primitive/SyntaxToText.jl")
include("projection/primitive/TextToGraphics.jl")
include("projection/primitive/GraphicsCaching.jl")
include("projection/primitive/JsonToSyntax.jl")
include("projection/primitive/TableToGraphics.jl")
include("projection/primitive/XmlToSyntax.jl")
include("projection/primitive/FileSystemToSyntax.jl")
include("projection/primitive/TextToString.jl")
include("projection/primitive/ObjectToSyntax.jl")
include("projection/primitive/WidgetToGraphics.jl")
include("projection/primitive/BookToSyntax.jl")
include("projection/primitive/LineNumbering.jl")
include("projection/primitive/WordWrapping.jl")
include("projection/primitive/PrimitiveToSyntax.jl")
include("projection/primitive/PrimitiveToText.jl")
include("projection/primitive/MathToSyntax.jl")
include("projection/primitive/JuliaToSyntax.jl")
include("projection/primitive/CollectionToSyntax.jl")
include("projection/primitive/ConversationToWidget.jl")
include("projection/primitive/WorkbenchToWidget.jl")

# ── Compound projections ─────────────────────────────────────────────────

include("projection/compound/HigherOrder.jl")
include("projection/compound/Generic.jl")

# ── Devices, backend, and editor ──────────────────────────────────────────

include("device/Window.jl")
include("backend/Sdl.jl")
include("editor/ToolRegistry.jl")
include("editor/Anthropic.jl")
include("editor/Mcp.jl")
include("editor/WorkbenchAssistant.jl")
include("editor/Editor.jl")
include("editor/Application.jl")

# ── Public API ────────────────────────────────────────────────────────────

# Import modules with Base extensions to ensure they're loaded when Projectured is imported
# This makes Base method extensions (like getindex for CellVector) available in contexts
# that import Projectured, such as the MCP execution environment.
using .DocumentModule: @document
using .ProjectionModule: @projection
using .IoMapModule: @iomap
using .CollectionModule
using .JsonModule
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
using .ReactiveModule: Cell, setval!, setfn!, isuptodate
using .ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
using .ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference,
                       TypeReference, FunctionReference, ProjectionReference, ReferencePath, EmptyReferencePath,
                       is_valid_reference, evaluate_reference, append_reference, collect_references,
                       is_element_reference, is_position_reference, is_range_reference,
                       reference_equal, is_prefix_of
using .DocumentApiModule: set_selection!, clear_selection!
using .OperationModule: ReplaceSelectionOperation, QuitEditorOperation, replace_selection!
using .ReferenceCaseModule: var"@reference_case", when, prefix
using .ReferenceBuilderModule: var"@reference"
using .OperationApiModule: Operation, evaluate_operation
using .JsonModule: JsonDocument, JsonInsertion, JsonForeign, JsonNull, JsonBool, JsonNumber, JsonString, JsonArray,
                   JsonObject, JsonObjectEntry, jsonvalue, entries
using .TableModule: TableDocument, TableCell, TableRow, TableColumn, TableTable
using .XmlModule: XmlDocument, XmlInsertion, XmlForeign, XmlText, XmlAttribute, XmlElement, xmlattr,
                  setattr!, deleteattr!
using .FileSystemModule: FileSystemDocument, FileSystemInsertion, FileSystemForeign,
                         FileSystemFile, FileSystemDirectory, make_filesystem_pathname
using .TextModule: TextDocument, TextInsertion, TextForeign, TextText, TextString, TextNewline
using .PrimitiveModule: PrimitiveDocument, PrimitiveInsertion, PrimitiveForeign,
                        PrimitiveBool, PrimitiveNumber, PrimitiveString,
                        NumberReplaceRangeOperation, StringReplaceRangeOperation
using .MathModule: MathDocument, MathInsertion, MathVariable, MathBinaryOperation,
                   MathParenthesized, MathAssignment
using .JuliaModule: JuliaDocument, JuliaIdentifier, JuliaInteger, JuliaBinaryOp, JuliaCall,
                    JuliaIf, JuliaFunction, JuliaBlock
using .SyntaxModule: SyntaxDocument, SyntaxInsertion, SyntaxForeign, SyntaxLeaf, SyntaxNode, render
using .GraphicsModule: GraphicsDocument, GraphicsInsertion, GraphicsForeign,
                       GraphicsText, GraphicsRect, GraphicsCanvas, GraphicsViewport, GraphicsImage,
                       GraphicsFence, LayoutDirection, layout_none, layout_horizontal, layout_vertical,
                       hit_element_at
using .ModifiersModule: Modifiers
using .KeyboardModule: KeyDown, KeyUp, KeyPress, is_ctrl, is_shift, is_alt, is_meta
using .MouseModule: MouseDown, MouseUp, MousePress, MouseMove, MouseScroll
using .BackendModule: Backend, init!, quit!, open_window!, close_window!, measure_text
using .SdlBackendModule: SdlBackend, sdl_measure_text, sdl_render_canvas,
                          write_image, GraphicsCanvasToImageFile
using .DeviceModule: Device, write_to_device, read_from_device, write_to_devices, read_from_devices
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
using .FileSystemToSyntaxModule: FileSystemFileToSyntaxLeaf, FileSystemDirectoryToSyntaxNode, FileSystemToSyntax
using .ObjectToSyntaxModule: ObjectToSyntax, NothingToSyntaxLeaf, BoolToSyntaxLeaf,
                              NumberToSyntaxLeaf, StringToSyntaxLeaf, SymbolToSyntaxLeaf,
                              CharToSyntaxLeaf, ObjectNodeToSyntaxNode, print_object
using .BookToSyntaxModule: BookBookToSyntaxNode, BookChapterToSyntaxNode,
                            BookParagraphToSyntaxLeaf, BookListToSyntaxNode,
                            BookPictureToSyntaxLeaf, BookToSyntax
using .ClipboardModule: ClipboardDocument, ClipboardInsertion, ClipboardForeign,
                        ClipboardSlice, ClipboardCollection
using .CollectionModule: CellVector, ListNode, CollectionDocument, left_tail, right_tail, cell_at, take_first_n
using .BookModule: BookDocument, BookInsertion, BookForeign,
                   BookBook, BookChapter, BookParagraph, BookList, BookPicture
using .WorkbenchModule: WorkbenchDocument, WorkbenchInsertion, WorkbenchForeign,
                        WorkbenchWorkbench, WorkbenchPage,
                        WorkbenchNavigator, WorkbenchConsole, WorkbenchDescriptor,
                        WorkbenchOperator, WorkbenchSearcher, WorkbenchEvaluator,
                        WorkbenchAssistant,
                        WorkbenchEditor
using .ColorModule: StyleColor
using .GeometryModule: Inset, Point2D,
                      inset_default, inset_size, inset_width, inset_height,
                      inset_top_left, inset_top_right, inset_bottom_left, inset_bottom_right
using .WidgetModule: WidgetDocument, WidgetInsertion, WidgetForeign,
                     WidgetLabel, WidgetText, WidgetCheckbox, WidgetButton,
                     WidgetTooltip, WidgetMenu, WidgetMenuItem, WidgetComposite,
                     WidgetShell, WidgetTitlePane, WidgetSplitPane, WidgetTabbedPane,
                     WidgetScrollPane, WidgetToolbar, WidgetScrollBar,
                     HideWidgetOperation, ShowWidgetOperation,
                     ScrollWidgetOperation, SelectTabOperation, SetScrollBarValueOperation
using .ImageModule: ImageDocument, ImageInsertion, ImageForeign, ImageFile, ImageMemory
using .TextToStringModule: TextToString, TextTextToString, TextStringToString, TextNewlineToString
using .TextLineNumberingModule: LineNumbering, TextLineNumbering
using .TextWordWrappingModule: WordWrapping, TextWordWrapping
using .SyntaxToTextModule: SyntaxToText, SyntaxNodeToTextIoMap,
                                       SyntaxLeafToText, SyntaxListToText
using .PrimitiveToSyntaxModule: PrimitiveToSyntax, PrimitiveBoolToSyntaxLeaf,
                                 PrimitiveNumberToSyntaxLeaf, PrimitiveStringToSyntaxLeaf
using .PrimitiveToTextModule: PrimitiveToText, PrimitiveBoolToText,
                               PrimitiveNumberToText, PrimitiveStringToText
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
                                WorkbenchAssistantToWidgetScrollPane,
                                WorkbenchEditorToWidgetScrollPane,
                                WorkbenchToWidget
using .GraphicsCachingModule: GraphicsCanvasToGraphicsImage, GraphicsCaching
using .ApplicationModule: application
using .McpModule: McpServer, mcp_start!, mcp_stop!
using .ToolRegistryModule: Tool, Resource,
                            register_tool!, register_tools!, list_tools, call_tool,
                            register_resource!, register_resources!, list_resources, read_resource,
                            anthropic_tool_schema, mcp_tools, mcp_resources
using .AnthropicModule: stream_message
using .ConversationModule: ConversationDocument, ConversationConversation,
                            ConversationMessage,
                            ConversationUserMessage, ConversationAssistantMessage,
                            ConversationToolUseMessage, ConversationToolResultMessage,
                            ConversationJuliaInputMessage, ConversationJuliaResultMessage,
                            ConversationBlock,
                            ConversationTextBlock, ConversationCodeBlock,
                            ConversationHeadingBlock, ConversationListBlock,
                            ConversationToolUseBlock
using .ConversationToWidgetModule: ConversationToWidget,
                                    ConversationConversationToWidgetComposite,
                                    ConversationUserMessageToWidgetComposite,
                                    ConversationAssistantMessageToWidgetComposite,
                                    ConversationToolUseMessageToWidgetComposite,
                                    ConversationToolResultMessageToWidgetComposite,
                                    ConversationJuliaInputMessageToWidgetComposite,
                                    ConversationJuliaResultMessageToWidgetComposite,
                                    ConversationTextBlockToText,
                                    ConversationCodeBlockToWidget,
                                    ConversationHeadingBlockToText,
                                    ConversationListBlockToWidgetComposite,
                                    ConversationToolUseBlockToText
using .WorkbenchAssistantModule: SubmitProseOperation, SubmitJuliaOperation,
                                   ClearInputOperation, ResetConversationOperation,
                                   build_messages, assistant_tool_schemas,
                                   dispatch_assistant_tool, parse_markdown_blocks

export @document, @projection, @iomap
export Cell, setval!, setfn!, isuptodate, take_first_n
export projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
export ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, TypeReference,
       FunctionReference, ProjectionReference, ReferencePath, EmptyReferencePath, is_valid_reference,
       evaluate_reference, append_reference, collect_references,
       is_element_reference, is_position_reference, is_range_reference,
       reference_equal, is_prefix_of
export set_selection!, clear_selection!, replace_selection!
export @reference_case, when, prefix
export @reference
export ReplaceSelectionOperation
export JsonDocument, JsonInsertion, JsonForeign, JsonNull, JsonBool, JsonNumber, JsonString, JsonArray, JsonObject, JsonObjectEntry, jsonvalue, entries
export TableDocument, TableCell, TableRow, TableColumn, TableTable
export XmlDocument, XmlInsertion, XmlForeign, XmlText, XmlAttribute, XmlElement, xmlattr, setattr!, deleteattr!
export FileSystemDocument, FileSystemInsertion, FileSystemForeign, FileSystemFile, FileSystemDirectory, make_filesystem_pathname
export TextDocument, TextInsertion, TextForeign, TextText, TextString, TextNewline
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
export PrimitiveDocument, PrimitiveInsertion, PrimitiveForeign,
       PrimitiveBool, PrimitiveNumber, PrimitiveString,
       NumberReplaceRangeOperation, StringReplaceRangeOperation
export MathDocument, MathInsertion, MathVariable, MathBinaryOperation,
       MathParenthesized, MathAssignment
export JuliaDocument, JuliaIdentifier, JuliaInteger, JuliaBinaryOp, JuliaCall,
       JuliaIf, JuliaFunction, JuliaBlock
export SyntaxDocument, SyntaxInsertion, SyntaxForeign, SyntaxLeaf, SyntaxNode, render
export GraphicsDocument, GraphicsInsertion, GraphicsForeign,
       GraphicsText, GraphicsRect, GraphicsCanvas, GraphicsViewport, GraphicsImage,
       GraphicsFence, LayoutDirection, layout_none, layout_horizontal, layout_vertical, hit_element_at
export Modifiers
export KeyDown, KeyUp, KeyPress, is_ctrl, is_shift, is_alt, is_meta
export MouseDown, MouseUp, MousePress, MouseMove, MouseScroll
export Backend, init!, quit!, open_window!, close_window!, measure_text
export SdlBackend, sdl_measure_text, sdl_render_canvas, write_image, GraphicsCanvasToImageFile
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
export FileSystemFileToSyntaxLeaf, FileSystemDirectoryToSyntaxNode, FileSystemToSyntax
export ObjectToSyntax, NothingToSyntaxLeaf, BoolToSyntaxLeaf,
       NumberToSyntaxLeaf, StringToSyntaxLeaf, SymbolToSyntaxLeaf,
       CharToSyntaxLeaf, ObjectNodeToSyntaxNode, print_object
export BookBookToSyntaxNode, BookChapterToSyntaxNode,
       BookParagraphToSyntaxLeaf, BookListToSyntaxNode,
       BookPictureToSyntaxLeaf, BookToSyntax
export ClipboardDocument, ClipboardInsertion, ClipboardForeign, ClipboardSlice, ClipboardCollection
export CellVector, ListNode, CollectionDocument, left_tail, right_tail, cell_at
export Inset, StyleColor, Point2D, color_default
export WidgetDocument, WidgetInsertion, WidgetForeign,
       WidgetLabel, WidgetText, WidgetCheckbox, WidgetButton,
       WidgetTooltip, WidgetMenu, WidgetMenuItem, WidgetComposite,
       WidgetShell, WidgetTitlePane, WidgetSplitPane, WidgetTabbedPane,
       WidgetScrollPane, WidgetToolbar, WidgetScrollBar
export HideWidgetOperation, ShowWidgetOperation, ScrollWidgetOperation, SelectTabOperation, SetScrollBarValueOperation
export Operation, evaluate_operation
export inset_default, inset_size, inset_width, inset_height,
       inset_top_left, inset_top_right, inset_bottom_left, inset_bottom_right
export BookDocument, BookInsertion, BookForeign, BookBook, BookChapter, BookParagraph, BookList, BookPicture
export WorkbenchDocument, WorkbenchInsertion, WorkbenchForeign,
       WorkbenchWorkbench, WorkbenchPage,
       WorkbenchNavigator, WorkbenchConsole, WorkbenchDescriptor,
       WorkbenchOperator, WorkbenchSearcher, WorkbenchEvaluator,
       WorkbenchAssistant,
       WorkbenchEditor
export ImageDocument, ImageInsertion, ImageForeign, ImageFile, ImageMemory
export TextToString, TextTextToString, TextStringToString, TextNewlineToString
export LineNumbering, TextLineNumbering
export WordWrapping, TextWordWrapping
export SyntaxToText, SyntaxLeafToText, SyntaxListToText
export PrimitiveToSyntax, PrimitiveBoolToSyntaxLeaf,
       PrimitiveNumberToSyntaxLeaf, PrimitiveStringToSyntaxLeaf
export PrimitiveToText, PrimitiveBoolToText,
       PrimitiveNumberToText, PrimitiveStringToText
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
export GraphicsCanvasToGraphicsImage, GraphicsCaching
export WorkbenchWorkbenchToWidgetShell,    WorkbenchWorkbenchToWidgetShellIoMap,
       WorkbenchPageToWidgetTabbedPane,    WorkbenchPageToWidgetTabbedPaneIoMap,
       WorkbenchNavigatorToWidgetScrollPane, WorkbenchNavigatorToWidgetScrollPaneIoMap,
       WorkbenchConsoleToWidgetScrollPane,
       WorkbenchDescriptorToWidgetScrollPane,
       WorkbenchOperatorToWidgetScrollPane,
       WorkbenchSearcherToWidgetScrollPane,
       WorkbenchEvaluatorToWidgetScrollPane,
       WorkbenchAssistantToWidgetScrollPane,
       WorkbenchEditorToWidgetScrollPane,
       WorkbenchToWidget
export application
export McpServer, mcp_start!, mcp_stop!
export Tool, Resource, register_tool!, register_tools!, list_tools, call_tool,
       register_resource!, register_resources!, list_resources, read_resource,
       anthropic_tool_schema, mcp_tools, mcp_resources
export stream_message
export ConversationDocument, ConversationConversation,
       ConversationMessage,
       ConversationUserMessage, ConversationAssistantMessage,
       ConversationToolUseMessage, ConversationToolResultMessage,
       ConversationJuliaInputMessage, ConversationJuliaResultMessage,
       ConversationBlock,
       ConversationTextBlock, ConversationCodeBlock,
       ConversationHeadingBlock, ConversationListBlock,
       ConversationToolUseBlock
export ConversationToWidget,
       ConversationConversationToWidgetComposite,
       ConversationUserMessageToWidgetComposite,
       ConversationAssistantMessageToWidgetComposite,
       ConversationToolUseMessageToWidgetComposite,
       ConversationToolResultMessageToWidgetComposite,
       ConversationJuliaInputMessageToWidgetComposite,
       ConversationJuliaResultMessageToWidgetComposite,
       ConversationTextBlockToText,
       ConversationCodeBlockToWidget,
       ConversationHeadingBlockToText,
       ConversationListBlockToWidgetComposite,
       ConversationToolUseBlockToText
export SubmitProseOperation, SubmitJuliaOperation,
       ClearInputOperation, ResetConversationOperation,
       build_messages, assistant_tool_schemas, dispatch_assistant_tool,
       parse_markdown_blocks

end # module Projectured
