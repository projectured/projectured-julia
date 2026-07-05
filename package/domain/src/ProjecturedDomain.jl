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
const ScreenDocumentModule = ProjecturedBase.ScreenDocumentModule
const ScreenDeviceModule = ProjecturedKernel.ScreenDeviceModule
const ChainingProjectionModule = ProjecturedKernel.ChainingProjectionModule
const SortingProjectionModule = ProjecturedBase.SortingProjectionModule
const FilteringProjectionModule = ProjecturedBase.FilteringProjectionModule
const SearchingProjectionModule = ProjecturedBase.SearchingProjectionModule
const WindowManagingProjectionModule = ProjecturedBase.WindowManagingProjectionModule
const ReaderDefaultsModule = ProjecturedBase.ReaderDefaultsModule
const ToolRegistryModule = ProjecturedKernel.ToolRegistryModule
const TypeDispatchingProjectionModule = ProjecturedKernel.TypeDispatchingProjectionModule

# ── Visual aliases (domain plan Q1 — style slice) ─────────────────────────
# Files moved into ProjecturedVisual; the old names live on here so unmoved
# domain files (~30 importers of ColorModule alone) keep resolving.
const ColorModule = ProjecturedVisual.ColorModule
const FontModule = ProjecturedVisual.FontModule
const GeometryModule = ProjecturedVisual.GeometryModule
const ImageModule = ProjecturedVisual.ImageModule
const StyleStrokeModule = ProjecturedVisual.StyleStrokeModule
const StyleTextModule = ProjecturedVisual.StyleTextModule

# ── Concrete domains, parsers, projections, backends, editors ──────────────
include("common/OsClipboard.jl")
include("document/Document.jl")
# Font/Color/StyleText/StyleStroke/Geometry moved to package/visual at Q1
# (style slice); available via the visual aliases at the top of this file.
include("document/Text.jl")
include("document/Syntax.jl")
include("document/Graphics.jl")
include("document/Json.jl")
include("document/Yaml.jl")
include("document/GestureMap.jl")
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
include("document/Versioning.jl")
include("document/Widget.jl")
include("document/ConstraintSolver.jl")
include("document/Layout.jl")
include("document/Graph.jl")
include("document/GraphLayout.jl")
include("layout/GraphLayoutEngine.jl")
include("document/Component.jl")
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
include("projection/generic/ObjectToWidget.jl")
include("projection/primitive/ClipboardToAny.jl")
include("projection/primitive/VersioningToAny.jl")
include("projection/higherorder/ProjectionConfiguring.jl")
include("projection/higherorder/Dragging.jl")
include("projection/primitive/SyntaxToText.jl")
include("projection/primitive/TextToGraphics.jl")
include("projection/primitive/GraphicsCaching.jl")
include("projection/ProjectionTemplate.jl")
include("projection/primitive/JsonToSyntax.jl")
include("projection/primitive/YamlToSyntax.jl")
include("projection/primitive/GestureMapToSyntax.jl")
include("projection/primitive/XmlToSyntax.jl")
include("projection/primitive/MarkdownToSyntax.jl")
include("projection/primitive/FileSystemToSyntax.jl")
include("projection/primitive/FileSystemToWidget.jl")
include("projection/primitive/WorkspaceToFileSystem.jl")
include("projection/primitive/TextToString.jl")
include("projection/primitive/ObjectToSyntax.jl")
include("projection/primitive/LayoutToGraphics.jl")
include("projection/primitive/WidgetToGraphics.jl")
include("projection/higherorder/WidgetHoverTracking.jl")
include("projection/higherorder/WidgetPopupResolver.jl")
include("projection/primitive/TextToWidget.jl")
include("projection/primitive/GraphToGraphLayout.jl")
include("projection/primitive/GraphLayoutToGraphics.jl")
include("projection/primitive/SyntaxToWidget.jl")
include("projection/primitive/BookToSyntax.jl")
include("projection/primitive/LineNumbering.jl")
include("projection/primitive/WordWrapping.jl")
include("projection/primitive/TextFirstLine.jl")
include("projection/primitive/TextFiltering.jl")
include("projection/primitive/TextHighlighting.jl")
include("projection/primitive/SelectionInverting.jl")
include("projection/primitive/PrimitiveToSyntax.jl")
include("projection/primitive/PrimitiveToText.jl")
include("projection/primitive/ReferenceToText.jl")
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
include("projection/primitive/CollectionToSyntax.jl")
include("projection/primitive/ConversationToSyntax.jl")
include("projection/primitive/ConversationToWidget.jl")
include("projection/primitive/WorkbenchToWidget.jl")
include("projection/primitive/CollectionToLayout.jl")
include("projection/primitive/NaturalProjection.jl")
include("serializer/BinarySerialization.jl")
include("serializer/NaturalFormat.jl")
include("serializer/DocumentFile.jl")
include("projection/compound/HigherOrder.jl")
include("projection/compound/Generic.jl")
include("backend/Console.jl")
include("backend/Pdf.jl")
include("external/Database.jl")
include("projection/primitive/CellTableToTable.jl")
include("projection/primitive/DbCatalogToSql.jl")
include("projection/primitive/DbCatalogToSyntax.jl")
include("editor/ConversationEditor.jl")
include("editor/WorkbenchAssistant.jl")
include("editor/WorkbenchFile.jl")

end # module ProjecturedDomain
