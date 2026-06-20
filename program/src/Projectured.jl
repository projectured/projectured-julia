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
include("context/PrinterContext.jl")
include("common/Operation.jl")
include("document/Document.jl")
include("document/Collection.jl")
include("common/DocumentCopy.jl")
include("document/Font.jl")
include("document/Color.jl")
include("document/StyleText.jl")
include("document/StyleStroke.jl")
include("document/Geometry.jl")
include("document/Text.jl")
include("document/Primitive.jl")
include("common/OperationRerooting.jl")
include("document/Syntax.jl")
include("document/Graphics.jl")
include("document/Json.jl")
include("document/Math.jl")
include("document/Julia.jl")
include("document/Tabular.jl")
include("document/Database.jl")
include("document/DbCatalog.jl")
include("document/DatabaseInstance.jl")
include("document/Sql.jl")
include("document/Xml.jl")
include("document/FileSystem.jl")
include("document/Workspace.jl")
include("document/Clipboard.jl")
include("document/Widget.jl")
include("document/Layout.jl")
include("document/Graph.jl")
include("document/GraphLayout.jl")
include("layout/GraphLayoutEngine.jl")
include("document/Component.jl")
include("document/Book.jl")
include("document/Evaluator.jl")
include("document/Formula.jl")
include("document/Conversation.jl")
include("document/Ini.jl")
include("document/Ned.jl")
include("parser/IniParser.jl")
include("parser/NedParser.jl")
include("parser/JuliaParser.jl")
include("parser/JsonParser.jl")
include("parser/XmlParser.jl")
include("parser/SqlParser.jl")
# LLM backend (used as a field type by `WorkbenchAssistant`). Loads early
# because no document or projection layer depends on it; it only needs
# HTTP/JSON3 (external packages) and access to the Anthropic SSE client.
include("editor/Anthropic.jl")
include("editor/Llm.jl")
include("document/Workbench.jl")
include("document/Image.jl")
include("document/Screen.jl")
include("document/Tooltip.jl")
include("document/Dragging.jl")

# ── Higher-order projections ──────────────────────────────────────────────

include("projection/higherorder/Sequential.jl")
include("projection/higherorder/TypeDispatching.jl")
include("projection/higherorder/Recursive.jl")
include("projection/higherorder/Alternative.jl")
include("projection/higherorder/PredicateDispatching.jl")
include("projection/higherorder/ReferenceDispatching.jl")
include("projection/higherorder/Nesting.jl")
include("projection/higherorder/WindowManager.jl")
include("projection/higherorder/EnvelopeUnwrapping.jl")
include("projection/higherorder/TooltipDecorator.jl")

# ── Generic projections ───────────────────────────────────────────────────

include("common/Projection.jl")
include("projection/generic/Preserving.jl")
include("projection/generic/Reversing.jl")
include("projection/generic/Filtering.jl")
include("projection/generic/Searching.jl")
include("projection/generic/Sorting.jl")
include("projection/generic/Copying.jl")
include("projection/primitive/ScreenToScreen.jl")
include("projection/generic/Invariably.jl")
include("projection/generic/ObjectToWidget.jl")

# ── Devices (needed by projections) ──────────────────────────────────────

include("device/Modifiers.jl")
include("device/Keyboard.jl")
include("device/Mouse.jl")
include("device/EventCase.jl")
include("projection/generic/Focusing.jl")
# Clipboard projection: needs the keyboard/event-case device modules above plus
# the clipboard documents, copy_document, and operations included earlier.
include("projection/primitive/ClipboardToAny.jl")

# Higher-order projection that depends on ObjectToWidget (generic) and the
# keyboard device, so it is included here rather than with the other
# higher-order projections above.
include("projection/higherorder/ProjectionConfiguring.jl")
# Drag-and-drop decorator: depends on the Mouse device, the collection/reference
# modules, and the DraggingState document, all included above.
include("projection/higherorder/Dragging.jl")

# ── Primitive projections ─────────────────────────────────────────────────

include("projection/primitive/SyntaxToText.jl")
include("projection/primitive/TextToGraphics.jl")
include("projection/primitive/GraphicsCaching.jl")
include("projection/primitive/JsonToSyntax.jl")
include("projection/primitive/XmlToSyntax.jl")
include("projection/primitive/FileSystemToSyntax.jl")
include("projection/primitive/WorkspaceToFileSystem.jl")
include("projection/primitive/TextToString.jl")
include("projection/primitive/ObjectToSyntax.jl")
include("projection/primitive/ObjectToJson.jl")
# LayoutToGraphics before WidgetToGraphics: the WidgetTable renderer builds a
# GridLayout and reads its geometry off the GridLayoutIoMap, so those symbols
# must already be defined when WidgetToGraphics is loaded.
include("projection/primitive/LayoutToGraphics.jl")
include("projection/primitive/WidgetToGraphics.jl")
include("projection/primitive/TextToWidget.jl")
include("projection/primitive/GraphToGraphLayout.jl")
include("projection/primitive/GraphLayoutToGraphics.jl")
include("projection/primitive/SyntaxToWidget.jl")
include("projection/primitive/BookToSyntax.jl")
include("projection/primitive/IniToSyntax.jl")
include("projection/primitive/NedToSyntax.jl")
include("projection/primitive/LineNumbering.jl")
include("projection/primitive/WordWrapping.jl")
include("projection/primitive/TextFirstLine.jl")
include("projection/primitive/TextFiltering.jl")
include("projection/primitive/TextHighlighting.jl")
include("projection/primitive/SelectionInverting.jl")
include("projection/primitive/PrimitiveToSyntax.jl")
include("projection/primitive/PrimitiveToText.jl")
include("projection/primitive/ReferenceToText.jl")
include("projection/primitive/MathToSyntax.jl")
include("projection/primitive/JuliaToSyntax.jl")
include("projection/primitive/FormulaToSyntax.jl")
include("projection/primitive/DocumentInsertionToSyntax.jl")
include("projection/primitive/SqlToSyntax.jl")
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
include("backend/Console.jl")
include("backend/Web.jl")
include("backend/Pdf.jl")
include("external/Database.jl")
include("external/ConnectionPool.jl")
include("external/DatabaseTabular.jl")
include("projection/primitive/DatabaseTableToTabularGrid.jl")
include("projection/primitive/DatabaseInstanceToDbCatalog.jl")
include("projection/primitive/SqlToCellTable.jl")
include("projection/primitive/CellTableToTable.jl")
include("projection/primitive/DbCatalogToJson.jl")
include("projection/primitive/DbCatalogToSql.jl")
include("projection/primitive/DbCatalogToSyntax.jl")
include("editor/GestureRecognizer.jl")
include("editor/ToolRegistry.jl")
include("editor/Mcp.jl")
# ConversationEditor (the composer) loads before WorkbenchAssistant so the panel's
# reader can import `composer_read` to route its draft-turn input.
include("editor/ConversationEditor.jl")
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
using .ReferenceModule
using .SyntaxModule
using .FileSystemModule
using .XmlModule
using .TextModule
using .PrimitiveModule
using .MathModule
using .FontModule
using .ColorModule
using .StyleTextModule
using .StyleStrokeModule
using .ImageModule
using .ScreenDocumentModule
using .ReactiveModule: Cell, setval!, setfn!, isuptodate
using .ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection, Change, as_change
using .ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference,
                       TypeReference, FunctionReference, ProjectionReference, PointReference,
                       TextRectangularReference,
                       ReferencePath, EmptyReferencePath,
                       is_valid_reference, evaluate_reference, append_reference, collect_references,
                       is_element_reference, is_position_reference, is_range_reference,
                       reference_equal, is_prefix_of,
                       ReferenceTypeMismatch, valid_reference_prefix, annotate_reference_types, strip_reference_types
using .PrinterContextModule: PrinterContext, child_context, with_available_size,
                                 with_property, get_property
using .DocumentApiModule: set_selection!, clear_selection!
using .OperationModule: ReplaceSelectionOperation, QuitEditorOperation, replace_selection!,
                        OpenWindowOperation, CloseWindowOperation, ResizeWindowOperation, ToggleCollapseOperation,
                        ReplaceDocumentOperation, ReplaceReferencedValue, CollectionInsertOperation, CollectionDeleteOperation,
                        CompoundOperation
using .ReferenceCaseModule: var"@reference_case", when, prefix
using .EventCaseModule: var"@event_case"
using .ReferenceBuilderModule: var"@reference", var"@step"
using .OperationApiModule: Operation, evaluate_operation
using .JsonModule: JsonDocument, JsonInsertion, JsonNull, JsonBool, JsonNumber, JsonString, JsonArray,
                   JsonObject, JsonObjectEntry, jsonvalue, entries
using .TabularModule: TabularDocument, TabularCell, TabularRow, TabularGrid,
                      tabular_cell, tabular_column,
                      insert_row!, delete_row!, insert_column!, delete_column!
using .DatabaseDocumentModule: DatabaseDocument, DatabaseTable,
                               DatabaseUpdateOperation, DatabaseInsertOperation
using .DatabaseModule: DatabaseAdapter, RawDatabaseResult, OdbcDatabaseAdapter,
                       db_connect!, db_close!, db_alive,
                       db_rowid_column,
                       db_query, db_execute_raw,
                       db_insert!, db_update!, db_delete!,
                       db_catalog_databases, db_catalog_schemas, db_catalog_tables, db_catalog_columns
using .DatabaseTableToTabularGridModule: DatabaseTableIoMap, DatabaseTableToTabularGrid
using .DatabaseInstanceDocumentModule: DatabaseInstanceDocument, DatabaseInstance, DatabaseCredentials
using .ConnectionPoolModule: OdbcConnectionPool, with_connection, dsn_for, close_pool!
using .SqlDocumentModule: SqlDocument, SqlStatement,
                          SqlSelectExpression, SqlFromBaseItem, SqlJoinType, SqlJoinCondition,
                          SqlJoinConditionExpression, SqlWhereCondition,
                          SqlTableName, SqlTableAlias, SqlColumnName, SqlColumnAlias,
                          SqlDistinct, SqlAllColumns, SqlColumnReference,
                          SqlSelectItem, SqlSelectClause, SqlWhereClause,
                          SqlInnerJoin, SqlLeftOuterJoin, SqlRightOuterJoin,
                          SqlFullOuterJoin, SqlCrossJoin,
                          SqlJoinOnCondition, SqlJoinUsingCondition,
                          SqlTableExpression, SqlJoinedFromItem, SqlFromItem, SqlFromClause,
                          SqlSelectStatement, SqlSubqueryFromItem,
                          SqlInsertStatement, SqlUpdateAssignment, SqlUpdateStatement,
                          SqlColumnDefinition, SqlCreateTableStatement, SqlCreateSchemaStatement,
                          SqlStatementList,
                          SqlWhereFilterCondition, SqlBooleanExpression,
                          SqlScalarValue, SqlComparison,
                          SqlAnd, SqlOr, SqlNot
using .DbCatalogDocumentModule: DbCatalogDocument,
                                DbCatalogRdbms, DbCatalogDatabase, DbCatalogSchema,
                                DbCatalogTable, DbCatalogColumn
using .DatabaseInstanceToDbCatalogModule: DatabaseInstanceToDbCatalog
using .SqlToCellTableModule: SqlToCellTable
using .CellTableToTableModule: CellTableToTable, CellTableToWidgetTable
using .DbCatalogToJsonModule: DbCatalogRdbmsToJson, DbCatalogDatabaseToJson,
                               DbCatalogSchemaToJson, DbCatalogTableToJson, DbCatalogColumnToJson,
                               DbCatalogToJson
using .DbCatalogToSqlModule: DbCatalogRdbmsToSql, DbCatalogDatabaseToSql,
                              DbCatalogSchemaToSql, DbCatalogTableToSql, DbCatalogColumnToSql,
                              DbCatalogToSql
using .DbCatalogToSyntaxModule: DbCatalogColumnToSyntaxLeaf, DbCatalogTableToSyntaxNode,
                                DbCatalogSchemaToSyntaxNode, DbCatalogDatabaseToSyntaxNode,
                                DbCatalogRdbmsToSyntaxNode, DbCatalogToSyntax,
                                dbcatalog_marker_eligible
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
                    JuliaIf, JuliaFunction, JuliaBlock, JuliaInsertion
using .SyntaxModule: SyntaxDocument, SyntaxInsertion, SyntaxLeaf, SyntaxNode, render
using .GraphicsModule: GraphicsDocument, GraphicsInsertion,
                       GraphicsText, GraphicsRect, GraphicsLine, GraphicsCircle,
                       GraphicsPolyline, GraphicsSpline, GraphicsCanvas, GraphicsViewport, GraphicsImage,
                       GraphicsFence, LayoutDirection, layout_none, layout_horizontal, layout_vertical,
                       hit_element_at, tessellate_spline, polyline_arrowhead, point_near_polyline
using .ModifiersModule: Modifiers
using .KeyboardModule: Keyboard, KeyDown, KeyUp, KeyPress, is_ctrl, is_shift, is_alt, is_meta
using .MouseModule: MouseDown, MouseUp, MousePress, MouseMove, MouseScroll
using .BackendModule: Backend, init!, quit!, measure_text
using .SdlBackendModule: SdlBackend, sdl_measure_text, sdl_render_canvas,
                          sdl_display_size,
                          write_image, record_video, GraphicsCanvasToImageFile,
                          sdl_decode_image, decode_image_file!
using .ConsoleBackendModule: ConsoleBackend, console_render
using .WebBackendModule: WebBackend, web_key_to_symbol
using .PdfBackendModule: write_pdf, GraphicsCanvasToPdfFile, pdf_measure_text

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
using .EnvelopeUnwrappingModule: EnvelopeUnwrappingProjection, EnvelopeUnwrappingIoMap
using .WindowManagerProjectionModule: WindowManagerProjection, WindowManagerProjectionIoMap
using .ScreenToScreenModule: ScreenToScreen, ScreenToScreenIoMap, ScreenWindowIoMap
using .TooltipDecoratorProjectionModule: TooltipDecoratorProjection, TooltipDecoratorProjectionIoMap
using .DraggingDocumentModule: DraggingState, DraggingDocument
using .DraggingProjectionModule: DraggingProjection, DraggingProjectionIoMap, MoveRangeOperation
using .ReversingProjectionModule: ReversingProjection
using .FilteringProjectionModule: FilteringProjection, FilteringProjectionIoMap
using .SearchingProjectionModule: SearchingProjection, SearchingProjectionIoMap
using .ObjectToWidgetModule: ObjectToWidget, ObjectToWidgetIoMap
using .ProjectionConfiguringProjectionModule: ProjectionConfiguringProjection, ProjectionConfiguringProjectionIoMap
using .SortingProjectionModule: SortingProjection, SortingProjectionIoMap
using .CopyingProjectionModule: CopyingProjection, CopyingProjectionIoMap
using .DocumentCopyModule: copy_document
using .ClipboardToAnyProjectionModule: ClipboardSliceToAnyProjection, ClipboardCollectionToAnyProjection,
                                     ClipboardSliceToAnyProjectionIoMap, ClipboardCollectionToAnyProjectionIoMap,
                                     ToggleClipboardSliceDisplayOperation, ToggleClipboardCollectionDisplayOperation
using .FocusingProjectionModule: FocusingProjection, ReplaceFocusPartOperation
using .JsonToSyntaxModule: JsonToSyntax, JsonStringToSyntaxLeaf,
                               JsonNullToSyntaxLeaf, JsonBoolToSyntaxLeaf,
                               JsonNumberToSyntaxLeaf, JsonArrayToSyntaxNode,
                               JsonObjectToSyntaxNode,
                               JsonInsertionToSyntaxLeaf
using .XmlToSyntaxModule: XmlToSyntax, XmlTextToSyntaxLeaf, XmlElementToSyntaxNode
using .FileSystemToSyntaxModule: FileSystemFileToSyntaxLeaf, FileSystemDirectoryToSyntaxNode, FileSystemToSyntax,
                                 filesystem_marker_eligible
using .WorkspaceToFileSystemModule: WorkspaceFolderToFileSystemDirectory, WorkspaceToFileSystem
using .ObjectToSyntaxModule: ObjectToSyntax, NothingToSyntaxLeaf, BoolToSyntaxLeaf,
                              NumberToSyntaxLeaf, StringToSyntaxLeaf, SymbolToSyntaxLeaf,
                              CharToSyntaxLeaf, ObjectNodeToSyntaxNode, print_object, search_references, search_objects
using .ObjectToJsonModule: ObjectToJson, NothingToJsonNull, BoolToJsonBool,
                            NumberToJsonNumber, StringToJsonString, SymbolToJsonString,
                            CharToJsonString, CellToJson, ObjectNodeToJsonObject, json_object
using .BookToSyntaxModule: BookBookToSyntaxNode, BookChapterToSyntaxNode,
                            BookParagraphToSyntaxLeaf, BookListToSyntaxNode,
                            BookPictureToSyntaxLeaf, BookToSyntax
using .ClipboardModule: ClipboardDocument, ClipboardInsertion,
                        ClipboardSlice, ClipboardCollection
using .CollectionModule: CellVector, CellMatrix, CellTable, ListNode, CollectionDocument, left_tail, right_tail, cell_at, take_first_n
using .BookModule: BookDocument, BookInsertion,
                   BookBook, BookChapter, BookParagraph, BookList, BookPicture
using .IniModule: IniDocument, IniInsertion, IniComment, IniInclude,
                  IniConfigOption, IniParamAssignment, IniSection, IniFile
using .IniParserModule: iniparse, iniparse_file
using .NedModule: NedDocument, NedInsertion, NedExtends, NedInterfaceName, NedLoop, NedCondition, NedLiteral,
                  NedPropertyKey, NedProperty, NedPropertyDecl, NedParam, NedGate,
                  NedSubmodule, NedConnection, NedConnectionGroup,
                  NedSimpleModule, NedCompoundModule, NedModuleInterface, NedChannel, NedChannelInterface,
                  NedPackage, NedImport, NedFile
using .NedParserModule: nedparse, nedparse_file
using .JuliaParserModule: juliaparse, juliaparse_file
using .JsonParserModule: jsonparse, jsonparse_file
using .XmlParserModule: xmlparse, xmlparse_file
using .SqlParserModule: sqlparse, sqlparse_file
using .IniToSyntaxModule: IniInsertionToSyntaxLeaf, IniCommentToSyntaxLeaf, IniIncludeToSyntaxLeaf,
                          IniConfigOptionToSyntaxNode, IniParamAssignmentToSyntaxNode,
                          IniSectionToSyntaxNode, IniFileToSyntaxNode, IniToSyntax
using .NedToSyntaxModule: NedInsertionToSyntaxLeaf, NedPackageToSyntaxLeaf, NedImportToSyntaxLeaf,
                          NedPropertyToSyntaxLeaf, NedParamToSyntaxLeaf, NedGateToSyntaxLeaf,
                          NedSubmoduleToSyntaxNode, NedConnectionToSyntaxLeaf, NedConnectionGroupToSyntaxNode,
                          NedSimpleModuleToSyntaxNode, NedCompoundModuleToSyntaxNode,
                          NedModuleInterfaceToSyntaxNode, NedChannelToSyntaxNode, NedChannelInterfaceToSyntaxNode,
                          NedFileToSyntaxNode, NedToSyntax
using .ComponentModule: ComponentDocument, ComponentMasterDetail
using .WorkbenchModule: WorkbenchDocument, WorkbenchInsertion,
                        WorkbenchWorkbench, WorkbenchPage,
                        WorkbenchNavigator, WorkbenchConsole, WorkbenchDescriptor,
                        WorkbenchOperator, WorkbenchSearcher, WorkbenchEvaluator,
                        WorkbenchAssistant,
                        WorkbenchEditor,
                        WorkbenchOpenDocumentOperation, WorkbenchCloseDocumentOperation
using .ColorModule: StyleColor
using .GeometryModule: Inset, Point2D,
                      inset_default, inset_size, inset_width, inset_height,
                      inset_top_left, inset_top_right, inset_bottom_left, inset_bottom_right
using .WidgetModule: WidgetDocument, WidgetInsertion,
                     WidgetLabel, WidgetText, WidgetCheckbox, WidgetButton,
                     WidgetTooltip, WidgetMenu, WidgetMenuItem, WidgetComposite,
                     WidgetShell, WidgetTitlePane, WidgetSplitPane, WidgetTabbedPane,
                     WidgetScrollPane, WidgetToolbar, WidgetScrollBar,
                     WidgetBadge, WidgetSeparator, WidgetCard, WidgetSwitch, WidgetProgress,
                     WidgetSlider, WidgetRadioGroup, WidgetAvatar, WidgetAlert, WidgetSkeleton,
                     WidgetToggle, WidgetToggleGroup, WidgetSelect, WidgetTextarea, WidgetAccordion,
                     WidgetTable, WidgetTree,
                     HideWidgetOperation, ShowWidgetOperation,
                     ScrollWidgetOperation, SelectTabOperation, SetScrollBarValueOperation,
                     StartSplitterDragOperation, ResizeSplitPaneOperation, EndSplitterDragOperation
using .LayoutModule: LayoutDocument,
                     HorizontalLayout, VerticalLayout, GridLayout, FlowLayout,
                     LayoutConstraint, allocate_axis,
                     layout_min, layout_max, layout_preferred, layout_weight
using .GraphModule: GraphDocument, GraphInsertion, GraphVertex, GraphEdge, GraphGraph
using .GraphLayoutModule: GraphLayoutDocument, VertexLayout, EdgeLayout, GraphLayout, GraphConstraint
using .GraphLayoutEngineModule: GraphLayoutEngine, FallbackLayoutEngine, AdaptagramsEngine, layout_graph
using .ImageModule: ImageDocument, ImageInsertion, ImageFile, ImageMemory
using .ScreenDocumentModule: ScreenDocument, WindowDocument, EventEnvelope, WindowCloseRequest, WindowResizeEvent
using .TooltipDocumentModule: TooltipSource
using .TextToStringModule: TextToString, TextTextToString, TextStringToString, TextNewlineToString
using .TextLineNumberingModule: LineNumbering, TextLineNumbering
using .WordWrappingModule: WordWrapping, WordWrappingIoMap, WrapSeg
using .TextFirstLineModule: TextFirstLine, TextFirstLineIoMap
using .TextFilteringModule: TextFiltering, TextFilteringIoMap
using .TextHighlightingModule: TextHighlighting, TextHighlightingIoMap, HighlightSeg
using .SelectionInvertingModule: SelectionInverting, SelectionInvertingIoMap, SelSeg
using .SyntaxToTextModule: SyntaxToText, SyntaxNodeToTextIoMap,
                                       SyntaxLeafToText, SyntaxListToText
using .PrimitiveToSyntaxModule: PrimitiveToSyntax, PrimitiveBoolToSyntaxLeaf,
                                 PrimitiveNumberToSyntaxLeaf, PrimitiveStringToSyntaxLeaf
using .PrimitiveToTextModule: PrimitiveToText, PrimitiveBoolToText,
                               PrimitiveNumberToText, PrimitiveStringToTextText
using .ReferenceToTextModule: ReferenceToText, ReferenceToHumanReadableText
using .MathToSyntaxModule: MathToSyntax, MathInsertionToSyntaxLeaf, MathVariableToSyntaxLeaf,
                            MathBinaryOperationToSyntaxNode, MathParenthesizedToSyntaxNode,
                            MathAssignmentToSyntaxNode
using .SqlToSyntaxModule: SqlToSyntax, SqlAllColumnsToSyntaxLeaf, SqlColumnReferenceToSyntaxLeaf,
                          SqlColumnNameToSyntaxLeaf,
                          SqlTableExpressionToSyntaxLeaf, SqlJoinTypeToSyntaxLeaf,
                          SqlSelectItemToSyntaxNode, SqlSelectClauseToSyntaxNode,
                          SqlFromItemToSyntaxNode, SqlFromClauseToSyntaxNode,
                          SqlJoinedFromItemToSyntaxNode, SqlJoinOnConditionToSyntaxNode,
                          SqlWhereFilterConditionToSyntaxNode,
                          SqlWhereClauseToSyntaxNode, SqlSelectStatementToSyntaxNode,
                          SqlInsertStatementToSyntaxNode, SqlUpdateAssignmentToSyntaxNode,
                          SqlUpdateStatementToSyntaxNode,
                          SqlColumnDefinitionToSyntaxNode, SqlCreateTableStatementToSyntaxNode,
                          SqlCreateSchemaStatementToSyntaxNode, SqlStatementListToSyntaxNode
using .JuliaToSyntaxModule: JuliaToSyntax, JuliaIdentifierToSyntaxLeaf, JuliaIntegerToSyntaxLeaf,
                             JuliaBinaryOpToSyntaxNode, JuliaCallToSyntaxNode,
                             JuliaIfToSyntaxNode, JuliaFunctionToSyntaxNode,
                             JuliaBlockToSyntaxNode
using .FormulaToSyntaxModule: FormulaToSyntax, FormulaInsertionToSyntaxLeaf,
                              FormulaReferenceToSyntaxLeaf, FormulaFormulaToSyntaxNode,
                              FormulaEnvironmentToSyntaxNode
using .DocumentInsertionToSyntaxModule: InsertionToSyntaxLeaf,
                                         DocumentInsertionToSyntaxLeaf, JuliaInsertionToSyntaxLeaf,
                                         default_factory, default_completion
using .CollectionToSyntaxModule: CollectionToSyntax, CollectionCellVectorToSyntax,
                                  CollectionListNodeToSyntax
using .TextToGraphicsModule: TextToGraphics, TextToGraphicsIoMap
using .LayoutToGraphicsModule: HorizontalLayoutToGraphicsCanvas,
                               VerticalLayoutToGraphicsCanvas,
                               GridLayoutToGraphicsCanvas,
                               FlowLayoutToGraphicsCanvas,
                               LayoutConstraintToGraphicsCanvas,
                               LayoutToGraphics, GridLayoutIoMap
using .GraphToGraphLayoutModule: GraphGraphToGraphLayout, GraphToGraphLayout,
                                 GraphGraphToGraphLayoutIoMap
using .GraphLayoutToGraphicsModule: GraphLayoutToGraphicsCanvas,
                                    GraphLayoutToGraphicsCanvasIoMap
using .WidgetToGraphicsModule: WidgetInsertionToGraphicsCanvas, WidgetLabelToGraphicsCanvas, WidgetTextToGraphicsCanvas,
                               WidgetCheckboxToGraphicsCanvas, WidgetButtonToGraphicsCanvas,
                               WidgetTooltipToGraphicsCanvas, WidgetMenuToGraphicsCanvas,
                               WidgetMenuItemToGraphicsCanvas, WidgetCompositeToGraphicsCanvas,
                               WidgetShellToGraphicsCanvas, WidgetTitlePaneToGraphicsCanvas,
                               WidgetSplitPaneToGraphicsCanvas, WidgetTabbedPaneToGraphicsCanvas,
                               WidgetScrollPaneToGraphicsCanvas, WidgetScrollPaneToGraphicsCanvasIoMap,
                               WidgetToolbarToGraphicsCanvas, WidgetScrollBarToGraphicsCanvas,
                               WidgetToGraphics, WidgetTheme, widget_theme_light, widget_theme_dark,
                               widget_theme_slate_light, widget_theme_slate_dark,
                               WidgetScrollPaneToGraphicsViewport, WidgetScrollPaneToGraphicsViewportIoMap
using .TextToWidgetModule: TextToWidget, TextToWidgetIoMap, WidgetAndTextToGraphics
using .SyntaxToWidgetModule: SyntaxToWidget, SyntaxLeafToWidget, SyntaxNodeToWidget
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
using .GestureRecognizerModule: GestureRecognizer, recognize!, next_gesture!
using .EditorModule: Editor, run!, play_live!
using .McpModule: McpServer, mcp_start!, mcp_stop!,
                  search_documentation, search_api,
                  list_guides, read_guide, list_modules, list_classes, list_functions,
                  read_module_documentation, read_class_documentation, read_function_documentation
using .ToolRegistryModule: Tool, Resource,
                            register_tool!, register_tools!, list_tools, call_tool,
                            register_resource!, register_resources!, list_resources, read_resource,
                            anthropic_tool_schema, mcp_tools, mcp_resources
using .AnthropicModule: stream_message
using .LlmModule: LlmBackend, AnthropicLlm, FakeLlm, stream_turn
using .EvaluatorModule: EvaluatorDocument, EvaluatorForm, EvaluatorToplevel, result_text, eval_kind_label
using .FormulaModule: FormulaDocument, FormulaInsertion, FormulaReference, FormulaFormula,
                      FormulaEnvironment, formula_result_text, wire_result!,
                      resolve, column_letter, cell_name,
                      formula_references, formula_dependencies,
                      would_create_cycle, topological_order,
                      formula_to_expr, evaluate_formula
using .ConversationModule: ConversationDocument, ConversationConversation,
                            ConversationTurn, ConversationPart, ConversationDraft,
                            ConversationThinking, thinking_part
using .ConversationToSyntaxModule: ConversationToSyntax,
                                    ConversationConversationToSyntaxNode,
                                    ConversationTurnToSyntaxNode,
                                    ConversationPartToSyntaxNode
using .ConversationToWidgetModule: ConversationToWidget,
                                    ConversationConversationToWidgetComposite,
                                    ConversationTurnToWidgetComposite,
                                    ConversationPartToWidget
using .WorkbenchAssistantModule: SubmitProseOperation, SubmitJuliaOperation, SubmitDraftTurnOperation,
                                   ClearInputOperation, ResetConversationOperation,
                                   build_messages, conversation_to_string, write_conversation, assistant_tool_schemas,
                                   dispatch_assistant_tool, parse_markdown_blocks
using .ConversationEditorModule: ConversationComposerToWidget, composer_read,
                                  finalize_draft!, new_draft, reset_draft!,
                                  ComposerInputOperation, ComposerBackspaceOperation,
                                  ComposerNewlineOperation, ComposerInsertPartOperation,
                                  ComposerCommitChooserOperation, ComposerCommitSourceOperation,
                                  ComposerEvaluateOperation, ComposerRevertOperation,
                                  ComposerSubmitOperation

export @document, @projection, @iomap
export Cell, setval!, setfn!, isuptodate, take_first_n
export projection_print, projection_read, map_reference_forward, map_reference_backward, Projection, Change, as_change
export ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, TypeReference,
       FunctionReference, ProjectionReference, PointReference, TextRectangularReference, ReferencePath, EmptyReferencePath,
       is_valid_reference, evaluate_reference, append_reference, collect_references,
       is_element_reference, is_position_reference, is_range_reference,
       reference_equal, is_prefix_of,
       ReferenceTypeMismatch, valid_reference_prefix, annotate_reference_types, strip_reference_types
export PrinterContext, child_context, with_available_size, with_property, get_property
export set_selection!, clear_selection!, replace_selection!
export @reference_case, when, prefix
export @event_case
export @reference, @step
export ReplaceSelectionOperation, QuitEditorOperation, ToggleCollapseOperation
export ReplaceDocumentOperation, ReplaceReferencedValue, CollectionInsertOperation, CollectionDeleteOperation
export CompoundOperation
export OpenWindowOperation, CloseWindowOperation, ResizeWindowOperation
export JsonDocument, JsonInsertion, JsonNull, JsonBool, JsonNumber, JsonString, JsonArray, JsonObject, JsonObjectEntry, jsonvalue, entries
export TabularDocument, TabularCell, TabularRow, TabularGrid,
       tabular_cell, tabular_column,
       insert_row!, delete_row!, insert_column!, delete_column!
export DatabaseDocument, DatabaseTable, DatabaseUpdateOperation, DatabaseInsertOperation
export DatabaseAdapter, RawDatabaseResult, OdbcDatabaseAdapter,
       db_connect!, db_close!, db_alive, db_rowid_column,
       db_query, db_execute_raw, db_insert!, db_update!, db_delete!,
       db_catalog_databases, db_catalog_schemas, db_catalog_tables, db_catalog_columns
export DatabaseTableIoMap, DatabaseTableToTabularGrid
export DatabaseInstanceDocument, DatabaseInstance, DatabaseCredentials
export OdbcConnectionPool, with_connection, dsn_for, close_pool!
export SqlDocument, SqlStatement,
       SqlSelectExpression, SqlFromBaseItem, SqlJoinType, SqlJoinCondition,
       SqlJoinConditionExpression, SqlWhereCondition,
       SqlTableName, SqlTableAlias, SqlColumnName, SqlColumnAlias,
       SqlDistinct, SqlAllColumns, SqlColumnReference,
       SqlSelectItem, SqlSelectClause, SqlWhereClause,
       SqlInnerJoin, SqlLeftOuterJoin, SqlRightOuterJoin,
       SqlFullOuterJoin, SqlCrossJoin,
       SqlJoinOnCondition, SqlJoinUsingCondition,
       SqlTableExpression, SqlJoinedFromItem, SqlFromItem, SqlFromClause,
       SqlSelectStatement, SqlSubqueryFromItem,
       SqlInsertStatement, SqlUpdateAssignment, SqlUpdateStatement,
       SqlColumnDefinition, SqlCreateTableStatement, SqlCreateSchemaStatement,
       SqlStatementList,
       SqlWhereFilterCondition, SqlBooleanExpression,
       SqlScalarValue, SqlComparison,
       SqlAnd, SqlOr, SqlNot
export SqlToSyntax, SqlAllColumnsToSyntaxLeaf, SqlColumnReferenceToSyntaxLeaf,
       SqlColumnNameToSyntaxLeaf,
       SqlTableExpressionToSyntaxLeaf, SqlJoinTypeToSyntaxLeaf,
       SqlSelectItemToSyntaxNode, SqlSelectClauseToSyntaxNode,
       SqlFromItemToSyntaxNode, SqlFromClauseToSyntaxNode,
       SqlJoinedFromItemToSyntaxNode, SqlJoinOnConditionToSyntaxNode,
       SqlWhereFilterConditionToSyntaxNode,
       SqlWhereClauseToSyntaxNode, SqlSelectStatementToSyntaxNode,
       SqlInsertStatementToSyntaxNode, SqlUpdateAssignmentToSyntaxNode,
       SqlUpdateStatementToSyntaxNode,
       SqlColumnDefinitionToSyntaxNode, SqlCreateTableStatementToSyntaxNode,
       SqlCreateSchemaStatementToSyntaxNode, SqlStatementListToSyntaxNode
export DbCatalogDocument,
       DbCatalogRdbms, DbCatalogDatabase, DbCatalogSchema,
       DbCatalogTable, DbCatalogColumn
export DatabaseInstanceToDbCatalog
export SqlToCellTable, CellTableToTable, CellTableToWidgetTable
export DbCatalogRdbmsToJson, DbCatalogDatabaseToJson,
       DbCatalogSchemaToJson, DbCatalogTableToJson, DbCatalogColumnToJson,
       DbCatalogToJson
export DbCatalogRdbmsToSql, DbCatalogDatabaseToSql,
       DbCatalogSchemaToSql, DbCatalogTableToSql, DbCatalogColumnToSql,
       DbCatalogToSql
export DbCatalogColumnToSyntaxLeaf, DbCatalogTableToSyntaxNode,
       DbCatalogSchemaToSyntaxNode, DbCatalogDatabaseToSyntaxNode,
       DbCatalogRdbmsToSyntaxNode, DbCatalogToSyntax,
       dbcatalog_marker_eligible
export XmlDocument, XmlInsertion, XmlText, XmlAttribute, XmlElement, xmlattr, setattr!, deleteattr!
export IniDocument, IniInsertion, IniComment, IniInclude, IniConfigOption, IniParamAssignment, IniSection, IniFile
export iniparse, iniparse_file
export IniInsertionToSyntaxLeaf, IniCommentToSyntaxLeaf, IniIncludeToSyntaxLeaf,
       IniConfigOptionToSyntaxNode, IniParamAssignmentToSyntaxNode,
       IniSectionToSyntaxNode, IniFileToSyntaxNode, IniToSyntax
export NedDocument, NedInsertion, NedExtends, NedInterfaceName, NedLoop, NedCondition, NedLiteral,
       NedPropertyKey, NedProperty, NedPropertyDecl, NedParam, NedGate,
       NedSubmodule, NedConnection, NedConnectionGroup,
       NedSimpleModule, NedCompoundModule, NedModuleInterface, NedChannel, NedChannelInterface,
       NedPackage, NedImport, NedFile
export nedparse, nedparse_file
export juliaparse, juliaparse_file
export jsonparse, jsonparse_file
export xmlparse, xmlparse_file
export sqlparse, sqlparse_file
export NedInsertionToSyntaxLeaf, NedPackageToSyntaxLeaf, NedImportToSyntaxLeaf,
       NedPropertyToSyntaxLeaf, NedParamToSyntaxLeaf, NedGateToSyntaxLeaf,
       NedSubmoduleToSyntaxNode, NedConnectionToSyntaxLeaf, NedConnectionGroupToSyntaxNode,
       NedSimpleModuleToSyntaxNode, NedCompoundModuleToSyntaxNode,
       NedModuleInterfaceToSyntaxNode, NedChannelToSyntaxNode, NedChannelInterfaceToSyntaxNode,
       NedFileToSyntaxNode, NedToSyntax
export FileSystemDocument, FileSystemInsertion, FileSystemFile, FileSystemDirectory, make_filesystem_pathname
export WorkspaceDocument, WorkspaceFolder, Workspace
export TextDocument, TextInsertion, TextText, TextString, TextNewline, TextGraphics
export StyleFont, make_style_font, font_scaled_size
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
       GraphicsText, GraphicsRect, GraphicsLine, GraphicsCircle,
       GraphicsPolyline, GraphicsSpline, GraphicsCanvas, GraphicsViewport, GraphicsImage,
       GraphicsFence, LayoutDirection, layout_none, layout_horizontal, layout_vertical, hit_element_at,
       tessellate_spline, polyline_arrowhead, point_near_polyline
export Modifiers
export Keyboard, KeyDown, KeyUp, KeyPress, is_ctrl, is_shift, is_alt, is_meta
export MouseDown, MouseUp, MousePress, MouseMove, MouseScroll
export Backend, init!, quit!, measure_text
export Screen
export SdlBackend, sdl_measure_text, sdl_render_canvas, sdl_display_size,
       write_image, record_video, GraphicsCanvasToImageFile, sdl_decode_image, decode_image_file!
export ConsoleBackend, console_render
export WebBackend, web_key_to_symbol
export write_pdf, GraphicsCanvasToPdfFile, pdf_measure_text
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
export EnvelopeUnwrappingProjection, EnvelopeUnwrappingIoMap
export WindowManagerProjection, WindowManagerProjectionIoMap
export ScreenToScreen, ScreenToScreenIoMap, ScreenWindowIoMap
export TooltipDecoratorProjection, TooltipDecoratorProjectionIoMap
export DraggingState, DraggingDocument, DraggingProjection, DraggingProjectionIoMap, MoveRangeOperation
export ReversingProjection
export FilteringProjection, FilteringProjectionIoMap
export ObjectToWidget, ObjectToWidgetIoMap
export ProjectionConfiguringProjection, ProjectionConfiguringProjectionIoMap
export SearchingProjection, SearchingProjectionIoMap
export SortingProjection, SortingProjectionIoMap
export CopyingProjection, CopyingProjectionIoMap
export FocusingProjection, ReplaceFocusPartOperation
export JsonToSyntax, JsonStringToSyntaxLeaf,
       JsonNullToSyntaxLeaf, JsonBoolToSyntaxLeaf,
       JsonNumberToSyntaxLeaf, JsonArrayToSyntaxNode, JsonObjectToSyntaxNode,
       JsonInsertionToSyntaxLeaf
export XmlToSyntax, XmlTextToSyntaxLeaf, XmlElementToSyntaxNode
export FileSystemFileToSyntaxLeaf, FileSystemDirectoryToSyntaxNode, FileSystemToSyntax, filesystem_marker_eligible
export WorkspaceFolderToFileSystemDirectory, WorkspaceToFileSystem
export ObjectToSyntax, NothingToSyntaxLeaf, BoolToSyntaxLeaf,
       NumberToSyntaxLeaf, StringToSyntaxLeaf, SymbolToSyntaxLeaf,
       CharToSyntaxLeaf, ObjectNodeToSyntaxNode, print_object, search_references, search_objects
export ObjectToJson, NothingToJsonNull, BoolToJsonBool,
       NumberToJsonNumber, StringToJsonString, SymbolToJsonString,
       CharToJsonString, CellToJson, ObjectNodeToJsonObject, json_object
export BookBookToSyntaxNode, BookChapterToSyntaxNode,
       BookParagraphToSyntaxLeaf, BookListToSyntaxNode,
       BookPictureToSyntaxLeaf, BookToSyntax
export ClipboardDocument, ClipboardInsertion, ClipboardSlice, ClipboardCollection
export copy_document
export ClipboardSliceToAnyProjection, ClipboardCollectionToAnyProjection,
       ClipboardSliceToAnyProjectionIoMap, ClipboardCollectionToAnyProjectionIoMap,
       ToggleClipboardSliceDisplayOperation, ToggleClipboardCollectionDisplayOperation
export CellVector, CellMatrix, CellTable, ListNode, CollectionDocument, left_tail, right_tail, cell_at
export Inset, StyleColor, Point2D, color_default
export WidgetDocument, WidgetInsertion,
       WidgetLabel, WidgetText, WidgetCheckbox, WidgetButton,
       WidgetTooltip, WidgetMenu, WidgetMenuItem, WidgetComposite,
       WidgetShell, WidgetTitlePane, WidgetSplitPane, WidgetTabbedPane,
       WidgetScrollPane, WidgetToolbar, WidgetScrollBar,
       WidgetBadge, WidgetSeparator, WidgetCard, WidgetSwitch, WidgetProgress,
       WidgetSlider, WidgetRadioGroup, WidgetAvatar, WidgetAlert, WidgetSkeleton,
       WidgetToggle, WidgetToggleGroup, WidgetSelect, WidgetTextarea, WidgetAccordion,
       WidgetTable, WidgetTree
export HideWidgetOperation, ShowWidgetOperation, ScrollWidgetOperation, SelectTabOperation, SetScrollBarValueOperation
export StartSplitterDragOperation, ResizeSplitPaneOperation, EndSplitterDragOperation
export Operation, evaluate_operation
export inset_default, inset_size, inset_width, inset_height,
       inset_top_left, inset_top_right, inset_bottom_left, inset_bottom_right
export BookDocument, BookInsertion, BookBook, BookChapter, BookParagraph, BookList, BookPicture
export ComponentDocument, ComponentMasterDetail
export WorkbenchDocument, WorkbenchInsertion,
       WorkbenchWorkbench, WorkbenchPage,
       WorkbenchNavigator, WorkbenchConsole, WorkbenchDescriptor,
       WorkbenchOperator, WorkbenchSearcher, WorkbenchEvaluator,
       WorkbenchAssistant,
       WorkbenchEditor,
       WorkbenchOpenDocumentOperation, WorkbenchCloseDocumentOperation
export ImageDocument, ImageInsertion, ImageFile, ImageMemory
export ScreenDocument, WindowDocument, EventEnvelope, WindowCloseRequest, WindowResizeEvent
export TooltipSource
export TextToString, TextTextToString, TextStringToString, TextNewlineToString
export LineNumbering, TextLineNumbering
export WordWrapping, WordWrappingIoMap, WrapSeg
export TextFirstLine, TextFirstLineIoMap
export TextFiltering, TextFilteringIoMap
export TextHighlighting, TextHighlightingIoMap, HighlightSeg
export SelectionInverting, SelectionInvertingIoMap, SelSeg
export SyntaxToText, SyntaxLeafToText, SyntaxListToText
export PrimitiveToSyntax, PrimitiveBoolToSyntaxLeaf,
       PrimitiveNumberToSyntaxLeaf, PrimitiveStringToSyntaxLeaf
export PrimitiveToText, PrimitiveBoolToText,
       PrimitiveNumberToText, PrimitiveStringToTextText
export ReferenceToText, ReferenceToHumanReadableText
export MathToSyntax, MathInsertionToSyntaxLeaf, MathVariableToSyntaxLeaf,
       MathBinaryOperationToSyntaxNode, MathParenthesizedToSyntaxNode,
       MathAssignmentToSyntaxNode
export JuliaToSyntax, JuliaIdentifierToSyntaxLeaf, JuliaIntegerToSyntaxLeaf,
       JuliaBinaryOpToSyntaxNode, JuliaCallToSyntaxNode,
       JuliaIfToSyntaxNode, JuliaFunctionToSyntaxNode,
       JuliaBlockToSyntaxNode
export FormulaToSyntax, FormulaInsertionToSyntaxLeaf,
       FormulaReferenceToSyntaxLeaf, FormulaFormulaToSyntaxNode,
       FormulaEnvironmentToSyntaxNode
export JuliaInsertion, InsertionToSyntaxLeaf,
       DocumentInsertionToSyntaxLeaf, JuliaInsertionToSyntaxLeaf,
       default_factory, default_completion
using .DocumentCoreModule: DocumentBase, DocumentNothing, DocumentInsertion, DocumentReference
export DocumentBase, DocumentNothing, DocumentInsertion, DocumentReference
export CollectionToSyntax, CollectionCellVectorToSyntax, CollectionListNodeToSyntax
export TextToGraphics, WidgetToGraphics, WidgetTheme, widget_theme_light, widget_theme_dark,
       widget_theme_slate_light, widget_theme_slate_dark, TextToWidget, WidgetAndTextToGraphics
export SyntaxToWidget, SyntaxLeafToWidget, SyntaxNodeToWidget
export SyntaxNodeToTextIoMap, TextToGraphicsIoMap
export WidgetInsertionToGraphicsCanvas, WidgetLabelToGraphicsCanvas, WidgetTextToGraphicsCanvas,
       WidgetCheckboxToGraphicsCanvas, WidgetButtonToGraphicsCanvas,
       WidgetTooltipToGraphicsCanvas, WidgetMenuToGraphicsCanvas,
       WidgetMenuItemToGraphicsCanvas, WidgetCompositeToGraphicsCanvas,
       WidgetShellToGraphicsCanvas, WidgetTitlePaneToGraphicsCanvas,
       WidgetSplitPaneToGraphicsCanvas, WidgetTabbedPaneToGraphicsCanvas,
       WidgetScrollPaneToGraphicsCanvas, WidgetScrollPaneToGraphicsCanvasIoMap,
       WidgetToolbarToGraphicsCanvas, WidgetScrollBarToGraphicsCanvas
export WidgetScrollPaneToGraphicsViewport, WidgetScrollPaneToGraphicsViewportIoMap
export LayoutDocument, HorizontalLayout, VerticalLayout, GridLayout, FlowLayout, LayoutConstraint
export allocate_axis, layout_min, layout_max, layout_preferred, layout_weight
export HorizontalLayoutToGraphicsCanvas, VerticalLayoutToGraphicsCanvas,
       GridLayoutToGraphicsCanvas, FlowLayoutToGraphicsCanvas,
       LayoutConstraintToGraphicsCanvas, LayoutToGraphics
export GraphDocument, GraphInsertion, GraphVertex, GraphEdge, GraphGraph
export GraphLayoutDocument, VertexLayout, EdgeLayout, GraphLayout, GraphConstraint
export GraphLayoutEngine, FallbackLayoutEngine, AdaptagramsEngine, layout_graph
export GraphGraphToGraphLayout, GraphToGraphLayout, GraphGraphToGraphLayoutIoMap
export GraphLayoutToGraphicsCanvas, GraphLayoutToGraphicsCanvasIoMap
export GraphicsCanvasToGraphicsImage, GraphicsCaching
export GestureRecognizer, recognize!, next_gesture!
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
export Editor, run!, play_live!
export McpServer, mcp_start!, mcp_stop!,
       search_documentation, search_api,
       list_guides, read_guide, list_modules, list_classes, list_functions,
       read_module_documentation, read_class_documentation, read_function_documentation
export Tool, Resource, register_tool!, register_tools!, list_tools, call_tool,
       register_resource!, register_resources!, list_resources, read_resource,
       anthropic_tool_schema, mcp_tools, mcp_resources
export stream_message
export LlmBackend, AnthropicLlm, FakeLlm, stream_turn
export EvaluatorDocument, EvaluatorForm, EvaluatorToplevel, result_text, eval_kind_label
export FormulaDocument, FormulaInsertion, FormulaReference, FormulaFormula,
       FormulaEnvironment, formula_result_text, wire_result!,
       resolve, column_letter, cell_name,
       formula_references, formula_dependencies,
       would_create_cycle, topological_order,
       formula_to_expr, evaluate_formula
export ConversationDocument, ConversationConversation,
       ConversationTurn, ConversationPart, ConversationDraft,
       ConversationThinking, thinking_part
export ConversationToSyntax,
       ConversationConversationToSyntaxNode,
       ConversationTurnToSyntaxNode,
       ConversationPartToSyntaxNode
export ConversationToWidget,
       ConversationConversationToWidgetComposite,
       ConversationTurnToWidgetComposite,
       ConversationPartToWidget
export SubmitProseOperation, SubmitJuliaOperation, SubmitDraftTurnOperation,
       ClearInputOperation, ResetConversationOperation,
       build_messages, conversation_to_string, write_conversation, assistant_tool_schemas, dispatch_assistant_tool,
       parse_markdown_blocks
export ConversationComposerToWidget, composer_read, finalize_draft!, new_draft, reset_draft!,
       ComposerInputOperation, ComposerBackspaceOperation,
       ComposerNewlineOperation, ComposerInsertPartOperation,
       ComposerCommitChooserOperation, ComposerCommitSourceOperation,
       ComposerEvaluateOperation, ComposerRevertOperation,
       ComposerSubmitOperation

end # module Projectured
