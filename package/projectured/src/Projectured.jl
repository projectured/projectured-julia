"""
    Projectured

Umbrella package. Depends on `ProjecturedKernel` (the headless engine) and
`ProjecturedDomain` (all concrete documents/projections/backends) and re-exports
their combined public API as a single flat namespace, so existing `using
Projectured` user code is unchanged. The optional features (SDL/ODBC/Web live in
ProjecturedDomain; LLM/MCP live in ProjecturedKernel) light up through their
package extensions when the corresponding weakdeps are loaded.
"""
module Projectured

using ProjecturedKernel
using ProjecturedDomain

# ── Re-export the underlying submodules by name so qualified access
#    (Projectured.XxxModule.foo) keeps working across the package split ──
const AgentModule = ProjecturedKernel.AgentModule
const AlternativeProjectionModule = ProjecturedKernel.AlternativeProjectionModule
const BackendModule = ProjecturedKernel.BackendModule
const BookModule = ProjecturedDomain.BookModule
const BookToSyntaxModule = ProjecturedDomain.BookToSyntaxModule
const CellTableToTableModule = ProjecturedDomain.CellTableToTableModule
const ClipboardModule = ProjecturedDomain.ClipboardModule
const ClipboardToAnyProjectionModule = ProjecturedDomain.ClipboardToAnyProjectionModule
const CollectionModule = ProjecturedKernel.CollectionModule
const CollectionToSyntaxModule = ProjecturedDomain.CollectionToSyntaxModule
const ColorModule = ProjecturedDomain.ColorModule
const ComponentModule = ProjecturedDomain.ComponentModule
const ConsoleBackendModule = ProjecturedDomain.ConsoleBackendModule
const ConversationEditorModule = ProjecturedDomain.ConversationEditorModule
const ConversationModule = ProjecturedDomain.ConversationModule
const ConversationToSyntaxModule = ProjecturedDomain.ConversationToSyntaxModule
const ConversationToWidgetModule = ProjecturedDomain.ConversationToWidgetModule
const CopyingProjectionModule = ProjecturedKernel.CopyingProjectionModule
const DatabaseDocumentModule = ProjecturedDomain.DatabaseDocumentModule
const DatabaseInstanceDocumentModule = ProjecturedDomain.DatabaseInstanceDocumentModule
const DatabaseModule = ProjecturedDomain.DatabaseModule
const DbCatalogDocumentModule = ProjecturedDomain.DbCatalogDocumentModule
const DbCatalogToJsonModule = ProjecturedDomain.DbCatalogToJsonModule
const DbCatalogToSqlModule = ProjecturedDomain.DbCatalogToSqlModule
const DbCatalogToSyntaxModule = ProjecturedDomain.DbCatalogToSyntaxModule
const DeviceModule = ProjecturedKernel.DeviceModule
const DocumentApiModule = ProjecturedKernel.DocumentApiModule
const DocumentCopyModule = ProjecturedKernel.DocumentCopyModule
const DocumentCoreModule = ProjecturedDomain.DocumentCoreModule
const DocumentInsertionToSyntaxModule = ProjecturedDomain.DocumentInsertionToSyntaxModule
const DocumentModule = ProjecturedKernel.DocumentModule
const DraggingDocumentModule = ProjecturedDomain.DraggingDocumentModule
const DraggingProjectionModule = ProjecturedDomain.DraggingProjectionModule
const EditorModule = ProjecturedKernel.EditorModule
const EnvelopeUnwrappingModule = ProjecturedKernel.EnvelopeUnwrappingModule
const EvaluatorModule = ProjecturedDomain.EvaluatorModule
const EventCaseModule = ProjecturedKernel.EventCaseModule
const FileSystemModule = ProjecturedDomain.FileSystemModule
const FileSystemToSyntaxModule = ProjecturedDomain.FileSystemToSyntaxModule
const FilteringProjectionModule = ProjecturedKernel.FilteringProjectionModule
const FocusingProjectionModule = ProjecturedKernel.FocusingProjectionModule
const FontModule = ProjecturedDomain.FontModule
const FormulaModule = ProjecturedDomain.FormulaModule
const FormulaToSyntaxModule = ProjecturedDomain.FormulaToSyntaxModule
const GenericCompoundModule = ProjecturedDomain.GenericCompoundModule
const GeometryModule = ProjecturedDomain.GeometryModule
const GestureRecognizerModule = ProjecturedKernel.GestureRecognizerModule
const GraphLayoutEngineModule = ProjecturedDomain.GraphLayoutEngineModule
const GraphLayoutModule = ProjecturedDomain.GraphLayoutModule
const GraphLayoutToGraphicsModule = ProjecturedDomain.GraphLayoutToGraphicsModule
const GraphModule = ProjecturedDomain.GraphModule
const GraphToGraphLayoutModule = ProjecturedDomain.GraphToGraphLayoutModule
const GraphicsCachingModule = ProjecturedDomain.GraphicsCachingModule
const GraphicsModule = ProjecturedDomain.GraphicsModule
const HigherOrderCompoundModule = ProjecturedDomain.HigherOrderCompoundModule
const ImageModule = ProjecturedDomain.ImageModule
const InvariablyProjectionModule = ProjecturedKernel.InvariablyProjectionModule
const IoMapApiModule = ProjecturedKernel.IoMapApiModule
const IoMapModule = ProjecturedKernel.IoMapModule
const JsonModule = ProjecturedDomain.JsonModule
const JsonParserModule = ProjecturedDomain.JsonParserModule
const JsonToSyntaxModule = ProjecturedDomain.JsonToSyntaxModule
const JuliaModule = ProjecturedDomain.JuliaModule
const JuliaParserModule = ProjecturedDomain.JuliaParserModule
const JuliaToSyntaxModule = ProjecturedDomain.JuliaToSyntaxModule
const KeyboardModule = ProjecturedKernel.KeyboardModule
const LayoutModule = ProjecturedDomain.LayoutModule
const LayoutToGraphicsModule = ProjecturedDomain.LayoutToGraphicsModule
const LlmModule = ProjecturedKernel.LlmModule
const MathModule = ProjecturedDomain.MathModule
const MathToSyntaxModule = ProjecturedDomain.MathToSyntaxModule
const McpModule = ProjecturedKernel.McpModule
const ModifiersModule = ProjecturedKernel.ModifiersModule
const MouseModule = ProjecturedKernel.MouseModule
const NestingProjectionModule = ProjecturedKernel.NestingProjectionModule
const ObjectToJsonModule = ProjecturedDomain.ObjectToJsonModule
const ObjectToSyntaxModule = ProjecturedDomain.ObjectToSyntaxModule
const ObjectToWidgetModule = ProjecturedDomain.ObjectToWidgetModule
const OperationApiModule = ProjecturedKernel.OperationApiModule
const OperationModule = ProjecturedKernel.OperationModule
const PdfBackendModule = ProjecturedDomain.PdfBackendModule
const PredicateDispatchingModule = ProjecturedKernel.PredicateDispatchingModule
const PreservingProjectionModule = ProjecturedKernel.PreservingProjectionModule
const PrimitiveModule = ProjecturedKernel.PrimitiveModule
const PrimitiveToSyntaxModule = ProjecturedDomain.PrimitiveToSyntaxModule
const PrimitiveToTextModule = ProjecturedDomain.PrimitiveToTextModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const ProjectionConfiguringProjectionModule = ProjecturedDomain.ProjectionConfiguringProjectionModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const ProjectionTemplateModule = ProjecturedDomain.ProjectionTemplateModule
const ReactiveModule = ProjecturedKernel.ReactiveModule
const RecursiveProjectionModule = ProjecturedKernel.RecursiveProjectionModule
const ReferenceBuilderModule = ProjecturedKernel.ReferenceBuilderModule
const ReferenceCaseModule = ProjecturedKernel.ReferenceCaseModule
const ReferenceDispatchingModule = ProjecturedKernel.ReferenceDispatchingModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ReferenceToTextModule = ProjecturedDomain.ReferenceToTextModule
const ReversingProjectionModule = ProjecturedKernel.ReversingProjectionModule
const ScreenDocumentModule = ProjecturedKernel.ScreenDocumentModule
const ScreenModule = ProjecturedKernel.ScreenModule
const ScreenToScreenModule = ProjecturedDomain.ScreenToScreenModule
const SearchingProjectionModule = ProjecturedKernel.SearchingProjectionModule
const SelectionInvertingModule = ProjecturedDomain.SelectionInvertingModule
const SequentialProjectionModule = ProjecturedKernel.SequentialProjectionModule
const SortingProjectionModule = ProjecturedKernel.SortingProjectionModule
const SqlDocumentModule = ProjecturedDomain.SqlDocumentModule
const SqlParserModule = ProjecturedDomain.SqlParserModule
const SqlToSyntaxModule = ProjecturedDomain.SqlToSyntaxModule
const StyleStrokeModule = ProjecturedDomain.StyleStrokeModule
const StyleTextModule = ProjecturedDomain.StyleTextModule
const SyntaxModule = ProjecturedDomain.SyntaxModule
const SyntaxToTextModule = ProjecturedDomain.SyntaxToTextModule
const SyntaxToWidgetModule = ProjecturedDomain.SyntaxToWidgetModule
const TabularModule = ProjecturedDomain.TabularModule
const TextFilteringModule = ProjecturedDomain.TextFilteringModule
const TextFirstLineModule = ProjecturedDomain.TextFirstLineModule
const TextHighlightingModule = ProjecturedDomain.TextHighlightingModule
const TextLineNumberingModule = ProjecturedDomain.TextLineNumberingModule
const TextModule = ProjecturedDomain.TextModule
const TextToGraphicsModule = ProjecturedDomain.TextToGraphicsModule
const TextToStringModule = ProjecturedDomain.TextToStringModule
const TextToWidgetModule = ProjecturedDomain.TextToWidgetModule
const ToolRegistryModule = ProjecturedKernel.ToolRegistryModule
const TooltipDecoratorProjectionModule = ProjecturedDomain.TooltipDecoratorProjectionModule
const TooltipDocumentModule = ProjecturedDomain.TooltipDocumentModule
const TypeDispatchingModule = ProjecturedKernel.TypeDispatchingModule
const VersioningModule = ProjecturedDomain.VersioningModule
const VersioningToAnyProjectionModule = ProjecturedDomain.VersioningToAnyProjectionModule
const WidgetModule = ProjecturedDomain.WidgetModule
const WidgetToGraphicsModule = ProjecturedDomain.WidgetToGraphicsModule
const WindowManagerProjectionModule = ProjecturedKernel.WindowManagerProjectionModule
const WordWrappingModule = ProjecturedDomain.WordWrappingModule
const WorkbenchAssistantModule = ProjecturedDomain.WorkbenchAssistantModule
const WorkbenchModule = ProjecturedDomain.WorkbenchModule
const WorkbenchToWidgetModule = ProjecturedDomain.WorkbenchToWidgetModule
const WorkspaceModule = ProjecturedDomain.WorkspaceModule
const WorkspaceToFileSystemModule = ProjecturedDomain.WorkspaceToFileSystemModule
const XmlModule = ProjecturedDomain.XmlModule
const XmlParserModule = ProjecturedDomain.XmlParserModule
const XmlToSyntaxModule = ProjecturedDomain.XmlToSyntaxModule

using ProjecturedKernel.DocumentModule: @document
using ProjecturedKernel.ProjectionModule: @projection
using ProjecturedKernel.IoMapModule: @iomap
using ProjecturedKernel.CollectionModule
using ProjecturedDomain.JsonModule
using ProjecturedDomain.TabularModule
using ProjecturedKernel.ReferenceModule
using ProjecturedDomain.SyntaxModule
using ProjecturedDomain.FileSystemModule
using ProjecturedDomain.XmlModule
using ProjecturedDomain.TextModule
using ProjecturedKernel.PrimitiveModule
using ProjecturedDomain.MathModule
using ProjecturedDomain.FontModule
using ProjecturedDomain.ColorModule
using ProjecturedDomain.StyleTextModule
using ProjecturedDomain.StyleStrokeModule
using ProjecturedDomain.ImageModule
using ProjecturedKernel.ScreenDocumentModule
using ProjecturedKernel.ReactiveModule: Cell, setval!, setfn!, isuptodate
using ProjecturedKernel.ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection, Change, as_change
using ProjecturedKernel.ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference,
                       TypeReference, FunctionReference, ProjectionReference, PointReference,
                       TextRectangularReference,
                       ReferencePath, EmptyReferencePath,
                       is_valid_reference, evaluate_reference, append_reference, collect_references,
                       is_element_reference, is_position_reference, is_range_reference,
                       reference_equal, is_prefix_of,
                       ReferenceTypeMismatch, valid_reference_prefix, annotate_reference_types, strip_reference_types
using ProjecturedKernel.PrinterContextModule: PrinterContext, child_context, with_available_size,
                                 with_property, get_property
using ProjecturedKernel.DocumentApiModule: set_selection!, clear_selection!, document_read
using ProjecturedKernel.OperationModule: ReplaceSelectionOperation, QuitEditorOperation, replace_selection!,
                        OpenWindowOperation, CloseWindowOperation, ResizeWindowOperation, ToggleCollapseOperation,
                        ReplaceDocumentOperation, ReplaceReferencedValue, CollectionInsertOperation, CollectionDeleteOperation,
                        CompoundOperation
using ProjecturedKernel.ReferenceCaseModule: var"@reference_case", when, prefix
using ProjecturedKernel.EventCaseModule: var"@event_case"
using ProjecturedKernel.ReferenceBuilderModule: var"@reference", var"@step"
using ProjecturedKernel.OperationApiModule: Operation, evaluate_operation
using ProjecturedDomain.JsonModule: JsonDocument, JsonInsertion, JsonNull, JsonBool, JsonNumber, JsonString, JsonArray,
                   JsonObject, JsonObjectEntry, jsonvalue, entries
using ProjecturedDomain.TabularModule: TabularDocument, TabularCell, TabularRow, TabularGrid,
                      tabular_cell, tabular_column,
                      insert_row!, delete_row!, insert_column!, delete_column!
using ProjecturedDomain.DatabaseDocumentModule: DatabaseDocument, DatabaseTable,
                               DatabaseUpdateOperation, DatabaseInsertOperation
using ProjecturedDomain.DatabaseModule: DatabaseAdapter, RawDatabaseResult, make_database_adapter,
                       db_connect!, db_close!, db_alive,
                       db_rowid_column,
                       db_query, db_execute_raw,
                       db_insert!, db_update!, db_delete!,
                       db_catalog_databases, db_catalog_schemas, db_catalog_tables, db_catalog_columns
# OdbcDatabaseAdapter, the connection pool, and the DatabaseTableToTabularGrid /
# SqlToCellTable / DatabaseInstanceToDbCatalog live-query projections live in the
# ProjecturedODBCExt extension (build an adapter via make_database_adapter(:odbc)).
using ProjecturedDomain.DatabaseInstanceDocumentModule: DatabaseInstanceDocument, DatabaseInstance, DatabaseCredentials
using ProjecturedDomain.SqlDocumentModule: SqlDocument, SqlStatement,
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
using ProjecturedDomain.DbCatalogDocumentModule: DbCatalogDocument,
                                DbCatalogRdbms, DbCatalogDatabase, DbCatalogSchema,
                                DbCatalogTable, DbCatalogColumn
using ProjecturedDomain.CellTableToTableModule: CellTableToTable, CellTableToWidgetTable
using ProjecturedDomain.DbCatalogToJsonModule: DbCatalogRdbmsToJson, DbCatalogDatabaseToJson,
                               DbCatalogSchemaToJson, DbCatalogTableToJson, DbCatalogColumnToJson,
                               DbCatalogToJson
using ProjecturedDomain.DbCatalogToSqlModule: DbCatalogRdbmsToSql, DbCatalogDatabaseToSql,
                              DbCatalogSchemaToSql, DbCatalogTableToSql, DbCatalogColumnToSql,
                              DbCatalogToSql
using ProjecturedDomain.DbCatalogToSyntaxModule: DbCatalogColumnToSyntaxLeaf, DbCatalogTableToSyntaxNode,
                                DbCatalogSchemaToSyntaxNode, DbCatalogDatabaseToSyntaxNode,
                                DbCatalogRdbmsToSyntaxNode, DbCatalogToSyntax,
                                dbcatalog_marker_eligible
using ProjecturedDomain.XmlModule: XmlDocument, XmlInsertion, XmlText, XmlAttribute, XmlElement, xmlattr,
                  setattr!, deleteattr!
using ProjecturedDomain.FileSystemModule: FileSystemDocument, FileSystemInsertion,
                         FileSystemFile, FileSystemDirectory, make_filesystem_pathname
using ProjecturedDomain.WorkspaceModule: WorkspaceDocument, WorkspaceFolder, Workspace
using ProjecturedDomain.TextModule: TextDocument, TextInsertion, TextText, TextString, TextNewline, TextGraphics
using ProjecturedKernel.PrimitiveModule: PrimitiveDocument, PrimitiveInsertion,
                        PrimitiveBool, PrimitiveNumber, PrimitiveString,
                        NumberReplaceRangeOperation, StringReplaceRangeOperation
using ProjecturedDomain.MathModule: MathDocument, MathInsertion, MathVariable, MathBinaryOperation,
                   MathParenthesized, MathAssignment
using ProjecturedDomain.JuliaModule: JuliaDocument, JuliaIdentifier, JuliaInteger, JuliaBinaryOp, JuliaCall,
                    JuliaIf, JuliaFunction, JuliaBlock, JuliaInsertion
using ProjecturedDomain.SyntaxModule: SyntaxDocument, SyntaxInsertion, SyntaxLeaf, SyntaxNode, render
using ProjecturedDomain.GraphicsModule: GraphicsDocument, GraphicsInsertion,
                       GraphicsText, GraphicsRect, GraphicsLine, GraphicsCircle,
                       GraphicsPolyline, GraphicsSpline, GraphicsCanvas, GraphicsViewport, GraphicsImage,
                       GraphicsFence, LayoutDirection, layout_none, layout_horizontal, layout_vertical,
                       hit_element_at, tessellate_spline, polyline_arrowhead, point_near_polyline
using ProjecturedKernel.ModifiersModule: Modifiers
using ProjecturedKernel.KeyboardModule: Keyboard, KeyDown, KeyUp, KeyPress, is_ctrl, is_shift, is_alt, is_meta
using ProjecturedKernel.MouseModule: MouseDown, MouseUp, MousePress, MouseMove, MouseScroll
using ProjecturedKernel.BackendModule: Backend, init!, quit!, measure_text, make_backend,
                      write_image, record_video,
                      render_canvas, decode_image, display_size, set_display_size_provider!
# SdlBackend and the sdl_* / GraphicsCanvasToImageFile symbols live in the
# ProjecturedSDLExt extension; build the backend via make_backend(:sdl) and reach
# rendering/decoding through the core seams (render_canvas/decode_image/write_image).
using ProjecturedDomain.ConsoleBackendModule: ConsoleBackend, console_render
# WebBackend lives in the ProjecturedWebExt extension; build it via make_backend(:web).
using ProjecturedDomain.PdfBackendModule: write_pdf, GraphicsCanvasToPdfFile, pdf_measure_text, truetype_measure_text

using ProjecturedKernel.DeviceModule: Device, write_to_device, read_from_device, write_to_devices, read_from_devices
using ProjecturedKernel.ScreenModule: Screen, QuitEvent
using ProjecturedKernel.IoMapApiModule: IoMap
using ProjecturedKernel.IoMapModule: SimpleIoMap, ChildrenIoMap, ContentIoMap
using ProjecturedKernel.TypeDispatchingModule: TypeDispatchingProjection
using ProjecturedKernel.RecursiveProjectionModule: RecursiveProjection
using ProjecturedKernel.SequentialProjectionModule: SequentialProjection, SequentialProjectionIoMap
using ProjecturedKernel.AlternativeProjectionModule: AlternativeProjection, AlternativeProjectionIoMap
using ProjecturedKernel.PredicateDispatchingModule: PredicateDispatchingProjection
using ProjecturedKernel.PreservingProjectionModule: PreservingProjection
using ProjecturedKernel.InvariablyProjectionModule: InvariablyProjection
using ProjecturedKernel.ReferenceDispatchingModule: ReferenceDispatchingProjection, ReferenceDispatchingIoMap
using ProjecturedDomain.HigherOrderCompoundModule: ApplyAtProjection
using ProjecturedDomain.GenericCompoundModule: SortingAtProjection
using ProjecturedKernel.NestingProjectionModule: NestingProjection, NestingProjectionIoMap
using ProjecturedKernel.EnvelopeUnwrappingModule: EnvelopeUnwrappingProjection, EnvelopeUnwrappingIoMap
using ProjecturedKernel.WindowManagerProjectionModule: WindowManagerProjection, WindowManagerProjectionIoMap
using ProjecturedDomain.ScreenToScreenModule: ScreenToScreen, ScreenToScreenIoMap, ScreenWindowIoMap
using ProjecturedDomain.TooltipDecoratorProjectionModule: TooltipDecoratorProjection, TooltipDecoratorProjectionIoMap
using ProjecturedDomain.DraggingDocumentModule: DraggingState, DraggingDocument
using ProjecturedDomain.DraggingProjectionModule: DraggingProjection, DraggingProjectionIoMap, MoveRangeOperation
using ProjecturedKernel.ReversingProjectionModule: ReversingProjection
using ProjecturedKernel.FilteringProjectionModule: FilteringProjection, FilteringProjectionIoMap
using ProjecturedKernel.SearchingProjectionModule: SearchingProjection, SearchingProjectionIoMap
using ProjecturedDomain.ObjectToWidgetModule: ObjectToWidget, ObjectToWidgetIoMap
using ProjecturedDomain.ProjectionConfiguringProjectionModule: ProjectionConfiguringProjection, ProjectionConfiguringProjectionIoMap
using ProjecturedKernel.SortingProjectionModule: SortingProjection, SortingProjectionIoMap
using ProjecturedKernel.CopyingProjectionModule: CopyingProjection, CopyingProjectionIoMap
using ProjecturedKernel.DocumentCopyModule: copy_document
using ProjecturedDomain.ClipboardToAnyProjectionModule: ClipboardSliceToAnyProjection, ClipboardCollectionToAnyProjection,
                                     ClipboardSliceToAnyProjectionIoMap, ClipboardCollectionToAnyProjectionIoMap,
                                     ToggleClipboardSliceDisplayOperation, ToggleClipboardCollectionDisplayOperation
using ProjecturedDomain.VersioningToAnyProjectionModule: VersioningToAnyProjection, VersioningToAnyProjectionIoMap,
                                       SetVersionCriterionOperation
using ProjecturedKernel.FocusingProjectionModule: FocusingProjection, ReplaceFocusPartOperation
using ProjecturedDomain.JsonToSyntaxModule: JsonToSyntax, JsonStringToSyntaxLeaf,
                               JsonNullToSyntaxLeaf, JsonBoolToSyntaxLeaf,
                               JsonNumberToSyntaxLeaf, JsonArrayToSyntaxNode,
                               JsonObjectToSyntaxNode,
                               JsonInsertionToSyntaxLeaf
using ProjecturedDomain.XmlToSyntaxModule: XmlToSyntax, XmlTextToSyntaxLeaf, XmlElementToSyntaxNode
using ProjecturedDomain.FileSystemToSyntaxModule: FileSystemFileToSyntaxLeaf, FileSystemDirectoryToSyntaxNode, FileSystemToSyntax,
                                 filesystem_marker_eligible
using ProjecturedDomain.WorkspaceToFileSystemModule: WorkspaceFolderToFileSystemDirectory, WorkspaceToFileSystem
using ProjecturedDomain.ObjectToSyntaxModule: ObjectToSyntax, NothingToSyntaxLeaf, BoolToSyntaxLeaf,
                              NumberToSyntaxLeaf, StringToSyntaxLeaf, SymbolToSyntaxLeaf,
                              CharToSyntaxLeaf, ObjectNodeToSyntaxNode, print_object, search_references, search_objects
using ProjecturedDomain.ObjectToJsonModule: ObjectToJson, NothingToJsonNull, BoolToJsonBool,
                            NumberToJsonNumber, StringToJsonString, SymbolToJsonString,
                            CharToJsonString, CellToJson, ObjectNodeToJsonObject, json_object
using ProjecturedDomain.BookToSyntaxModule: BookBookToSyntaxNode, BookChapterToSyntaxNode,
                            BookParagraphToSyntaxLeaf, BookListToSyntaxNode,
                            BookPictureToSyntaxLeaf, BookToSyntax
using ProjecturedDomain.ClipboardModule: ClipboardDocument, ClipboardInsertion,
                        ClipboardSlice, ClipboardCollection
using ProjecturedDomain.VersioningModule: VersioningDocument, VersionProperties, ObjectVersion, VersionedObject,
                         IVersionProperties, IObjectVersion, IVersionedObject,
                         VersionCriterion, VersionCriterionLatest, VersionCriterionIndex,
                         VersionCriterionByAuthor, VersionCriterionAsOf, VersionCriterionPredicate,
                         select_version
using ProjecturedKernel.CollectionModule: CellVector, CellMatrix, CellTable, ListNode, CollectionDocument, left_tail, right_tail, cell_at, take_first_n
using ProjecturedDomain.BookModule: BookDocument, BookInsertion,
                   BookBook, BookChapter, BookParagraph, BookList, BookPicture
using ProjecturedDomain.JuliaParserModule: juliaparse, juliaparse_file
using ProjecturedDomain.JsonParserModule: jsonparse, jsonparse_file
using ProjecturedDomain.XmlParserModule: xmlparse, xmlparse_file
using ProjecturedDomain.SqlParserModule: sqlparse, sqlparse_file
using ProjecturedDomain.ComponentModule: ComponentDocument, ComponentMasterDetail
using ProjecturedDomain.WorkbenchModule: WorkbenchDocument, WorkbenchInsertion,
                        WorkbenchWorkbench, WorkbenchPage,
                        WorkbenchNavigator, WorkbenchConsole, WorkbenchDescriptor,
                        WorkbenchOperator, WorkbenchSearcher, WorkbenchEvaluator,
                        WorkbenchAssistant,
                        WorkbenchEditor,
                        WorkbenchOpenDocumentOperation, WorkbenchCloseDocumentOperation
using ProjecturedDomain.ColorModule: StyleColor
using ProjecturedDomain.GeometryModule: Inset, Point2D,
                      inset_default, inset_size, inset_width, inset_height,
                      inset_top_left, inset_top_right, inset_bottom_left, inset_bottom_right
using ProjecturedDomain.WidgetModule: WidgetDocument, WidgetInsertion,
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
using ProjecturedDomain.LayoutModule: LayoutDocument,
                     HorizontalLayout, VerticalLayout, GridLayout, FlowLayout,
                     LayoutConstraint, allocate_axis,
                     layout_min, layout_max, layout_preferred, layout_weight
using ProjecturedDomain.GraphModule: GraphDocument, GraphInsertion, GraphVertex, GraphEdge, GraphGraph
using ProjecturedDomain.GraphLayoutModule: GraphLayoutDocument, VertexLayout, EdgeLayout, GraphLayout, GraphConstraint
using ProjecturedDomain.GraphLayoutEngineModule: GraphLayoutEngine, FallbackLayoutEngine, AdaptagramsEngine, layout_graph
using ProjecturedDomain.ImageModule: ImageDocument, ImageInsertion, ImageFile, ImageMemory
using ProjecturedKernel.ScreenDocumentModule: ScreenDocument, WindowDocument, EventEnvelope, WindowCloseRequest, WindowResizeEvent
using ProjecturedDomain.TooltipDocumentModule: TooltipSource
using ProjecturedDomain.TextToStringModule: TextToString, TextTextToString, TextStringToString, TextNewlineToString
using ProjecturedDomain.TextLineNumberingModule: LineNumbering, TextLineNumbering
using ProjecturedDomain.WordWrappingModule: WordWrapping, WordWrappingIoMap, WrapSeg
using ProjecturedDomain.TextFirstLineModule: TextFirstLine, TextFirstLineIoMap
using ProjecturedDomain.TextFilteringModule: TextFiltering, TextFilteringIoMap
using ProjecturedDomain.TextHighlightingModule: TextHighlighting, TextHighlightingIoMap, HighlightSeg
using ProjecturedDomain.SelectionInvertingModule: SelectionInverting, SelectionInvertingIoMap, SelSeg
using ProjecturedDomain.SyntaxToTextModule: SyntaxToText, SyntaxNodeToTextIoMap,
                                       SyntaxLeafToText, SyntaxListToText
using ProjecturedDomain.PrimitiveToSyntaxModule: PrimitiveToSyntax, PrimitiveBoolToSyntaxLeaf,
                                 PrimitiveNumberToSyntaxLeaf, PrimitiveStringToSyntaxLeaf
using ProjecturedDomain.PrimitiveToTextModule: PrimitiveToText, PrimitiveBoolToText,
                               PrimitiveNumberToText, PrimitiveStringToTextText
using ProjecturedDomain.ReferenceToTextModule: ReferenceToText, ReferenceToHumanReadableText
using ProjecturedDomain.MathToSyntaxModule: MathToSyntax, MathInsertionToSyntaxLeaf, MathVariableToSyntaxLeaf,
                            MathBinaryOperationToSyntaxNode, MathParenthesizedToSyntaxNode,
                            MathAssignmentToSyntaxNode
using ProjecturedDomain.SqlToSyntaxModule: SqlToSyntax, SqlAllColumnsToSyntaxLeaf, SqlColumnReferenceToSyntaxLeaf,
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
using ProjecturedDomain.JuliaToSyntaxModule: JuliaToSyntax, JuliaIdentifierToSyntaxLeaf, JuliaIntegerToSyntaxLeaf,
                             JuliaBinaryOpToSyntaxNode, JuliaCallToSyntaxNode,
                             JuliaIfToSyntaxNode, JuliaFunctionToSyntaxNode,
                             JuliaBlockToSyntaxNode
using ProjecturedDomain.FormulaToSyntaxModule: FormulaToSyntax, FormulaInsertionToSyntaxLeaf,
                              FormulaReferenceToSyntaxLeaf, FormulaFormulaToSyntaxNode,
                              FormulaEnvironmentToSyntaxNode
using ProjecturedDomain.DocumentInsertionToSyntaxModule: InsertionToSyntaxLeaf,
                                         DocumentInsertionToSyntaxLeaf, JuliaInsertionToSyntaxLeaf,
                                         default_factory, default_completion
using ProjecturedDomain.CollectionToSyntaxModule: CollectionToSyntax, CollectionCellVectorToSyntax,
                                  CollectionListNodeToSyntax
using ProjecturedDomain.TextToGraphicsModule: TextToGraphics, TextToGraphicsIoMap
using ProjecturedDomain.LayoutToGraphicsModule: HorizontalLayoutToGraphicsCanvas,
                               VerticalLayoutToGraphicsCanvas,
                               GridLayoutToGraphicsCanvas,
                               FlowLayoutToGraphicsCanvas,
                               LayoutConstraintToGraphicsCanvas,
                               LayoutToGraphics, GridLayoutIoMap
using ProjecturedDomain.GraphToGraphLayoutModule: GraphGraphToGraphLayout, GraphToGraphLayout,
                                 GraphGraphToGraphLayoutIoMap
using ProjecturedDomain.GraphLayoutToGraphicsModule: GraphLayoutToGraphicsCanvas,
                                    GraphLayoutToGraphicsCanvasIoMap
using ProjecturedDomain.WidgetToGraphicsModule: WidgetInsertionToGraphicsCanvas, WidgetLabelToGraphicsCanvas, WidgetTextToGraphicsCanvas,
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
using ProjecturedDomain.TextToWidgetModule: TextToWidget, TextToWidgetIoMap, WidgetAndTextToGraphics
using ProjecturedDomain.SyntaxToWidgetModule: SyntaxToWidget, SyntaxLeafToWidget, SyntaxNodeToWidget
using ProjecturedDomain.WorkbenchToWidgetModule: WorkbenchWorkbenchToWidgetShell,    WorkbenchWorkbenchToWidgetShellIoMap,
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
using ProjecturedDomain.GraphicsCachingModule: GraphicsCanvasToGraphicsImage, GraphicsCaching
using ProjecturedKernel.GestureRecognizerModule: GestureRecognizer, recognize!, next_gesture!
using ProjecturedKernel.EditorModule: Editor, run!, play_live!
using ProjecturedKernel.AgentModule: make_agent_server, agent_server_start!, agent_server_stop!
# McpModule (core) holds the dependency-free editor tools; the MCP transport
# (McpServer, mcp_start!/stop!, mcp_tools/resources) lives in the
# ProjecturedMCPExt extension and is reached through make_agent_server(:mcp, …).
using ProjecturedKernel.McpModule: search_documentation, search_api,
                  list_guides, read_guide, list_modules, list_classes, list_functions,
                  read_module_documentation, read_class_documentation, read_function_documentation,
                  execute_julia_code, register_default_tools_and_resources!
using ProjecturedKernel.ToolRegistryModule: Tool, Resource,
                            register_tool!, register_tools!, list_tools, call_tool,
                            register_resource!, register_resources!, list_resources, read_resource,
                            anthropic_tool_schema
# stream_message (the Anthropic HTTP client) lives in the ProjecturedLLMExt extension.
using ProjecturedKernel.LlmModule: LlmBackend, AnthropicLlm, FakeLlm, stream_turn
using ProjecturedDomain.EvaluatorModule: EvaluatorDocument, EvaluatorForm, EvaluatorToplevel, result_text, eval_kind_label
using ProjecturedDomain.FormulaModule: FormulaDocument, FormulaInsertion, FormulaReference, FormulaFormula,
                      FormulaEnvironment, formula_result_text, wire_result!,
                      resolve, column_letter, cell_name,
                      formula_references, formula_dependencies,
                      would_create_cycle, topological_order,
                      formula_to_expr, evaluate_formula
using ProjecturedDomain.ConversationModule: ConversationDocument, ConversationConversation,
                            ConversationTurn, ConversationPart, ConversationDraft,
                            ConversationThinking, thinking_part
using ProjecturedDomain.ConversationToSyntaxModule: ConversationToSyntax,
                                    ConversationConversationToSyntaxNode,
                                    ConversationTurnToSyntaxNode,
                                    ConversationPartToSyntaxNode
using ProjecturedDomain.ConversationToWidgetModule: ConversationToWidget,
                                    ConversationConversationToWidgetComposite,
                                    ConversationTurnToWidgetComposite,
                                    ConversationPartToWidget
using ProjecturedDomain.WorkbenchAssistantModule: SubmitProseOperation, SubmitJuliaOperation, SubmitDraftTurnOperation,
                                   ClearInputOperation, ResetConversationOperation,
                                   build_messages, conversation_to_string, write_conversation, assistant_tool_schemas,
                                   dispatch_assistant_tool, parse_markdown_blocks
using ProjecturedDomain.ConversationEditorModule: ConversationComposerToWidget, composer_read,
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
export set_selection!, clear_selection!, replace_selection!, document_read
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
export DatabaseAdapter, RawDatabaseResult, make_database_adapter,
       db_connect!, db_close!, db_alive, db_rowid_column,
       db_query, db_execute_raw, db_insert!, db_update!, db_delete!,
       db_catalog_databases, db_catalog_schemas, db_catalog_tables, db_catalog_columns
# OdbcDatabaseAdapter, OdbcConnectionPool, DatabaseTableToTabularGrid/IoMap, the
# live-query projections, with_connection/dsn_for/close_pool! are provided by the
# ProjecturedODBCExt extension (build via make_database_adapter(:odbc)).
export DatabaseInstanceDocument, DatabaseInstance, DatabaseCredentials
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
# DatabaseInstanceToDbCatalog and SqlToCellTable are provided by ProjecturedODBCExt.
export CellTableToTable, CellTableToWidgetTable
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
export juliaparse, juliaparse_file
export jsonparse, jsonparse_file
export xmlparse, xmlparse_file
export sqlparse, sqlparse_file
export FileSystemDocument, FileSystemInsertion, FileSystemFile, FileSystemDirectory, make_filesystem_pathname
export WorkspaceDocument, WorkspaceFolder, Workspace
export TextDocument, TextInsertion, TextText, TextString, TextNewline, TextGraphics
export StyleFont, make_style_font, font_scaled_size
export StyleText, make_style_text
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
export Backend, init!, quit!, measure_text, make_backend, write_image, record_video,
       render_canvas, decode_image, display_size, set_display_size_provider!
export Screen
# write_image/record_video are exported above (BackendModule generics). SdlBackend and
# the sdl_*/GraphicsCanvasToImageFile symbols are provided by ProjecturedSDLExt.
export ConsoleBackend, console_render
# WebBackend/web_key_to_symbol are provided by ProjecturedWebExt (make_backend(:web)).
export write_pdf, GraphicsCanvasToPdfFile, pdf_measure_text, truetype_measure_text
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
export VersioningDocument, VersionedObject, ObjectVersion, VersionProperties,
       IVersionedObject, IObjectVersion, IVersionProperties
export VersionCriterion, VersionCriterionLatest, VersionCriterionIndex,
       VersionCriterionByAuthor, VersionCriterionAsOf, VersionCriterionPredicate,
       select_version
export VersioningToAnyProjection, VersioningToAnyProjectionIoMap,
       SetVersionCriterionOperation
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
using ProjecturedDomain.DocumentCoreModule: DocumentBase, DocumentNothing, DocumentInsertion, DocumentReference
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
export make_agent_server, agent_server_start!, agent_server_stop!
export search_documentation, search_api,
       list_guides, read_guide, list_modules, list_classes, list_functions,
       read_module_documentation, read_class_documentation, read_function_documentation,
       execute_julia_code, register_default_tools_and_resources!
export Tool, Resource, register_tool!, register_tools!, list_tools, call_tool,
       register_resource!, register_resources!, list_resources, read_resource,
       anthropic_tool_schema
# stream_message is provided by ProjecturedLLMExt.
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
