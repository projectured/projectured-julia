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
# ProjecturedBase — kernel plan P7/P8: concrete engine documents +
# document-shaped projections.
using ProjecturedBase
# ProjecturedVisual — domain plan Q1: style/graphics/layout/text/widget/
# syntax/backend slices. Aliases below repoint moved modules to
# ProjecturedVisual so unmoved domain files keep resolving.
using ProjecturedVisual

# ── Kernel submodule aliases (make relative ..XxxModule refs resolve into the
#    kernel; see the module docstring) ──────────────────────────────────────
# Kernel plan P6: BackendApiModule renamed to BackendModule; the old name
# lives on as an alias.
const BackendApiModule = ProjecturedKernel.BackendModule
const BackendModule = ProjecturedKernel.BackendModule
const IntentModule = ProjecturedKernel.IntentModule
# Kernel plan P8 moved the concrete documents + doc-shaped projections to
# ProjecturedBase. Aliases repoint here so existing domain files (66
# importers of CollectionModule alone) keep resolving.
const CollectionModule = ProjecturedBase.CollectionModule
const CopyingProjectionModule = ProjecturedBase.CopyingProjectionModule
# Kernel plan P5: DeviceApiModule renamed to DeviceModule; the old name is
# still available here for domain/opt-in files.
const DeviceApiModule = ProjecturedKernel.DeviceModule
const DeviceModule = ProjecturedKernel.DeviceModule
const DisplayModule = ProjecturedKernel.DisplayModule
# Kernel plan P2 merged DocumentApiModule into DocumentModule; the old name
# stays here as an alias so existing domain/opt-in files keep resolving.
const DocumentApiModule = ProjecturedKernel.DocumentModule
const DocumentModule = ProjecturedKernel.DocumentModule
const TimeModule = ProjecturedKernel.TimeModule
# Kernel plan P5 (R4): EventCaseModule + GestureBindingModule merged into
# GestureModule; the old names live on as aliases.
const EventCaseModule = ProjecturedKernel.GestureModule
const GestureBindingModule = ProjecturedKernel.GestureModule
const GestureModule = ProjecturedKernel.GestureModule
const IoMapApiModule = ProjecturedKernel.IoMapApiModule
const IoMapModule = ProjecturedKernel.IoMapModule
const KeyboardModule = ProjecturedKernel.KeyboardModule
const PlaybackModule = ProjecturedKernel.PlaybackModule
const LlmModule = ProjecturedKernel.LlmModule
const McpModule = ProjecturedKernel.McpModule
# Kernel plan P9 renamed AgentApiModule to AgentModule; the old name is
# still available here for backward compatibility.
const AgentApiModule = ProjecturedKernel.AgentModule
const AgentModule = ProjecturedKernel.AgentModule
const ModifiersModule = ProjecturedKernel.ModifiersModule
const MouseModule = ProjecturedKernel.MouseModule
const NestingProjectionModule = ProjecturedKernel.NestingProjectionModule
# Kernel plan P4 merged OperationApi/Operation/Rerooting into OperationModule;
# the old names live on as aliases so existing domain/opt-in files keep resolving.
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
# Kernel plan P3 merged ReferenceCase/Builder into ReferenceModule; the old
# names stay as aliases so existing domain/opt-in files keep resolving.
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
# Serialization slice (Q2/D4)
const BinarySerializationModule = ProjecturedBase.BinarySerializationModule
const ToolRegistryModule = ProjecturedKernel.ToolRegistryModule
const TypeDispatchingProjectionModule = ProjecturedKernel.TypeDispatchingProjectionModule

# ── Visual aliases (domain plan Q1 — style slice) ─────────────────────────
# Files moved into ProjecturedVisual; the old names live on here so unmoved
# domain files (~30 importers of ColorModule alone) keep resolving.
# Style slice (Q1 sub-commit 1)
const ColorModule = ProjecturedVisual.ColorModule
const FontModule = ProjecturedVisual.FontModule
const GeometryModule = ProjecturedVisual.GeometryModule
const ImageModule = ProjecturedVisual.ImageModule
const StyleStrokeModule = ProjecturedVisual.StyleStrokeModule
const StyleTextModule = ProjecturedVisual.StyleTextModule

# Graphics slice (Q1 sub-commit 2). Note: actual on-disk module names do NOT
# have the "Projection" suffix except where the visual file itself does — the
# aliases below match the module names in each visual file's `module …` line.
const GraphicsModule = ProjecturedVisual.GraphicsModule
const GraphicsCachingModule = ProjecturedVisual.GraphicsCachingModule

# Layout slice (Q1 sub-commit 2)
const LayoutModule = ProjecturedVisual.LayoutModule
const ConstraintSolverModule = ProjecturedVisual.ConstraintSolverModule
const LayoutToGraphicsModule = ProjecturedVisual.LayoutToGraphicsModule
const CollectionToLayoutModule = ProjecturedVisual.CollectionToLayoutModule

# Text slice (Q1 sub-commit 2)
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

# Widget slice (Q1 sub-commit 2)
const WidgetModule = ProjecturedVisual.WidgetModule
const WidgetToGraphicsModule = ProjecturedVisual.WidgetToGraphicsModule
const TextToWidgetModule = ProjecturedVisual.TextToWidgetModule
const ObjectToWidgetModule = ProjecturedVisual.ObjectToWidgetModule
const WidgetHoverTrackingProjectionModule = ProjecturedVisual.WidgetHoverTrackingProjectionModule
const ProjectionConfiguringProjectionModule = ProjecturedVisual.ProjectionConfiguringProjectionModule
const WidgetPopupResolverProjectionModule = ProjecturedVisual.WidgetPopupResolverProjectionModule

# Syntax slice (Q1 sub-commit 2)
const SyntaxModule = ProjecturedVisual.SyntaxModule
const SyntaxToTextModule = ProjecturedVisual.SyntaxToTextModule
const SyntaxToWidgetModule = ProjecturedVisual.SyntaxToWidgetModule
const ObjectToSyntaxModule = ProjecturedVisual.ObjectToSyntaxModule
const CollectionToSyntaxModule = ProjecturedVisual.CollectionToSyntaxModule
const PrimitiveToSyntaxModule = ProjecturedVisual.PrimitiveToSyntaxModule

# Backend slice (Q1 sub-commit 3)
const ConsoleBackendModule = ProjecturedVisual.ConsoleBackendModule
const PdfBackendModule = ProjecturedVisual.PdfBackendModule

# ── Concrete domains, parsers, projections, backends, editors ──────────────
include("clipboard/OsClipboard.jl")
include("document/Document.jl")
# Q1 sub-commit 2: Text/Syntax/Graphics moved to package/visual (text/syntax/
# graphics slices). Style + Image already moved in sub-commit 1. Available
# via the visual aliases at the top of this file.
# ── Q3 slice folders (source slices) ─────────────────────────────────────
# Each source slice groups a document + its parser + its XToSyntax bridge
# in one folder. Includes are ordered so any cross-slice edges (e.g.
# formula→julia, dbcatalog→sql) are satisfied — the plan verifies these
# form an acyclic slice DAG.
# ── Q3 slice-folder includes ─────────────────────────────────────────────
# Each source slice groups a document + its parser + its XToSyntax bridge
# in one folder. Load order: document/parser/toSyntax within each slice;
# slices ordered by the acyclic slice DAG the plan verifies
# (json/xml/yaml/julia/math/markdown/book independent; formula → julia;
# dbcatalog → sql; tabular → json).
include("json/Json.jl")
include("yaml/Yaml.jl")
include("gesturemap/GestureMap.jl")
include("math/Math.jl")
include("julia/Julia.jl")
include("tabular/Tabular.jl")
include("database/Database.jl")
include("dbcatalog/DbCatalog.jl")
include("sql/Sql.jl")
include("xml/Xml.jl")
include("filesystem/FileSystem.jl")
include("document/Workspace.jl")
include("clipboard/Clipboard.jl")
include("versioning/Versioning.jl")
include("graph/Graph.jl")
include("graph/GraphLayout.jl")
include("graph/GraphLayoutEngine.jl")
include("book/Book.jl")
include("markdown/Markdown.jl")
include("document/Evaluator.jl")
include("formula/Formula.jl")
include("document/Conversation.jl")
include("julia/JuliaParser.jl")
include("json/JsonParser.jl")
include("yaml/YamlParser.jl")
include("xml/XmlParser.jl")
include("markdown/MarkdownParser.jl")
include("sql/SqlParser.jl")
include("document/Workbench.jl")
include("tooltip/Tooltip.jl")
include("inspector/ReferenceInspector.jl")
include("dragging/Dragging.jl")
include("tooltip/TooltipDecorator.jl")
include("gesturemap/GestureHelpDecorator.jl")
include("projection/primitive/ScreenToScreen.jl")
include("clipboard/ClipboardToAny.jl")
include("versioning/VersioningToAny.jl")
include("dragging/DraggingProjection.jl")
include("projection/ProjectionTemplate.jl")
include("json/JsonToSyntax.jl")
include("yaml/YamlToSyntax.jl")
include("gesturemap/GestureMapToSyntax.jl")
include("xml/XmlToSyntax.jl")
include("markdown/MarkdownToSyntax.jl")
include("filesystem/FileSystemToSyntax.jl")
include("filesystem/FileSystemToWidget.jl")
include("projection/primitive/WorkspaceToFileSystem.jl")
include("graph/GraphToGraphLayout.jl")
include("graph/GraphLayoutToGraphics.jl")
include("book/BookToSyntax.jl")
include("inspector/ReferenceInspectorToText.jl")
include("inspector/HoverProbe.jl")
include("math/MathToSyntax.jl")
# DocumentInsertionToSyntax before JuliaToSyntax/SqlToSyntax: it defines the
# per-domain insertion→syntax leaves (JuliaInsertionToSyntaxLeaf, …) those
# projections register, and it depends on none of them.
include("projection/primitive/DocumentInsertionToSyntax.jl")
include("julia/JuliaToSyntax.jl")
include("formula/FormulaToSyntax.jl")
include("sql/SqlToSyntax.jl")
include("dbcatalog/DbCatalogToSql.jl")
include("dbcatalog/DbCatalogToSyntax.jl")
include("tabular/CellTableToTable.jl")
include("projection/primitive/ConversationToSyntax.jl")
include("projection/primitive/ConversationToWidget.jl")
include("projection/primitive/WorkbenchToWidget.jl")
include("projection/primitive/NaturalProjection.jl")
include("serializer/NaturalFormat.jl")
include("serializer/DocumentFile.jl")
include("projection/compound/HigherOrder.jl")
include("projection/compound/Generic.jl")
include("database/DatabaseAdapters.jl")
include("editor/ConversationEditor.jl")
include("editor/WorkbenchAssistant.jl")
include("editor/WorkbenchFile.jl")

end # module ProjecturedDomain
