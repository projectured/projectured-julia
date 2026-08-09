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
# Every alias carries the module's own name, so a domain file names a module
# exactly as the module names itself.
const BackendModule = ProjecturedKernel.BackendModule
const IntentModule = ProjecturedKernel.IntentModule
const CollectionModule = ProjecturedBase.CollectionModule
const DocumentCoreModule = ProjecturedBase.DocumentCoreModule
const DomainModule = ProjecturedBase.DomainModule
const CopyingProjectionModule = ProjecturedBase.CopyingProjectionModule
const DeviceModule = ProjecturedKernel.DeviceModule
const DocumentModule = ProjecturedKernel.DocumentModule
const SelectionModule = ProjecturedKernel.SelectionModule
const ProjectionReferenceStepModule = ProjecturedKernel.ProjectionReferenceStepModule
const PointReferenceStepModule = ProjecturedVisual.PointReferenceStepModule
const TextSpanReferenceStepModule = ProjecturedVisual.TextSpanReferenceStepModule
const TextColumnReferenceStepModule = ProjecturedVisual.TextColumnReferenceStepModule
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
const OperationModule = ProjecturedKernel.OperationModule
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
# The shared insert-by-typing leaf and the `*Nothing` placeholder leaf. Every
# domain's insertion prints through it.
const DocumentInsertionToSyntaxModule = ProjecturedVisual.DocumentInsertionToSyntaxModule

# Plot — the vocabulary a chart and a sequence chart share.
const PlotGeometryModule = ProjecturedVisual.PlotGeometryModule
const PlotStyleModule = ProjecturedVisual.PlotStyleModule

# Backend
const ConsoleBackendModule = ProjecturedVisual.ConsoleBackendModule
const PdfBackendModule = ProjecturedVisual.PdfBackendModule

# File format — natural text I/O + the document-file entry point (moved down to
# visual, beside the text printers it needs). Domains register the per-domain
# seams (natural_syntax_projection / natural_extension / parse_natural /
# new_document_seed) on these modules from their existing ToSyntax files.
const NaturalFormatModule = ProjecturedVisual.NaturalFormatModule
const NaturalRegistryModule = ProjecturedVisual.NaturalRegistryModule
const DocumentFileModule = ProjecturedVisual.DocumentFileModule

# ── Extracted domain packages ──────────────────────────────────────────────
# Each concrete domain becomes its own package. Bind their submodules the same
# way the engine packages' are bound above, so a slice still inside this package
# names them unchanged (`..JsonModule`). This tuple grows with every extraction
# and this package disappears when the last slice leaves.
using ProjecturedJson
using ProjecturedWorkbench
using ProjecturedConversation
using ProjecturedProcess
using ProjecturedFsm
using ProjecturedFormula
using ProjecturedDbCatalog
using ProjecturedSequenceChart
using ProjecturedChart
using ProjecturedGraph
using ProjecturedFileSystem
using ProjecturedDatabase
using ProjecturedSql
using ProjecturedJulia
using ProjecturedMath
using ProjecturedBook
using ProjecturedRst
using ProjecturedMarkdown
using ProjecturedXml
using ProjecturedYaml

for _src in (ProjecturedJson, ProjecturedWorkbench, ProjecturedConversation, ProjecturedProcess, ProjecturedFsm, ProjecturedFormula, ProjecturedDbCatalog, ProjecturedSequenceChart, ProjecturedChart, ProjecturedGraph, ProjecturedFileSystem, ProjecturedDatabase, ProjecturedSql, ProjecturedJulia, ProjecturedMath, ProjecturedBook, ProjecturedRst, ProjecturedMarkdown, ProjecturedXml, ProjecturedYaml,)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) === _src) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

# ── Concrete domains, parsers, projections, backends, editors ──────────────
# Each source slice groups a document + its parser + its XToSyntax bridge in one
# folder. Load order: document/parser/toSyntax within each slice; slices ordered
# so cross-slice edges are satisfied (json/xml/yaml/julia/math/markdown/book/
# component independent; formula → julia; dbcatalog → sql) — an acyclic
# slice DAG.
# The plot vocabulary both plotted notations share: the arithmetic and the
# colour/marker cycles. Neither the chart nor the sequence chart owns it.
# DocumentInsertionToSyntax before every domain ToSyntax: it defines the shared
# insertion leaf (typed-name buffer with live completion) and the shared
# *Nothing placeholder leaf. It names no domain at all — a domain builds its own
# source insertion from this leaf, in a file it already has.
# The Julia source hole: the keyword scaffolds and the JuliaInsertion leaf. It
# needs the generic insertion leaf above and the Julia parser, and JuliaToSyntax
# needs it, so it sits between them.
# The recorder and the overlay come after the log chain: the overlay names
# GestureLogToSyntax to render the panel.
# The two-dimensional form of a formula: its own typesetter, next to the linear
# one. Needs the visual style metrics (TrueTypeModule) and Graphics only.
# After julia/JuliaToSyntax.jl: the notation merges the Julia dispatch table so
# embedded guards/actions/entry/helpers render through the same recursion.
# Same merge as the fsm notation: the process notation renders embedded
# actions/conditions through the Julia dispatch table.
# After the graph slice projections: the diagram prints into GraphGraph and
# relies on the stock layout/graphics stages to draw it.
# After the graph slice projections, as the fsm diagram is: the flowchart
# prints into GraphGraph and relies on the stock layout/graphics stages.
# Code generation: builds a JuliaDocument module and writes it through the
# fileformat natural-text path, so it follows both.
# Realization: builds a JuliaDocument function and writes it through the
# fileformat natural-text path, so it follows both.
# The debug runner: realization + runtime + session meet here, and nowhere
# else, so it follows all three.

end # module ProjecturedDomain
