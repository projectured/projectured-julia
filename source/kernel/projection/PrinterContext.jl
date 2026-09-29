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
  printed with it stays at time 0. A caller that animates gives the root context
  a `Clock` of its own, and writes it once per frame.

`PrinterContext(reference, width, height, properties[, clock])` makes a context
whose range is exact on each axis where a cell is given, as the root of a
window gives its size, and free where `nothing` is given.

`get_exact_width(ctx)` and `get_exact_height(ctx)` read the extent of an exact
range, and `nothing` for a bounded or a free one.

Use it to give a printer what its parent knows: where the input sits in the
document, how much room there is, the clock of animated output, and the
properties that a parent sets for its subtree.

# Example

    width, height = Cell(800), Cell(600)
    context = PrinterContext(EmptyReference(), width, height, Dict{Symbol, Any}())
    iomap = print_document(projection, projection, document, context)

See also `make_child_context`, which makes the context of a child, and
`with_exact_size`, `with_bounded_size` and `with_property`, which change one part.
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

"""
    get_exact_width(ctx) -> Union{Cell, Nothing}

The width of `ctx` when its range on the width is exact: the one cell that is
both its minimum and its maximum. `nothing` when the range is bounded or free.

Use it where a printer fills the slot that its parent gives, and is its content
where the parent gives none: a shell, a split, a viewport, the columns of a grid.
"""
get_exact_width(ctx::PrinterContext) = _get_exact_extent(ctx.minimum_width, ctx.maximum_width)

"""
    get_exact_height(ctx) -> Union{Cell, Nothing}

The height of `ctx` when its range on the height is exact, and `nothing` when it
is bounded or free. See [`get_exact_width`](@ref).
"""
get_exact_height(ctx::PrinterContext) = _get_exact_extent(ctx.minimum_height, ctx.maximum_height)

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

Use it to give a child its place in the document before a node printer prints
the child.

# Example

    context = make_child_context(ctx, FieldReferenceStep("content"))
    content_iomap = print_child(recursion, input.content, context)

See also `print_child`, which prints the child with it, and `with_exact_size`,
which gives the child a range of its own.

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
across the print recursion.
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
    withhold_offer(ctx, axis) -> PrinterContext

The context a container hands its children on an axis whose extent the container
derives **from** those children.

A vertical stack's height is the sum of its children's, a card's height is its
content's, a toolbar's width is its items'. Such a container must not offer that
extent back down: a child that reads it ultimately reads the container's own outer
size, which closes a reactive cycle and overflows the stack when the cell
evaluates.

So the offer is derived from what the container is, not chosen at each site. This
is that rule, written once — `axis` is the axis the container derives, `:x` or
`:y`, and the other axis passes through untouched. The axis becomes free: no
minimum and no maximum. Any other `axis` throws an `ArgumentError`.
"""
function withhold_offer(ctx::PrinterContext, axis::Symbol)
    axis === :x && return with_exact_size(ctx; width = nothing)
    axis === :y && return with_exact_size(ctx; height = nothing)
    throw(ArgumentError("withhold_offer: the axis is :x or :y, not :$axis"))
end

"""
    with_clock(ctx, clock) -> PrinterContext

Return a copy of `ctx` bound to a different `clock`. Use it to give the root
context of a tree a clock of its own, so that a write to one clock invalidates
only the cells of its own tree.
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
