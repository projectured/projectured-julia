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
include("common/OsClipboard.jl")
include("document/Document.jl")
# Q1 sub-commit 2: Text/Syntax/Graphics moved to package/visual (text/syntax/
# graphics slices). Style + Image already moved in sub-commit 1. Available
# via the visual aliases at the top of this file.
include("document/Json.jl")
include("document/Yaml.jl")
include("document/GestureMap.jl")
include("document/Math.jl")
include("document/Julia.jl")
include("document/Tabular.jl")
include("document/Database.jl")
include("document/DbCatalog.jl")
# Q3: DatabaseInstance.jl deleted — orphan (effectively only used by
# Component, itself an orphan; verified in Q0 D3 finding).
include("document/Sql.jl")
include("document/Xml.jl")
include("document/FileSystem.jl")
include("document/Workspace.jl")
include("document/Clipboard.jl")
include("document/Versioning.jl")
# Q1 sub-commit 2: Widget/ConstraintSolver/Layout moved to package/visual
# (widget + layout slices).
include("document/Graph.jl")
include("document/GraphLayout.jl")
include("layout/GraphLayoutEngine.jl")
# Q3: Component.jl deleted — true orphan (no importers anywhere in the
# repo; verified in Q0 D3 finding).
include("document/Book.jl")
include("document/Markdown.jl")
include("document/Evaluator.jl")
include("document/Formula.jl")
include("document/Conversation.jl")
include("parser/JuliaParser.jl")
include("parser/JsonParser.jl")
include("parser/YamlParser.jl")
include("parser/XmlParser.jl")
include("parser/MarkdownParser.jl")
include("parser/SqlParser.jl")
include("document/Workbench.jl")
# Image moved to package/visual at Q1 (style slice).
include("document/Tooltip.jl")
include("document/ReferenceInspector.jl")
include("document/Dragging.jl")
include("projection/higherorder/TooltipDecorator.jl")
include("projection/higherorder/GestureHelpDecorator.jl")
include("projection/primitive/ScreenToScreen.jl")
# Q1 sub-commit 2: ObjectToWidget moved to visual/widget/.
include("projection/primitive/ClipboardToAny.jl")
include("projection/primitive/VersioningToAny.jl")
# Q1 sub-commit 2: ProjectionConfiguring moved to visual/widget/.
include("projection/higherorder/Dragging.jl")
# Q1 sub-commit 2: SyntaxToText, TextToGraphics, GraphicsCaching moved to
# visual (syntax, text, graphics slices).
include("projection/ProjectionTemplate.jl")
include("projection/primitive/JsonToSyntax.jl")
include("projection/primitive/YamlToSyntax.jl")
include("projection/primitive/GestureMapToSyntax.jl")
include("projection/primitive/XmlToSyntax.jl")
include("projection/primitive/MarkdownToSyntax.jl")
include("projection/primitive/FileSystemToSyntax.jl")
include("projection/primitive/FileSystemToWidget.jl")
include("projection/primitive/WorkspaceToFileSystem.jl")
# Q1 sub-commit 2: TextToString, ObjectToSyntax, LayoutToGraphics,
# WidgetToGraphics moved to visual. WidgetHoverTracking, WidgetPopupResolver,
# TextToWidget likewise.
include("projection/primitive/GraphToGraphLayout.jl")
include("projection/primitive/GraphLayoutToGraphics.jl")
# Q1 sub-commit 2: SyntaxToWidget moved to visual/syntax/.
include("projection/primitive/BookToSyntax.jl")
# Q1 sub-commit 2: LineNumbering, WordWrapping, TextFirstLine, TextFiltering,
# TextHighlighting, SelectionInverting, PrimitiveToSyntax, PrimitiveToText,
# ReferenceToText all moved to visual.
include("projection/primitive/ReferenceInspectorToText.jl")
include("projection/higherorder/HoverProbe.jl")
include("projection/primitive/MathToSyntax.jl")
# DocumentInsertionToSyntax before JuliaToSyntax/SqlToSyntax: it defines the
# per-domain insertion→syntax leaves (JuliaInsertionToSyntaxLeaf, …) those
# projections register, and it depends on none of them.
include("projection/primitive/DocumentInsertionToSyntax.jl")
include("projection/primitive/JuliaToSyntax.jl")
include("projection/primitive/FormulaToSyntax.jl")
include("projection/primitive/SqlToSyntax.jl")
# Q1 sub-commit 2: CollectionToSyntax moved to visual/syntax/.
include("projection/primitive/ConversationToSyntax.jl")
include("projection/primitive/ConversationToWidget.jl")
include("projection/primitive/WorkbenchToWidget.jl")
# Q1 sub-commit 2: CollectionToLayout moved to package/visual (layout slice).
include("projection/primitive/NaturalProjection.jl")
# Q2 (D4): BinarySerialization moved to package/base (base/serialization/).
# NaturalFormat + DocumentFile remain here until their framework/registration
# split lands (D4 refactor); they keep their current include position.
include("serializer/NaturalFormat.jl")
include("serializer/DocumentFile.jl")
include("projection/compound/HigherOrder.jl")
include("projection/compound/Generic.jl")
# Q1 sub-commit 3: Console + Pdf moved to package/visual (backend slice).
include("external/Database.jl")
include("projection/primitive/CellTableToTable.jl")
include("projection/primitive/DbCatalogToSql.jl")
include("projection/primitive/DbCatalogToSyntax.jl")
include("editor/ConversationEditor.jl")
include("editor/WorkbenchAssistant.jl")
include("editor/WorkbenchFile.jl")

end # module ProjecturedDomain
