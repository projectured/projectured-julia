# ── Projection layer ───────────────────────────────────────────────────────
# The layer holds the projection contract, the fallback of each of its generics,
# the two codegen macros, and the open-generic seams a higher package registers
# against. The concrete projection algebra — the generic and the higher-order
# combinators — is domain-independent framework that sinks to a higher package,
# not here. The IO maps it builds on are the layer below (`iomap/`).
#
# The ordered include list of the layer; a fragment of ProjecturedKernel.
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
