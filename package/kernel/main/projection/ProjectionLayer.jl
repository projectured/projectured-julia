# ── Projection layer (layer 7 — interface, infrastructure & algebra) ───────
# The ordered include list of the projection layer; a fragment of ProjecturedKernel.
# The interface stubs lead the layer: ProjectionApi and IoMapApi declare the
# abstract types and open generics (the four projection functions, IoMap) that
# everything below implements; Intent is the reader-side protocol data type;
# IoMapModule holds the shared concrete IO maps. Nothing below this layer
# imports any of them — `package/base` extends the generics through the fully
# loaded kernel, so they need no earlier position in the include list.
include("ProjectionApi.jl")
include("IoMapApi.jl")
include("Intent.jl")
include("IoMap.jl")
# PrinterContext (Reactive + Reference only) is projection-layer infrastructure
# consumed by ProjectionModule and the generic projections.
include("PrinterContext.jl")
# Open generics for the children container ProjectionTemplate uses; base's
# Collection.jl adds the CellVector methods.
include("ChildrenContainer.jl")
# Must load before the combinators (Chaining/Nesting/Recursive/TypeDispatching)
# that import collect_gesture_bindings from it.
include("GestureBindings.jl")
include("higherorder/Chaining.jl")
include("higherorder/TypeDispatching.jl")
include("higherorder/Recursive.jl")
include("higherorder/Switching.jl")
include("higherorder/PredicateDispatching.jl")
include("higherorder/ReferenceDispatching.jl")
include("higherorder/Nesting.jl")
include("higherorder/EnvelopeUnwrapping.jl")
include("generic/Identity.jl")
include("generic/Reversing.jl")
include("generic/Constant.jl")
include("generic/Focusing.jl")

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
