# Fragment of `ProjectionModule` — `PrinterContext`, the context a printer
# carries down the tree: the range of each axis it may use, the clock it animates
# against, and the properties a parent passes to its children.


"""
    PrinterContext(reference, width, height, properties, clock)

Downward-flowing per-invocation context for `print_document`.

- `reference` — `Reference` describing where the current input sits
  relative to the document root. Tree depth is `length(reference)` — derive
  it on demand rather than caching a redundant field.
- `minimum_width` / `maximum_width` and `minimum_height` / `maximum_height` —
  the range that the parent gives on each axis, as reactive cells. The
  maximum is the edge: the child does not draw past it, and the container
  clips there. The minimum is the extent the child takes at least. A
  `nothing` minimum is 0, and a `nothing` maximum is no edge. An axis is in
  one of three states: exact (minimum and maximum are the same cell, "you are
  this"), bounded (no minimum, a maximum: "what you need, up to this") and
  free (neither: "what you need"). Cells, and not numbers, let descendants
  read the range reactively, so that a resize never forces re-projection.
- `properties` — open-ended `Dict{Symbol, Any}` for per-projection data
  (theme, focus, debug flags, …).
- `clock` — the animation clock a printer subscribes to for animated
  output. The default is a new `Clock` that no code writes, so an animation
  printed with it stays at time 0. A live editor loop gives its root context its
  own `Clock`, which it writes once per frame.

`PrinterContext(reference, width, height, properties[, clock])` makes a context
whose range is exact on each axis where a cell is given, as the root of a
window gives its size, and free where `nothing` is given.

`ctx.available_width` and `ctx.available_height` read the extent of an exact
range, and `nothing` for a bounded or a free one.
"""
struct PrinterContext
    reference::Reference
    minimum_width::Union{Nothing, Cell}
    maximum_width::Union{Nothing, Cell}
    minimum_height::Union{Nothing, Cell}
    maximum_height::Union{Nothing, Cell}
    properties::Dict{Symbol, Any}
    clock::Clock
end

# @positional: the five of a root context: where it prints, the width and the height it is exactly, its properties and its clock.
PrinterContext(reference::Reference, width::Union{Nothing, Cell}, height::Union{Nothing, Cell},
               properties::Dict{Symbol, Any}, clock::Clock) =
    PrinterContext(reference, width, width, height, height, properties, clock)

# @positional: the four of a root context: where it prints, the width and the height it is exactly, and its properties.
PrinterContext(reference::Reference, width::Union{Nothing, Cell}, height::Union{Nothing, Cell},
               properties::Dict{Symbol, Any}) =
    PrinterContext(reference, width, height, properties, Clock())

PrinterContext() =
    PrinterContext(EmptyReference(), nothing, nothing, Dict{Symbol,Any}(), Clock())

PrinterContext(ref::Reference) =
    PrinterContext(ref, nothing, nothing, Dict{Symbol,Any}(), Clock())

# The extent of an exact range, the same cell as its minimum and its maximum, and
# `nothing` for a bounded or a free range.
_get_exact_extent(minimum, maximum) = (minimum !== nothing && minimum === maximum) ? maximum : nothing

function Base.getproperty(ctx::PrinterContext, name::Symbol)
    name === :available_width &&
        return _get_exact_extent(getfield(ctx, :minimum_width), getfield(ctx, :maximum_width))
    name === :available_height &&
        return _get_exact_extent(getfield(ctx, :minimum_height), getfield(ctx, :maximum_height))
    getfield(ctx, name)
end

# A copy of `ctx` with the range of each axis given as a pair (minimum, maximum).
_with_ranges(ctx::PrinterContext, width, height; reference = ctx.reference,
             properties = ctx.properties, clock = ctx.clock) =
    PrinterContext(reference, width[1], width[2], height[1], height[2], properties, clock)

_get_width_range(ctx::PrinterContext) = (ctx.minimum_width, ctx.maximum_width)
_get_height_range(ctx::PrinterContext) = (ctx.minimum_height, ctx.maximum_height)

"""
    make_child_context(ctx, steps...) -> PrinterContext

Return a context for a child position: extends `ctx.reference` by `steps`.
The ranges, the clock and the properties are inherited unchanged —
pass-through wrappers keep the parent's range; a layout that gives its child a
range of its own calls `with_exact_size`, `with_bounded_size` or
`withhold_offer` explicitly.

!!! warning "The properties Dict is shared, not copied"
    `make_child_context` passes the parent's `properties` Dict to the child **by
    reference**. Mutating it in place (`ctx.properties[k] = v`) therefore leaks
    into the parent and every sibling branch. Always add per-projection data
    with `with_property`, which copies the Dict so branches stay isolated; treat
    `ctx.properties` as read-only.
"""
function make_child_context(ctx::PrinterContext, steps::ReferenceStep...)
    _with_ranges(ctx, _get_width_range(ctx), _get_height_range(ctx);
                 reference = extend_reference(ctx.reference, steps...))
end

# @positional: a path, in the order it is walked: the context, the node, and the steps that lead to the child.
"""
    make_child_context(ctx, current_doc, steps...) -> PrinterContext

Child context whose reference is `ctx.reference` extended by `steps`, kept
**fully typed**: the appended steps are annotated against `current_doc` (the
document `ctx` currently points at, e.g. the `print_document` input) so every
new node — and the terminal — records its type, then concatenated onto the
already-typed parent reference. This preserves the strict-typing invariant
across the print recursion (the reference-types-always-present plan).
`current_doc` is any document (not a `ReferenceStep`/`Reference`,
which select the other methods).
"""
function make_child_context(ctx::PrinterContext, current_doc::Document,
                            first::ReferenceStep, rest::ReferenceStep...)
    relative = annotate_reference_types(current_doc, Reference(first, rest...))
    _with_ranges(ctx, _get_width_range(ctx), _get_height_range(ctx);
                 reference = concat_references(ctx.reference, relative))
end

"""
    make_child_context(ctx, ref::Reference) -> PrinterContext

Build a child context whose `reference` is the given path directly (rather
than extending `ctx.reference`). Inherits the ranges, the clock and the
properties. Useful when the caller already constructed the full child path
with `@reference`.
"""
function make_child_context(ctx::PrinterContext, ref::Reference)
    _with_ranges(ctx, _get_width_range(ctx), _get_height_range(ctx); reference = ref)
end

# The keyword default of the size helpers: the axis keeps the range it has.
struct _KeepRange end

_get_exact_range(extent::Nothing) = (nothing, nothing)
_get_exact_range(extent::Cell) = (extent, extent)

_get_bounded_range(edge::Nothing) = (nothing, nothing)
_get_bounded_range(edge::Cell) = (nothing, edge)

"""
    with_exact_size(ctx; width, height) -> PrinterContext

A copy of `ctx` whose range is exact on each axis given: the minimum and the
maximum are the same cell, and the child is that extent. `nothing` makes the
axis free. An axis that is not given keeps its range.

Use it where a container gives a child its slot: a weighted child of a stack, a
`Fixed` one, the content of a viewport.
"""
function with_exact_size(ctx::PrinterContext; width = _KeepRange(), height = _KeepRange())
    _with_ranges(ctx,
                 width isa _KeepRange ? _get_width_range(ctx) : _get_exact_range(width),
                 height isa _KeepRange ? _get_height_range(ctx) : _get_exact_range(height))
end

"""
    with_bounded_size(ctx; width, height) -> PrinterContext

A copy of `ctx` whose range is bounded on each axis given: no minimum, and the
cell as the maximum, so the child takes what it needs, up to that edge.
`nothing` makes the axis free. An axis that is not given keeps its range.

Use it where a container knows how much room there is but does not give the
child a slot: a `Content` child of a stack that has an edge.
"""
function with_bounded_size(ctx::PrinterContext; width = _KeepRange(), height = _KeepRange())
    _with_ranges(ctx,
                 width isa _KeepRange ? _get_width_range(ctx) : _get_bounded_range(width),
                 height isa _KeepRange ? _get_height_range(ctx) : _get_bounded_range(height))
end

"""
    with_size_range(ctx; width, height) -> PrinterContext

A copy of `ctx` with the range of each axis given as a pair `(minimum, maximum)`,
each a cell or `nothing`. An axis that is not given keeps its range.

Use it for a range with both a minimum and an edge, as a `Content` child with a
placement minimum receives in a bounded parent. `with_exact_size` and
`with_bounded_size` write the common ranges.
"""
function with_size_range(ctx::PrinterContext; width = _KeepRange(), height = _KeepRange())
    _with_ranges(ctx,
                 width isa _KeepRange ? _get_width_range(ctx) : width,
                 height isa _KeepRange ? _get_height_range(ctx) : height)
end

"""
    with_inner_size(ctx; width = 0, height = 0) -> PrinterContext

A copy of `ctx` whose range on each axis is the range of `ctx` less an inset, in
the same state: an exact range stays exact, a bounded one stays bounded and a
free one stays free. The minimum and the maximum are each reduced by the inset,
and never go under 0. An inset is a number or a cell of a number.

Use it where a container passes its own range on to its content, less its
margin, border, padding and bands.
"""
with_inner_size(ctx::PrinterContext; width = 0, height = 0) =
    _with_ranges(ctx, _get_inner_range(_get_width_range(ctx), width),
                 _get_inner_range(_get_height_range(ctx), height))

_get_inset_value(inset::Real) = Int(inset)
_get_inset_value(inset::Cell) = Int(inset[])

_get_inner_extent(extent::Nothing, inset) = nothing
_get_inner_extent(extent::Cell, inset) =
    Cell(@computation Int32(max(0, Int(extent[]) - _get_inset_value(inset))))

# An exact range stays one cell, so it stays exact.
function _get_inner_range(range, inset)
    minimum, maximum = range
    inner_maximum = _get_inner_extent(maximum, inset)
    minimum === maximum && return (inner_maximum, inner_maximum)
    (_get_inner_extent(minimum, inset), inner_maximum)
end

"""
    with_available_size(ctx; width, height) -> PrinterContext

The same as [`with_exact_size`](@ref).
"""
with_available_size(ctx::PrinterContext; kwargs...) = with_exact_size(ctx; kwargs...)

"""
    withhold_offer(ctx, axis) -> PrinterContext

The context a container hands its children on an axis whose extent the container
derives **from** those children.

A vertical stack's height is the sum of its children's, a card's height is its
content's, a toolbar's width is its items'. Such a container must not offer that
extent back down: a child that reads it ultimately reads the container's own outer
size, which closes a reactive cycle and overflows the stack when the cell
evaluates.

So the offer is derived from what the container is, not chosen at each site. This
is that rule, written once — `axis` is the axis the container derives, and the
other axis passes through untouched. The axis becomes free: no minimum and no
maximum.
"""
withhold_offer(ctx::PrinterContext, axis::Symbol) =
    axis === :x ? with_exact_size(ctx; width = nothing) :
                  with_exact_size(ctx; height = nothing)

"""
    with_clock(ctx, clock) -> PrinterContext

Return a copy of `ctx` bound to a different `clock`. Used by the editor loop
to mint the root context with its own private clock so per-editor
invalidation stays independent.
"""
with_clock(ctx::PrinterContext, clock::Clock) =
    _with_ranges(ctx, _get_width_range(ctx), _get_height_range(ctx); clock = clock)

"""
    with_property(ctx, key, value) -> PrinterContext

Return a copy of `ctx` with `properties[key]` set to `value`. The
properties dict is copied so sibling branches do not see each other's
writes.
"""
function with_property(ctx::PrinterContext, key::Symbol, value)
    props = copy(ctx.properties)
    props[key] = value
    _with_ranges(ctx, _get_width_range(ctx), _get_height_range(ctx); properties = props)
end

"""
    get_property(ctx, key, default=nothing)

Look up `key` in `ctx.properties`, returning `default` when missing.
"""
get_property(ctx::PrinterContext, key::Symbol, default=nothing) =
    get(ctx.properties, key, default)
