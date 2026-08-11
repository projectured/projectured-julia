"""
    ProjecturedBase

The domain-independent vocabulary and frameworks — layered between the
kernel engine and the concrete domain slices (kernel ← base ← domain ←
umbrella; opt-in packages still depend on domain).

base is an **acyclic DAG of concept folders** (sliced like the `domain`
package), not ordered layers. Each folder is one cohesive concept and holds
whatever kinds it needs — its documents *and* its projections *and* its
operations:

- **`domain/`** — what a document domain *is*: `DocumentCore` (the empty /
  insertion / reference documents) and the `@domain` macro + insertion completion.
- **`collection/`** — the reactive containers (`CellVector` / `CellMatrix` /
  `CellTable` / `ListNode`).
- **`primitive/`** — the scalar documents (`Primitive*` + the two
  `Replace*RangeOperation`s).
- **`projection/`** — the domain-free projection *algebra*: `generic/` +
  `higherorder/` combinators, `compound/`, plus `Searching` / `Copying`, the
  two collection-shaped projections (`Sorting`, `Filtering`) and
  `ReaderDefaults`, the IoMap-typed `read_intent` methods.
- **`dragging/`, `reflection/`** — optional feature slices, each a document
  paired with its projection (`DraggingState` + `DraggingProjection`; the
  `UnsyncedDocument` marker + `DocumentReflection`).
- **`serialization/`** — exact/lossless binary persistence.

Kernel submodules are aliased below so files under this package's source
folders can keep their relative `..XxxModule` references unchanged — inside
a submodule of `ProjecturedBase`, `..CellModule` resolves through the
`const CellModule = ProjecturedKernel.CellModule` binding.
"""
module ProjecturedBase

using ProjecturedKernel
using ProjecturedCollection
using ProjecturedPrimitive
using ProjecturedDomain
using ProjecturedSerialization
using ProjecturedProjection

# ── Aliases of the packages this one was spliced into ─────────────────────
# Each concept folder becomes its own package (see
# plan/pending/splice-base-and-visual-packages.md). While the splice runs,
# ProjecturedBase re-aliases what has already left, so every consumer keeps
# resolving `..XxxModule`.
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
# NOTE: the concrete generic + higher-order projections (Identity, Reversing,
# Constant, Focusing, Chaining, TypeDispatching, Recursive, Switching,
# PredicateDispatching, ReferenceDispatching, Nesting, WindowInputUnwrapping) are
# now *defined* in this package's projection layer below — they are no longer
# kernel submodules, so they must NOT be aliased here.

# ── backend/ preamble ─────────────────────────────────────────────────────
# Reflection-based `default_backend`: pick a loaded Backend subtype by type
# name. Needs InteractiveUtils.subtypes (a base dependency, absent in kernel).
include("backend/DefaultBackend.jl")

# ── Concept folders, in topological include order ──────────────────────────
# base is an acyclic DAG of concept folders (sliced like `domain`), not ordered
# layers: vocabulary → projection algebra → feature slices → persistence, each
# module included after the modules it imports.

# reflection/ — a bounded shadow of a large/live object. DocumentReflection
# consumes BoundedSync's UnsyncedDocument marker + SyncPolicy/DepthPolicy, which
# implement the kernel's policy-parameterised sync_document! seam.
include("reflection/BoundedSync.jl")
include("reflection/DocumentReflection.jl")

# dragging/ — the DraggingState reorder wrapper document; its projection is below.
include("dragging/Dragging.jl")
# versioning/ — the VersionedObject overlay document; its projection is below.
include("versioning/Versioning.jl")

# dragging/ projection — the press→drag→drop reader over DraggingState
include("dragging/DraggingProjection.jl")
# versioning/ projection — version-elimination (School-A reader over the value child)
include("versioning/VersioningToAny.jl")

end # module ProjecturedBase
