# ── Projection layer — interface & infrastructure ──────────────────────────
# This layer keeps only the interface, the gesture-binding machinery, the
# `@projection` macro defaults, and the projection-template engine. The concrete
# projection algebra (the generic + higher-order combinators) is
# domain-independent framework that sinks to a higher package, not here. The IO
# maps it builds on are the layer below (`iomap/`).
# The ordered include list of the projection layer; a fragment of ProjecturedKernel.
# ProjectionReferenceStep — a reference step whose payload is a projection.
# Small, self-contained; needs only DocumentModule and ReferenceModule, so
# loads first in the layer.
include("ProjectionReferenceStep.jl")
# PrinterContext (Cell + Reference only) is projection-layer infrastructure
# consumed by ProjectionModule and the generic projections.
include("PrinterContext.jl")
# Open generics for the children container the template engine uses; a higher
# package adds the concrete element-collection methods.
include("ChildrenContainer.jl")

# ── ProjectionModule — the contract, its defaults and `@projection` ────────
# The contract declares the four generics every projection implements, and the
# same module holds their fallbacks and the codegen that declares a projection
# type. It loads before the gesture bindings, which take the `Projection` type
# from it.
include("ProjectionModule.jl")

# Open generics for the gesture-binding tables. The concrete generic and
# higher-order projections that consume `read_projection_gesture` are
# domain-independent framework that sinks to a higher package; the kernel keeps
# only the binding machinery.
include("GestureBindings.jl")

# ── ProjectionTemplate ─────────────────────────────────────────────────────
# The builder-and-walk projection-template engine every structural projection
# uses. It is projection machinery, not per-domain content. It keeps two seams
# open for a higher package:
#   (a) constructive element-collection sites go through the children-container
#       generic (make_children_container / get_children_container_type); a higher
#       package registers the concrete methods.
#   (b) the text-range-replace read_intent method lives in a higher package
#       beside the primitive-op defaults.
include("ProjectionTemplate.jl")
