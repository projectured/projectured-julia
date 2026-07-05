"""
    ProjecturedBase

The domain-independent vocabulary and frameworks — layered between the
kernel engine and the concrete domain slices (kernel ← base ← domain ←
umbrella; opt-in packages still depend on domain).

Two layers today:

- **`document/`** — the engine's concrete document types: Collection
  (CellVector / CellMatrix / CellTable / ListNode), Primitive
  (Bool/Number/String/Insertion), ScreenDocument (multi-window screen model
  + window events/ops). Registers the R1 CellVector method for
  `child_reference_steps` on the kernel's `OperationModule`, and the R2
  reroot methods for `ReplaceStringRangeOperation` / `ReplaceNumberRangeOperation`.
- **`projection/`** — the document-shaped generic projections
  (`SortingProjection`, `FilteringProjection`, `SearchingProjection`,
  `CopyingProjection`, `WindowManagingProjection`) plus the R6 reader
  defaults (`ReaderDefaultsModule`) — the Primitive-op branches of the
  default `read_intent` that split out of `kernel/common/Projection.jl` at
  P8. Multiple dispatch: `read_intent(::Projection, iomap, ::ReplaceStringRangeOperation)`
  is more specific than the kernel's catch-all, so registering these
  methods here is all the R6 seam requires.

Kernel submodules are aliased below so files under this package's source
folders can keep their relative `..XxxModule` references unchanged — inside
a submodule of `ProjecturedBase`, `..CellModule` resolves through the
`const CellModule = ProjecturedKernel.CellModule` binding.

Coming at Q2 (D1/D4 seams, from the domain plan): `document/Insertion.jl`
(shared insertion document, moved down from domain's `core/`); a new
`serialization/` layer with BinarySerialization / NaturalFormat /
DocumentFile (the domain-independent persistence frameworks).
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
const IntentModule = ProjecturedKernel.IntentModule
const IoMapModule = ProjecturedKernel.IoMapModule
const IoMapApiModule = ProjecturedKernel.IoMapApiModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const IdentityProjectionModule = ProjecturedKernel.IdentityProjectionModule
const GestureModule = ProjecturedKernel.GestureModule
const BackendModule = ProjecturedKernel.BackendModule

# ── Layer 1 — document (concrete engine documents) ────────────────────────
# Collection precedes Primitive and ScreenDocument (both import CellVector).
# Each file registers its own R1 / R2 seam methods onto the kernel's
# OperationModule generics.
include("document/Collection.jl")
include("document/Primitive.jl")
include("document/ScreenDocument.jl")

# ── Layer 2 — projection (document-shaped generic projections) ────────────
# The 5 doc-shaped projections + the R6 reader defaults. Each file is
# currently its own module; a later cosmetic pass may consolidate them into
# a single BaseProjectionModule aggregator with fragments.
include("projection/Sorting.jl")
include("projection/Filtering.jl")
include("projection/Searching.jl")
include("projection/Copying.jl")
include("projection/WindowManaging.jl")
include("projection/ReaderDefaults.jl")

end # module ProjecturedBase
