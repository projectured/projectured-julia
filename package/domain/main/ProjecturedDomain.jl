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
const DocumentCoreModule = ProjecturedBase.DocumentCoreModule
const DomainModule = ProjecturedBase.DomainModule
const CopyingProjectionModule = ProjecturedBase.CopyingProjectionModule
const DeviceModule = ProjecturedKernel.DeviceModule
const DocumentApiModule = ProjecturedKernel.DocumentModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ReferenceApiModule = ProjecturedKernel.ReferenceModule
const SelectionModule = ProjecturedKernel.SelectionModule
const SelectionApiModule = ProjecturedKernel.SelectionModule
const ProjectionReferenceStepModule = ProjecturedKernel.ProjectionReferenceStepModule
const ProjectionReferenceStepApiModule = ProjecturedKernel.ProjectionReferenceStepModule
const PointReferenceStepModule = ProjecturedVisual.PointReferenceStepModule
const PointReferenceStepApiModule = ProjecturedVisual.PointReferenceStepModule
const TextSpanReferenceStepModule = ProjecturedVisual.TextSpanReferenceStepModule
const TextSpanReferenceStepApiModule = ProjecturedVisual.TextSpanReferenceStepModule
const TextColumnReferenceStepModule = ProjecturedVisual.TextColumnReferenceStepModule
const TextColumnReferenceStepApiModule = ProjecturedVisual.TextColumnReferenceStepModule
const ClockModule = ProjecturedKernel.ClockModule
const EventModule = ProjecturedKernel.EventModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const ProjectionGestureBindingsModule = ProjecturedKernel.ProjectionGestureBindingsModule
const ProjectionTemplateModule = ProjecturedKernel.ProjectionTemplateModule
const IoMapModule = ProjecturedKernel.IoMapModule
const PlaybackModule = ProjecturedKernel.PlaybackModule
const LlmModule = ProjecturedKernel.LlmModule
const ToolModule = ProjecturedKernel.ToolModule
const AgentServerModule = ProjecturedKernel.AgentServerModule
const AgentModule = ProjecturedKernel.AgentModule
const NestingProjectionModule = ProjecturedBase.NestingProjectionModule
const OperationApiModule = ProjecturedKernel.OperationModule
const OperationModule = ProjecturedKernel.OperationModule
const OperationRerootingModule = ProjecturedKernel.OperationModule
const PerformanceCounterModule = ProjecturedKernel.PerformanceCounterModule
const PredicateDispatchingProjectionModule = ProjecturedBase.PredicateDispatchingProjectionModule
const IdentityProjectionModule = ProjecturedBase.IdentityProjectionModule
const PrimitiveModule = ProjecturedBase.PrimitiveModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const CellModule = ProjecturedKernel.CellModule
const CellStructModule = ProjecturedKernel.CellStructModule
const RecursiveProjectionModule = ProjecturedBase.RecursiveProjectionModule
const ReferenceBuilderModule = ProjecturedKernel.ReferenceModule
const ReferenceCaseModule = ProjecturedKernel.ReferenceModule
const ReferenceDispatchingProjectionModule = ProjecturedBase.ReferenceDispatchingProjectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ScreenDocumentModule = ProjecturedVisual.ScreenDocumentModule
const ChainingProjectionModule = ProjecturedBase.ChainingProjectionModule
const SortingProjectionModule = ProjecturedBase.SortingProjectionModule
const FilteringProjectionModule = ProjecturedBase.FilteringProjectionModule
const SearchingProjectionModule = ProjecturedBase.SearchingProjectionModule
const WindowManagingProjectionModule = ProjecturedVisual.WindowManagingProjectionModule
const ReaderDefaultsModule = ProjecturedBase.ReaderDefaultsModule
const HigherOrderCompoundModule = ProjecturedBase.HigherOrderCompoundModule
const GenericCompoundModule = ProjecturedBase.GenericCompoundModule
const BinarySerializationModule = ProjecturedBase.BinarySerializationModule
const FileProjectModule = ProjecturedBase.FileProjectModule
const TextFileModule = ProjecturedBase.TextFileModule
const TypeDispatchingProjectionModule = ProjecturedBase.TypeDispatchingProjectionModule

# ── Visual submodule aliases ───────────────────────────────────────────────
# Style
const ColorModule = ProjecturedVisual.ColorModule
const FontModule = ProjecturedVisual.FontModule
const TrueTypeModule = ProjecturedVisual.TrueTypeModule
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

# File format — natural text I/O + the document-file entry point (moved down to
# visual, beside the text printers it needs). Domains register the per-domain
# seams (natural_syntax_projection / natural_extension / parse_natural /
# new_document_seed) on these modules from their existing ToSyntax files.
const NaturalFormatModule = ProjecturedVisual.NaturalFormatModule
const DocumentFileModule = ProjecturedVisual.DocumentFileModule

# ── Concrete domains, parsers, projections, backends, editors ──────────────
# Each source slice groups a document + its parser + its XToSyntax bridge in one
# folder. Load order: document/parser/toSyntax within each slice; slices ordered
# so cross-slice edges are satisfied (json/xml/yaml/julia/math/markdown/book/
# component independent; formula → julia; dbcatalog → sql) — an acyclic
# slice DAG.
include("json/Json.jl")
include("yaml/Yaml.jl")
include("gesturemap/GestureMap.jl")
include("gesturemap/CommandPalette.jl")
include("gesturelog/GestureLog.jl")
include("math/Math.jl")
include("julia/Julia.jl")
include("database/DatabaseInstance.jl")
include("database/Database.jl")
include("dbcatalog/DbCatalog.jl")
include("sql/Sql.jl")
include("xml/Xml.jl")
include("filesystem/FileSystem.jl")
include("component/Component.jl")
include("workbench/Workspace.jl")
include("graph/Graph.jl")
include("graph/GraphLayout.jl")
include("graph/GraphLayoutEngine.jl")
include("chart/ChartGeometry.jl")
include("chart/ChartSampleReferenceStep.jl")
include("chart/Chart.jl")
include("chart/ChartPlot.jl")
include("sequencechart/SequenceChartGeometry.jl")
include("sequencechart/SequenceChartRowReferenceStep.jl")
include("sequencechart/SequenceChart.jl")
include("sequencechart/SequenceChartPlot.jl")
include("fsm/Fsm.jl")
include("fsm/FsmDiagram.jl")
include("book/Book.jl")
include("markdown/Markdown.jl")
include("rst/Rst.jl")
include("conversation/Evaluator.jl")
include("formula/Formula.jl")
include("conversation/Conversation.jl")
include("julia/JuliaParser.jl")
include("json/JsonParser.jl")
include("yaml/YamlParser.jl")
include("xml/XmlParser.jl")
include("markdown/MarkdownParser.jl")
include("rst/RstParser.jl")
include("sql/SqlParser.jl")
include("workbench/Workbench.jl")
include("gesturemap/GestureHelpDecorator.jl")
# DocumentInsertionToSyntax before every domain ToSyntax: it defines the shared
# insertion leaf (typed-name buffer with live completion), the per-domain
# delegates (JuliaInsertionToSyntaxLeaf, …) those projections register, and the
# shared *Nothing placeholder leaf — and it depends on no domain projection.
include("insertion/InsertionToSyntax.jl")
include("json/JsonToSyntax.jl")
include("json/JsonFile.jl")   # FileDocument wrapping a JsonDocument
include("julia/JuliaFile.jl") # FileDocument wrapping a JuliaDocument
include("yaml/YamlToSyntax.jl")
include("gesturemap/GestureMapToSyntax.jl")
include("gesturemap/CommandPaletteToSyntax.jl")
include("gesturemap/CommandPaletteDecorator.jl")
include("gesturelog/GestureLogToSyntax.jl")
# The recorder and the overlay come after the log chain: the overlay names
# GestureLogToSyntax to render the panel.
include("gesturelog/GestureLogRecorder.jl")
include("gesturelog/GestureLogOverlay.jl")
include("xml/XmlToSyntax.jl")
include("markdown/MarkdownToSyntax.jl")
include("rst/RstToSyntax.jl")
include("rst/RstFile.jl")   # FileDocument wrapping an RstDocument
include("markdown/MarkdownFile.jl") # FileDocument wrapping a MarkdownDocument
include("markdown/MarkdownToLayout.jl") # MarkdownRoot as a stack of blocks
include("xml/XmlFile.jl")           # FileDocument wrapping an XmlDocument
include("filesystem/FileSystemToSyntax.jl")
include("filesystem/FileSystemToWidget.jl")
include("workbench/WorkspaceToFileSystem.jl")
include("graph/GraphToGraphLayout.jl")
include("graph/GraphLayoutToGraphics.jl")
include("chart/ChartToChartPlot.jl")
include("chart/ChartPlotToGraphics.jl")
include("sequencechart/SequenceChartToSequenceChartPlot.jl")
include("sequencechart/SequenceChartPlotToGraphics.jl")
include("book/BookToSyntax.jl")
include("math/MathToSyntax.jl")
include("julia/JuliaToSyntax.jl")
include("formula/FormulaToSyntax.jl")
# After julia/JuliaToSyntax.jl: the notation merges the Julia dispatch table so
# embedded guards/actions/entry/helpers render through the same recursion.
include("fsm/FsmToSyntax.jl")
include("fsm/FsmToFsmDiagram.jl")
# After the graph slice projections: the diagram prints into GraphGraph and
# relies on the stock layout/graphics stages to draw it.
include("fsm/FsmDiagramToGraph.jl")
# Code generation: builds a JuliaDocument module and writes it through the
# fileformat natural-text path, so it follows both.
include("fsm/FsmToJuliaCode.jl")
include("sql/SqlToSyntax.jl")
include("dbcatalog/DbCatalogToSql.jl")
include("dbcatalog/DbCatalogToSyntax.jl")
include("conversation/ConversationToSyntax.jl")
include("conversation/ConversationToWidget.jl")
include("workbench/WorkbenchToWidget.jl")
include("insertion/EmbedToSyntax.jl")
include("insertion/NaturalProjection.jl")
include("database/DatabaseAdapters.jl")
include("conversation/ConversationEditor.jl")
include("workbench/WorkbenchAssistant.jl")
include("workbench/WorkbenchFile.jl")

end # module ProjecturedDomain
