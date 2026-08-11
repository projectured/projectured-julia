"""
    ProjecturedBase

The domain-independent vocabulary and frameworks. The package owns no source
file any more: each of its concept folders is now a package of its own, and
this module is a transitional aggregator that binds them under the names its
consumers still use. It disappears at step 5 of
[the splice plan](plan/pending/splice-base-and-visual-packages.md).

The eight packages it aggregates:

- `ProjecturedCollection` — the reactive containers.
- `ProjecturedPrimitive` — the scalar documents.
- `ProjecturedDomain` — what a document domain is.
- `ProjecturedProjection` — the domain-free projection algebra.
- `ProjecturedReflection` — a bounded shadow of a live object.
- `ProjecturedDragging` — the reorder wrapper and its reader.
- `ProjecturedVersioning` — the version overlay and its projection.
- `ProjecturedSerialization` — persistence.

The kernel aliases below stay until the consumers name the kernel directly.
"""
module ProjecturedBase

using ProjecturedKernel
using ProjecturedCollection
using ProjecturedPrimitive
using ProjecturedDomain
using ProjecturedSerialization
using ProjecturedProjection
using ProjecturedReflection
using ProjecturedDragging
using ProjecturedVersioning

# Every concept folder is now a package of its own. ProjecturedBase re-aliases
# what left, so every consumer keeps resolving `..XxxModule` until step 4
# rewires it.
# The aliases of the packages this one was spliced into follow.
const CollectionModule = ProjecturedCollection.CollectionModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const DocumentCoreModule = ProjecturedDomain.DocumentCoreModule
const DomainModule = ProjecturedDomain.DomainModule
const BinarySerializationModule = ProjecturedSerialization.BinarySerializationModule
const FileProjectModule = ProjecturedSerialization.FileProjectModule
const TextFileModule = ProjecturedSerialization.TextFileModule
const CopyingProjectionModule = ProjecturedProjection.CopyingProjectionModule
const FilteringProjectionModule = ProjecturedProjection.FilteringProjectionModule
const ReaderDefaultsModule = ProjecturedProjection.ReaderDefaultsModule
const SearchingProjectionModule = ProjecturedProjection.SearchingProjectionModule
const SortingProjectionModule = ProjecturedProjection.SortingProjectionModule
const GenericCompoundModule = ProjecturedProjection.GenericCompoundModule
const HigherOrderCompoundModule = ProjecturedProjection.HigherOrderCompoundModule
const ConstantProjectionModule = ProjecturedProjection.ConstantProjectionModule
const FocusingProjectionModule = ProjecturedProjection.FocusingProjectionModule
const IdentityProjectionModule = ProjecturedProjection.IdentityProjectionModule
const ReversingProjectionModule = ProjecturedProjection.ReversingProjectionModule
const ChainingProjectionModule = ProjecturedProjection.ChainingProjectionModule
const NestingProjectionModule = ProjecturedProjection.NestingProjectionModule
const PredicateDispatchingProjectionModule = ProjecturedProjection.PredicateDispatchingProjectionModule
const RecursiveProjectionModule = ProjecturedProjection.RecursiveProjectionModule
const ReferenceDispatchingProjectionModule = ProjecturedProjection.ReferenceDispatchingProjectionModule
const SwitchingProjectionModule = ProjecturedProjection.SwitchingProjectionModule
const TypeDispatchingProjectionModule = ProjecturedProjection.TypeDispatchingProjectionModule
const WindowInputUnwrappingProjectionModule = ProjecturedProjection.WindowInputUnwrappingProjectionModule
const BoundedSyncModule = ProjecturedReflection.BoundedSyncModule
const DocumentReflectionModule = ProjecturedReflection.DocumentReflectionModule
const DraggingDocumentModule = ProjecturedDragging.DraggingDocumentModule
const DraggingProjectionModule = ProjecturedDragging.DraggingProjectionModule
const VersioningModule = ProjecturedVersioning.VersioningModule
const VersioningToAnyProjectionModule = ProjecturedVersioning.VersioningToAnyProjectionModule

# ── Kernel submodule aliases ──────────────────────────────────────────────
# One entry per kernel submodule this package's files touch. The order
# doesn't matter here (aliases resolve lazily); grouped by kernel layer for
# readability.
const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const SelectionModule = ProjecturedKernel.SelectionModule
const OperationModule = ProjecturedKernel.OperationModule
const OperationApiModule = ProjecturedKernel.OperationModule
const OperationRerootingModule = ProjecturedKernel.OperationModule
const IntentModule = ProjecturedKernel.IntentModule
const EventModule = ProjecturedKernel.EventModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const IoMapModule = ProjecturedKernel.IoMapModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const ProjectionReferenceStepModule = ProjecturedKernel.ProjectionReferenceStepModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const BackendModule = ProjecturedKernel.BackendModule
# Kernel-side seams that base implements methods on.
const ChildrenContainerModule = ProjecturedKernel.ChildrenContainerModule
const ProjectionTemplateModule = ProjecturedKernel.ProjectionTemplateModule
# GestureBindings stays in the kernel projection layer; the moved generic /
# higher-order projections import the projection gesture seam from it.
const ProjectionGestureBindingsModule = ProjecturedKernel.ProjectionGestureBindingsModule
const ReferenceCaseModule = ProjecturedKernel.ReferenceModule

end # module ProjecturedBase
