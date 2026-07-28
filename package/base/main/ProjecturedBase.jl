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
  `CellTable` / `ListNode`) and their collection-shaped projections
  (`SortingProjection`, `FilteringProjection`).
- **`primitive/`** — the scalar documents (`Primitive*` + the two
  `Replace*RangeOperation`s) and `ReaderDefaults`, their default-`read_intent` half.
- **`projection/`** — the domain-free projection *algebra*: `generic/` +
  `higherorder/` combinators, `compound/`, plus `Searching` / `Copying`.
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
# higher-order projections import `collect_gesture_bindings` from it.
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

# vocabulary — the documents every slice/domain reuses
include("collection/Collection.jl")   # CellVector/CellMatrix/CellTable/ListNode
include("primitive/Primitive.jl")     # Primitive* + Replace*RangeOperation
include("domain/DocumentCore.jl")     # DocumentBase/Nothing/Insertion/Reference

# reflection/ — a bounded shadow of a large/live object. DocumentReflection
# consumes BoundedSync's UnsyncedDocument marker + SyncPolicy/DepthPolicy, which
# implement the kernel's policy-parameterised sync_document! seam.
include("reflection/BoundedSync.jl")
include("reflection/DocumentReflection.jl")

# domain/ — the @domain macro (per-domain root/Nothing/Insertion kit + Insert
# gesture + insertion traits) and the reflection-based insertion completion.
include("domain/Domain.jl")

# dragging/ — the DraggingState reorder wrapper document; its projection is below.
include("dragging/Dragging.jl")
# versioning/ — the VersionedObject overlay document; its projection is below.
include("versioning/Versioning.jl")

# projection algebra — the domain-free generic + higher-order combinators. The
# only intra-order edge is Identity → Reversing; Sorting imports IdentityProjection
# and the compound aggregates import Recursive/ReferenceDispatching/Nesting.
include("projection/generic/Identity.jl")
include("projection/generic/Reversing.jl")
include("projection/generic/Constant.jl")
include("projection/higherorder/Chaining.jl")
include("projection/higherorder/TypeDispatching.jl")
include("projection/higherorder/Recursive.jl")
include("projection/higherorder/Switching.jl")
include("projection/higherorder/PredicateDispatching.jl")
include("projection/higherorder/ReferenceDispatching.jl")
include("projection/higherorder/Nesting.jl")
include("projection/higherorder/WindowInputUnwrapping.jl")
include("projection/generic/Focusing.jl")

# collection-shaped projections (dispatch on CellVector)
include("collection/Sorting.jl")
include("collection/Filtering.jl")
# Searching + Copying consume any input → generic algebra
include("projection/Searching.jl")
include("projection/Copying.jl")
# ReaderDefaults — the Primitive-op branches of the default read_intent
include("primitive/ReaderDefaults.jl")
# dragging/ projection — the press→drag→drop reader over DraggingState
include("dragging/DraggingProjection.jl")
# versioning/ projection — version-elimination (School-A reader over the value child)
include("versioning/VersioningToAny.jl")
# compound aggregates
include("projection/compound/HigherOrderCompound.jl")
include("projection/compound/GenericCompound.jl")

# persistence — exact/lossless binary via Julia's Serialization stdlib; a Cell
# serialises as just its value, pruning the reactive graph at every cell boundary.
include("serialization/BinarySerialization.jl")

end # module ProjecturedBase
