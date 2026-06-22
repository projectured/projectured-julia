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
submodule of `ProjecturedDomain`, `..ReactiveModule` resolves through the
`const ReactiveModule = ProjecturedKernel.ReactiveModule` binding below.
"""
module ProjecturedDomain

using ProjecturedKernel

# ── Kernel submodule aliases (make relative ..XxxModule refs resolve into the
#    kernel; see the module docstring) ──────────────────────────────────────
const BackendModule = ProjecturedKernel.BackendModule
const CollectionModule = ProjecturedKernel.CollectionModule
const CopyingProjectionModule = ProjecturedKernel.CopyingProjectionModule
const DeviceModule = ProjecturedKernel.DeviceModule
const DocumentApiModule = ProjecturedKernel.DocumentApiModule
const DocumentCopyModule = ProjecturedKernel.DocumentCopyModule
const DocumentModule = ProjecturedKernel.DocumentModule
const EventCaseModule = ProjecturedKernel.EventCaseModule
const IoMapApiModule = ProjecturedKernel.IoMapApiModule
const IoMapModule = ProjecturedKernel.IoMapModule
const KeyboardModule = ProjecturedKernel.KeyboardModule
const LlmModule = ProjecturedKernel.LlmModule
const McpModule = ProjecturedKernel.McpModule
const ModifiersModule = ProjecturedKernel.ModifiersModule
const MouseModule = ProjecturedKernel.MouseModule
const NestingProjectionModule = ProjecturedKernel.NestingProjectionModule
const OperationApiModule = ProjecturedKernel.OperationApiModule
const OperationModule = ProjecturedKernel.OperationModule
const OperationRerootingModule = ProjecturedKernel.OperationRerootingModule
const PredicateDispatchingModule = ProjecturedKernel.PredicateDispatchingModule
const PreservingProjectionModule = ProjecturedKernel.PreservingProjectionModule
const PrimitiveModule = ProjecturedKernel.PrimitiveModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const ReactiveModule = ProjecturedKernel.ReactiveModule
const RecursiveProjectionModule = ProjecturedKernel.RecursiveProjectionModule
const ReferenceBuilderModule = ProjecturedKernel.ReferenceBuilderModule
const ReferenceCaseModule = ProjecturedKernel.ReferenceCaseModule
const ReferenceDispatchingModule = ProjecturedKernel.ReferenceDispatchingModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ScreenDocumentModule = ProjecturedKernel.ScreenDocumentModule
const ScreenModule = ProjecturedKernel.ScreenModule
const SequentialProjectionModule = ProjecturedKernel.SequentialProjectionModule
const SortingProjectionModule = ProjecturedKernel.SortingProjectionModule
const ToolRegistryModule = ProjecturedKernel.ToolRegistryModule
const TypeDispatchingModule = ProjecturedKernel.TypeDispatchingModule

# ── Concrete domains, parsers, projections, backends, editors ──────────────
include("document/Document.jl")
include("document/Font.jl")
include("document/Color.jl")
include("document/StyleText.jl")
include("document/StyleStroke.jl")
include("document/Geometry.jl")
include("document/Text.jl")
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
include("document/Versioning.jl")
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
include("parser/JuliaParser.jl")
include("parser/JsonParser.jl")
include("parser/XmlParser.jl")
include("parser/SqlParser.jl")
include("document/Workbench.jl")
include("document/Image.jl")
include("document/Tooltip.jl")
include("document/Dragging.jl")
include("projection/higherorder/TooltipDecorator.jl")
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
include("projection/primitive/XmlToSyntax.jl")
include("projection/primitive/FileSystemToSyntax.jl")
include("projection/primitive/WorkspaceToFileSystem.jl")
include("projection/primitive/TextToString.jl")
include("projection/primitive/ObjectToSyntax.jl")
include("projection/primitive/ObjectToJson.jl")
include("projection/primitive/LayoutToGraphics.jl")
include("projection/primitive/WidgetToGraphics.jl")
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
include("projection/primitive/MathToSyntax.jl")
include("projection/primitive/JuliaToSyntax.jl")
include("projection/primitive/FormulaToSyntax.jl")
include("projection/primitive/DocumentInsertionToSyntax.jl")
include("projection/primitive/SqlToSyntax.jl")
include("projection/primitive/CollectionToSyntax.jl")
include("projection/primitive/ConversationToSyntax.jl")
include("projection/primitive/ConversationToWidget.jl")
include("projection/primitive/WorkbenchToWidget.jl")
include("projection/compound/HigherOrder.jl")
include("projection/compound/Generic.jl")
include("backend/Console.jl")
include("backend/Pdf.jl")
include("external/Database.jl")
include("projection/primitive/CellTableToTable.jl")
include("projection/primitive/DbCatalogToJson.jl")
include("projection/primitive/DbCatalogToSql.jl")
include("projection/primitive/DbCatalogToSyntax.jl")
include("editor/ConversationEditor.jl")
include("editor/WorkbenchAssistant.jl")

end # module ProjecturedDomain
