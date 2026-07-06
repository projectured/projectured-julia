"""
    ProjecturedDomain

All concrete ProjecturEd domains and their projections: the document types
(JSON/XML/Text/Syntax/Graphics/Widget/Workbench/SQL/...), the parsers, the
Console/PDF backends, and the domain-coupled editors (WorkbenchAssistant,
ConversationEditor). Builds on the headless `ProjecturedKernel` engine and
owns the SDL/ODBC/Web package extensions. The flat public API is re-exported
by the `Projectured` umbrella.

Kernel submodules are bound here as `const` aliases so the domain source files
can keep their original relative `..XxxModule` references unchanged — inside a
submodule of `ProjecturedDomain`, `..CellModule` resolves through the
`const CellModule = ProjecturedKernel.CellModule` binding below.
"""
module ProjecturedDomain

using ProjecturedKernel
# ProjecturedBase — concrete engine documents + document-shaped projections.
using ProjecturedBase
# ProjecturedVisual — style/graphics/layout/text/widget/syntax/backend slices.
using ProjecturedVisual

# ── Kernel submodule aliases (make relative ..XxxModule refs resolve into the
#    kernel; see the module docstring) ──────────────────────────────────────
# Some aliases carry a second, deprecated name (e.g. BackendApiModule) so files
# that still reference it keep resolving to the canonical module.
const BackendApiModule = ProjecturedKernel.BackendModule
const BackendModule = ProjecturedKernel.BackendModule
const IntentModule = ProjecturedKernel.IntentModule
const CollectionModule = ProjecturedBase.CollectionModule
const CopyingProjectionModule = ProjecturedBase.CopyingProjectionModule
const DeviceApiModule = ProjecturedKernel.DeviceModule
const DeviceModule = ProjecturedKernel.DeviceModule
const DisplayModule = ProjecturedKernel.DisplayModule
const DocumentApiModule = ProjecturedKernel.DocumentModule
const DocumentModule = ProjecturedKernel.DocumentModule
const TimeModule = ProjecturedKernel.TimeModule
const EventCaseModule = ProjecturedKernel.GestureModule
const GestureBindingModule = ProjecturedKernel.GestureModule
const GestureModule = ProjecturedKernel.GestureModule
const ProjectionGestureBindingsModule = ProjecturedKernel.ProjectionGestureBindingsModule
const ProjectionTemplateModule = ProjecturedKernel.ProjectionTemplateModule
const IoMapApiModule = ProjecturedKernel.IoMapApiModule
const IoMapModule = ProjecturedKernel.IoMapModule
const KeyboardModule = ProjecturedKernel.KeyboardModule
const PlaybackModule = ProjecturedKernel.PlaybackModule
const LlmModule = ProjecturedKernel.LlmModule
const McpModule = ProjecturedKernel.McpModule
const AgentApiModule = ProjecturedKernel.AgentModule
const AgentModule = ProjecturedKernel.AgentModule
const ModifiersModule = ProjecturedKernel.ModifiersModule
const MouseModule = ProjecturedKernel.MouseModule
const NestingProjectionModule = ProjecturedKernel.NestingProjectionModule
const OperationApiModule = ProjecturedKernel.OperationModule
const OperationModule = ProjecturedKernel.OperationModule
const OperationRerootingModule = ProjecturedKernel.OperationModule
const PerformanceCounterModule = ProjecturedKernel.PerformanceCounterModule
const PredicateDispatchingProjectionModule = ProjecturedKernel.PredicateDispatchingProjectionModule
const IdentityProjectionModule = ProjecturedKernel.IdentityProjectionModule
const PrimitiveModule = ProjecturedBase.PrimitiveModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const CellModule = ProjecturedKernel.CellModule
const RecursiveProjectionModule = ProjecturedKernel.RecursiveProjectionModule
const ReferenceBuilderModule = ProjecturedKernel.ReferenceModule
const ReferenceCaseModule = ProjecturedKernel.ReferenceModule
const ReferenceDispatchingProjectionModule = ProjecturedKernel.ReferenceDispatchingProjectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ScreenDocumentModule = ProjecturedVisual.ScreenDocumentModule
const ScreenDeviceModule = ProjecturedKernel.ScreenDeviceModule
const ChainingProjectionModule = ProjecturedKernel.ChainingProjectionModule
const SortingProjectionModule = ProjecturedBase.SortingProjectionModule
const FilteringProjectionModule = ProjecturedBase.FilteringProjectionModule
const SearchingProjectionModule = ProjecturedBase.SearchingProjectionModule
const WindowManagingProjectionModule = ProjecturedVisual.WindowManagingProjectionModule
const ReaderDefaultsModule = ProjecturedBase.ReaderDefaultsModule
const HigherOrderCompoundModule = ProjecturedBase.HigherOrderCompoundModule
const GenericCompoundModule = ProjecturedBase.GenericCompoundModule
const BinarySerializationModule = ProjecturedBase.BinarySerializationModule
const ToolRegistryModule = ProjecturedKernel.ToolRegistryModule
const TypeDispatchingProjectionModule = ProjecturedKernel.TypeDispatchingProjectionModule

# ── Visual submodule aliases ───────────────────────────────────────────────
# Style
const ColorModule = ProjecturedVisual.ColorModule
const FontModule = ProjecturedVisual.FontModule
const GeometryModule = ProjecturedVisual.GeometryModule
const ImageModule = ProjecturedVisual.ImageModule
const StyleStrokeModule = ProjecturedVisual.StyleStrokeModule
const StyleTextModule = ProjecturedVisual.StyleTextModule

# Graphics. Note: the on-disk module names do NOT carry the "Projection" suffix
# except where the visual file itself does — the aliases match the module names
# in each visual file's `module …` line.
const GraphicsModule = ProjecturedVisual.GraphicsModule
const GraphicsCachingModule = ProjecturedVisual.GraphicsCachingModule

# Layout
const LayoutModule = ProjecturedVisual.LayoutModule
const ConstraintSolverModule = ProjecturedVisual.ConstraintSolverModule
const LayoutToGraphicsModule = ProjecturedVisual.LayoutToGraphicsModule
const CollectionToLayoutModule = ProjecturedVisual.CollectionToLayoutModule

# Text
const TextModule = ProjecturedVisual.TextModule
const TextToGraphicsModule = ProjecturedVisual.TextToGraphicsModule
const TextToStringModule = ProjecturedVisual.TextToStringModule
const TextLineNumberingModule = ProjecturedVisual.TextLineNumberingModule
const WordWrappingModule = ProjecturedVisual.WordWrappingModule
const TextFilteringModule = ProjecturedVisual.TextFilteringModule
const TextFirstLineModule = ProjecturedVisual.TextFirstLineModule
const TextHighlightingModule = ProjecturedVisual.TextHighlightingModule
const SelectionInvertingModule = ProjecturedVisual.SelectionInvertingModule
const PrimitiveToTextModule = ProjecturedVisual.PrimitiveToTextModule
const ReferenceToTextModule = ProjecturedVisual.ReferenceToTextModule

# Widget
const WidgetModule = ProjecturedVisual.WidgetModule
const WidgetToGraphicsModule = ProjecturedVisual.WidgetToGraphicsModule
const ObjectToWidgetModule = ProjecturedVisual.ObjectToWidgetModule
const WidgetHoverTrackingProjectionModule = ProjecturedVisual.WidgetHoverTrackingProjectionModule
const ProjectionConfiguringProjectionModule = ProjecturedVisual.ProjectionConfiguringProjectionModule
const WidgetPopupResolverProjectionModule = ProjecturedVisual.WidgetPopupResolverProjectionModule

# Syntax
const SyntaxModule = ProjecturedVisual.SyntaxModule
const SyntaxToTextModule = ProjecturedVisual.SyntaxToTextModule
const ObjectToSyntaxModule = ProjecturedVisual.ObjectToSyntaxModule
const CollectionToSyntaxModule = ProjecturedVisual.CollectionToSyntaxModule
const PrimitiveToSyntaxModule = ProjecturedVisual.PrimitiveToSyntaxModule

# Backend
const ConsoleBackendModule = ProjecturedVisual.ConsoleBackendModule
const PdfBackendModule = ProjecturedVisual.PdfBackendModule

# ── Concrete domains, parsers, projections, backends, editors ──────────────
include("clipboard/OsClipboard.jl")
include("core/Document.jl")
# Each source slice groups a document + its parser + its XToSyntax bridge in one
# folder. Load order: document/parser/toSyntax within each slice; slices ordered
# so cross-slice edges are satisfied (json/xml/yaml/julia/math/markdown/book
# independent; formula → julia; dbcatalog → sql) — an acyclic
# slice DAG.
include("json/Json.jl")
include("yaml/Yaml.jl")
include("gesturemap/GestureMap.jl")
include("math/Math.jl")
include("julia/Julia.jl")
include("database/DatabaseInstance.jl")
include("database/Database.jl")
include("dbcatalog/DbCatalog.jl")
include("sql/Sql.jl")
include("xml/Xml.jl")
include("filesystem/FileSystem.jl")
include("workbench/Workspace.jl")
include("clipboard/Clipboard.jl")
include("versioning/Versioning.jl")
include("graph/Graph.jl")
include("graph/GraphLayout.jl")
include("graph/GraphLayoutEngine.jl")
include("book/Book.jl")
include("markdown/Markdown.jl")
include("conversation/Evaluator.jl")
include("formula/Formula.jl")
include("conversation/Conversation.jl")
include("julia/JuliaParser.jl")
include("json/JsonParser.jl")
include("yaml/YamlParser.jl")
include("xml/XmlParser.jl")
include("markdown/MarkdownParser.jl")
include("sql/SqlParser.jl")
include("workbench/Workbench.jl")
include("tooltip/Tooltip.jl")
include("inspector/ReferenceInspector.jl")
include("dragging/Dragging.jl")
include("tooltip/TooltipDecorator.jl")
include("gesturemap/GestureHelpDecorator.jl")
include("clipboard/ClipboardToAny.jl")
include("versioning/VersioningToAny.jl")
include("dragging/DraggingProjection.jl")
include("json/JsonToSyntax.jl")
include("yaml/YamlToSyntax.jl")
include("gesturemap/GestureMapToSyntax.jl")
include("xml/XmlToSyntax.jl")
include("markdown/MarkdownToSyntax.jl")
include("filesystem/FileSystemToSyntax.jl")
include("filesystem/FileSystemToWidget.jl")
include("workbench/WorkspaceToFileSystem.jl")
include("graph/GraphToGraphLayout.jl")
include("graph/GraphLayoutToGraphics.jl")
include("book/BookToSyntax.jl")
include("inspector/ReferenceInspectorToText.jl")
include("inspector/HoverProbe.jl")
include("math/MathToSyntax.jl")
# DocumentInsertionToSyntax before JuliaToSyntax/SqlToSyntax: it defines the
# per-domain insertion→syntax leaves (JuliaInsertionToSyntaxLeaf, …) those
# projections register, and it depends on none of them.
include("insertion/InsertionToSyntax.jl")
include("julia/JuliaToSyntax.jl")
include("formula/FormulaToSyntax.jl")
include("sql/SqlToSyntax.jl")
include("dbcatalog/DbCatalogToSql.jl")
include("dbcatalog/DbCatalogToSyntax.jl")
include("conversation/ConversationToSyntax.jl")
include("conversation/ConversationToWidget.jl")
include("workbench/WorkbenchToWidget.jl")
include("insertion/NaturalProjection.jl")
include("naturalformat/NaturalFormat.jl")
include("naturalformat/DocumentFile.jl")
include("database/DatabaseAdapters.jl")
include("conversation/ConversationEditor.jl")
include("workbench/WorkbenchAssistant.jl")
include("workbench/WorkbenchFile.jl")

end # module ProjecturedDomain
