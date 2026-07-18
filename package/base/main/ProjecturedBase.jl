"""
    ProjecturedBase

The domain-independent vocabulary and frameworks — layered between the
kernel engine and the concrete domain slices (kernel ← base ← domain ←
umbrella; opt-in packages still depend on domain).

Two layers today:

- **`document/`** — the engine's concrete document types: Collection
  (CellVector / CellMatrix / CellTable / ListNode) and Primitive
  (Bool/Number/String/Insertion). Registers the CellVector method for
  `child_reference_steps` on the kernel's `OperationModule`, and the
  reroot methods for `ReplaceStringRangeOperation` / `ReplaceNumberRangeOperation`.
- **`projection/`** — the document-shaped generic projections
  (`SortingProjection`, `FilteringProjection`, `SearchingProjection`,
  `CopyingProjection`) plus the reader defaults (`ReaderDefaultsModule`) —
  the Primitive-op branches of the default `read_intent`. Multiple
  dispatch: `read_intent(::Projection, iomap, ::ReplaceStringRangeOperation)`
  is more specific than the kernel's catch-all, so registering these
  methods here is all this seam requires.

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

# ── Backend selection ────────────────────────────────────────────────────
# Reflection-based `default_backend`: pick a loaded Backend subtype by type
# name. Needs InteractiveUtils.subtypes (a base dependency, absent in kernel).
include("backend/DefaultBackend.jl")

# ── Layer 1 — document (concrete engine documents) ────────────────────────
# Collection and Primitive: the CellVector/CellMatrix/CellTable/ListNode and
# Bool/Number/String/Insertion document types. Each file registers its own
# seam methods onto the kernel's OperationModule generics.
include("document/Collection.jl")
include("document/Primitive.jl")
include("document/DocumentCore.jl")
# Domain — the @domain macro (per-domain root/Nothing/Insertion kit + Insert
# gesture + insertion traits) and the reflection-based completion machinery
# (insertion_candidates / insertion_names / complete_insertion /
# resolve_insertion). Sits right above DocumentCore: DocumentNothing /
# DocumentInsertion implement the same traits.
include("document/Domain.jl")
# DraggingState — a transparent drag-and-drop reorder wrapper; the gesture
# interpretation lives in the projection layer's DraggingProjection. Moved
# down from the domain `dragging/` slice (kernel-only document contracts).
include("document/Dragging.jl")
# ScreenDocument lives in package/visual (screen slice) — it travels
# together with WindowManagingProjection, and both belong in visual per
# the architecture rules (window things are visual, only the Display
# device stays in the kernel).

# ── Layer 2 — projection (domain-independent projection algebra + generics) ──
# The projection *machinery* (interface, IO maps, @projection macro, the
# projection-template engine, gesture bindings) stays in the kernel; every
# concrete projection is domain-independent framework and lives here.
#
# The generic + higher-order projections lead the layer: they depend only on
# the kernel projection interface, and the files below (Sorting imports
# IdentityProjection; ReaderDefaults + the compound aggregates import
# Recursive/ReferenceDispatching/Nesting) depend on them. Among the twelve the
# only intra-order edge is Identity → Reversing.
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

# ── The document-shaped generic projections + the reader defaults ──────────
# Each file is currently its own module; a later cosmetic pass may consolidate
# them into a single BaseProjectionModule aggregator with fragments.
include("projection/Sorting.jl")
include("projection/Filtering.jl")
include("projection/Searching.jl")
include("projection/Copying.jl")
# WindowManagingProjection lives in package/visual (screen slice), alongside
# ScreenDocument.
include("projection/ReaderDefaults.jl")
# DraggingProjection — a domain-independent higher-order projection adding
# drag-and-drop reordering to a CellVector-backed content. Moved down from the
# domain `dragging/` slice; imports only kernel + base document types.
include("projection/DraggingProjection.jl")
# The two compound projection aggregates import only kernel + base
# combinators, no domain content.
include("projection/HigherOrderCompound.jl")
include("projection/GenericCompound.jl")

# ── Layer 3 — serialization (domain-independent persistence) ─────────────
# BinarySerialization is exact/lossless persistence via Julia's Serialization
# stdlib, with a single customization: a Cell serializes as just its value,
# pruning the reactive graph at every cell boundary. Kernel-only imports.
include("serialization/BinarySerialization.jl")

end # module ProjecturedBase
