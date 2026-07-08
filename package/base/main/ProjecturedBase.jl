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
const OperationModule = ProjecturedKernel.OperationModule
const OperationApiModule = ProjecturedKernel.OperationModule
const OperationRerootingModule = ProjecturedKernel.OperationModule
const IntentModule = ProjecturedKernel.IntentModule
const MouseModule = ProjecturedKernel.MouseModule
const ModifiersModule = ProjecturedKernel.ModifiersModule
const IoMapModule = ProjecturedKernel.IoMapModule
const IoMapApiModule = ProjecturedKernel.IoMapApiModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const IdentityProjectionModule = ProjecturedKernel.IdentityProjectionModule
const GestureModule = ProjecturedKernel.GestureModule
const BackendModule = ProjecturedKernel.BackendModule
# Kernel-side seams that base implements methods on.
const ChildrenContainerModule = ProjecturedKernel.ChildrenContainerModule
const ProjectionTemplateModule = ProjecturedKernel.ProjectionTemplateModule
const RecursiveProjectionModule = ProjecturedKernel.RecursiveProjectionModule
const ReferenceDispatchingProjectionModule = ProjecturedKernel.ReferenceDispatchingProjectionModule
const NestingProjectionModule = ProjecturedKernel.NestingProjectionModule
const ReferenceCaseModule = ProjecturedKernel.ReferenceModule

# ── Layer 1 — document (concrete engine documents) ────────────────────────
# Collection and Primitive: the CellVector/CellMatrix/CellTable/ListNode and
# Bool/Number/String/Insertion document types. Each file registers its own
# seam methods onto the kernel's OperationModule generics.
include("document/Collection.jl")
include("document/Primitive.jl")
include("document/DocumentCore.jl")
# DomainSupport — the @domain macro (per-domain root/Nothing/Insertion kit +
# Insert gesture + insertion traits) and the reflection-based completion
# machinery (insertion_candidates / insertion_names / complete_insertion /
# resolve_insertion). Sits right above DocumentCore: DocumentNothing /
# DocumentInsertion implement the same traits.
include("document/DomainSupport.jl")
# DraggingState — a transparent drag-and-drop reorder wrapper; the gesture
# interpretation lives in the projection layer's DraggingProjection. Moved
# down from the domain `dragging/` slice (kernel-only document contracts).
include("document/Dragging.jl")
# ScreenDocument lives in package/visual (screen slice) — it travels
# together with WindowManagingProjection, and both belong in visual per
# the architecture rules (window things are visual, only the Screen
# device stays in the kernel).

# ── Layer 2 — projection (document-shaped generic projections) ────────────
# The document-shaped projections + the reader defaults. Each file is
# currently its own module; a later cosmetic pass may consolidate them into
# a single BaseProjectionModule aggregator with fragments.
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
