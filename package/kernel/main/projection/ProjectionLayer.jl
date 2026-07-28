# ── Projection layer — interface & infrastructure ──────────────────────────
# This layer keeps only the interface, the gesture-binding machinery, the
# `@projection` macro defaults, and the projection-template engine. The concrete
# projection algebra (the generic + higher-order combinators) is
# domain-independent framework that sinks to a higher package, not here. The IO
# maps it builds on are the layer below (`iomap/`).
# The ordered include list of the projection layer; a fragment of ProjecturedKernel.
# The interface stubs lead the layer: ProjectionApi declares the abstract types
# and open generics (the four projection functions) that everything below
# implements; Intent is the reader-side protocol data type. Nothing below this
# layer imports any of them — a higher package extends the generics through the
# fully loaded kernel, so they need no earlier position in the include list.
# ProjectionReferenceStep — a reference step whose payload is a projection.
# Small, self-contained; needs only DocumentModule and ReferenceModule, so
# loads first in the layer.
include("ProjectionReferenceStep.jl")
include("ProjectionApi.jl")
include("Intent.jl")
# PrinterContext (Cell + Reference only) is projection-layer infrastructure
# consumed by ProjectionModule and the generic projections.
include("PrinterContext.jl")
# Open generics for the children container the template engine uses; a higher
# package adds the concrete element-collection methods.
include("ChildrenContainer.jl")
# Open generics for the gesture-binding tables. The concrete generic and
# higher-order projections that consume `collect_gesture_bindings` are
# domain-independent framework that sinks to a higher package; the kernel keeps
# only the binding machinery.
include("GestureBindings.jl")

# ── Projection defaults & the `@projection` macro ──────────────────────────
# ProjectionModule holds the four-generic fallbacks and the `@projection`
# macro. Nothing in the kernel imports it, so it loads after the whole algebra.
include("Projection.jl")

# ── ProjectionTemplate ─────────────────────────────────────────────────────
# The builder-and-walk projection-template engine every structural projection
# uses. It is projection machinery, not per-domain content. It keeps two seams
# open for a higher package:
#   (a) constructive element-collection sites go through the children-container
#       generic (make_children_container / children_container_type); a higher
#       package registers the concrete methods.
#   (b) the text-range-replace read_intent method lives in a higher package
#       beside the primitive-op defaults.
include("ProjectionTemplate.jl")
