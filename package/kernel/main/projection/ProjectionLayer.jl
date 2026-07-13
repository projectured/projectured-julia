# ── Projection layer (layer 8 — interface & infrastructure) ────────────────
# The concrete projection algebra (the generic + higher-order combinators) is
# domain-independent framework and lives in `package/base`; this layer keeps
# only the interface, the IO maps, the gesture-binding machinery, the
# `@projection` macro defaults, and the projection-template engine.
# The ordered include list of the projection layer; a fragment of ProjecturedKernel.
# The interface stubs lead the layer: ProjectionApi and IoMapApi declare the
# abstract types and open generics (the four projection functions, IoMap) that
# everything below implements; Intent is the reader-side protocol data type;
# IoMapModule holds the shared concrete IO maps. Nothing below this layer
# imports any of them — `package/base` extends the generics through the fully
# loaded kernel, so they need no earlier position in the include list.
# ProjectionReference — a reference step whose payload is a projection.
# Small, self-contained; needs only DocumentModule and ReferenceModule, so
# loads first in the layer.
include("ProjectionReference.jl")
include("ProjectionApi.jl")
include("IoMapApi.jl")
include("Intent.jl")
include("IoMap.jl")
# PrinterContext (Cell + Reference only) is projection-layer infrastructure
# consumed by ProjectionModule and the generic projections.
include("PrinterContext.jl")
# Open generics for the children container ProjectionTemplate uses; base's
# Collection.jl adds the CellVector methods.
include("ChildrenContainer.jl")
# Open generics for the gesture-binding tables. The concrete generic and
# higher-order projections that consumed `collect_gesture_bindings` are
# domain-independent framework and now live in `package/base`'s projection
# layer (`ProjecturedBase`); the kernel keeps only the binding machinery.
include("GestureBindings.jl")

# ── Projection defaults & the `@projection` macro ──────────────────────────
# ProjectionModule holds the four-generic fallbacks and the `@projection`
# macro. Nothing in the kernel imports it, so it loads after the whole algebra;
# it needs Primitive, ReferenceCase/Builder, PrinterContext, Keyboard, Mouse.
include("Projection.jl")

# ── ProjectionTemplate ─────────────────────────────────────────────────────
# The builder-and-walk projection-template engine every XToSyntax uses. It is
# projection machinery, not per-domain content. It keeps two base seams open:
#   (a) constructive CellVector(...) sites go through the children-container
#       generic (make_children_container / children_container_type); base's
#       Collection.jl registers the CellVector methods.
#   (b) the ReplaceStringRangeOperation read_intent method lives in
#       base/projection/ReaderDefaults.jl beside the primitive-op defaults.
include("ProjectionTemplate.jl")
