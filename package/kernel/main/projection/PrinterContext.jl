"""
    PrinterContextModule

The downward-flowing per-invocation context threaded through
`print_document`. Replaces the bare `ReferencePath` 4th argument with a
lightweight, extensible struct that carries the reference path **plus**
optional fields projections can use to pass information through the tree.

The struct exposes a few named fields for universal concerns (reference
path, available width/height, animation clock) and an open-ended properties
`Dict` for per-projection data (theme, breadcrumbs, ancestor flags, …).

Builder helpers (`make_child_context`, `with_available_size`, `with_clock`,
`with_property`) let projections extend the context without knowing its full
field set.
"""
module PrinterContextModule

import ..CellModule: Cell
import ..ReferenceModule: ReferencePath, EmptyReferencePath, ReferenceStep, append_reference
import ..ClockModule: Clock, get_wall_clock

export PrinterContext, make_child_context, with_available_size, with_clock,
       with_property, get_property

"""
    PrinterContext(reference, available_width, available_height, properties, clock)

Downward-flowing per-invocation context for `print_document`.

- `reference` — `ReferencePath` describing where the current input sits
  relative to the document root. Tree depth is `length(reference)` — derive
  it on demand rather than caching a redundant field.
- `available_width` / `available_height` — the parent-allocated space, as
  reactive cells (or `nothing` if unbounded). Promoted to typed fields
  because layout is a universal concern; using `Cell` (rather than a
  plain value) lets descendants read the allocation reactively so that a
  resize never forces re-projection.
- `properties` — open-ended `Dict{Symbol, Any}` for per-projection data
  (theme, focus, debug flags, …).
- `clock` — the animation clock a printer subscribes to for animated
  output. Defaults to the shared wall clock; a live editor loop mints its
  root context with its own private `Clock` so per-editor invalidation falls
  out for free.
"""
struct PrinterContext
    reference::ReferencePath
    available_width::Union{Nothing, Cell}
    available_height::Union{Nothing, Cell}
    properties::Dict{Symbol, Any}
    clock::Clock
end

PrinterContext(reference::ReferencePath,
               available_width::Union{Nothing, Cell},
               available_height::Union{Nothing, Cell},
               properties::Dict{Symbol, Any}) =
    PrinterContext(reference, available_width, available_height, properties,
                   get_wall_clock())

PrinterContext() =
    PrinterContext(EmptyReferencePath(), nothing, nothing, Dict{Symbol,Any}(),
                   get_wall_clock())

PrinterContext(ref::ReferencePath) =
    PrinterContext(ref, nothing, nothing, Dict{Symbol,Any}(), get_wall_clock())

"""
    make_child_context(ctx, steps...) -> PrinterContext

Return a context for a child position: extends `ctx.reference` by `steps`.
Available width/height, clock, and properties are inherited unchanged —
pass-through wrappers keep the parent's allocation; a layout that
re-allocates space calls `with_available_size` explicitly.

!!! warning "The properties Dict is shared, not copied"
    `make_child_context` passes the parent's `properties` Dict to the child **by
    reference**. Mutating it in place (`ctx.properties[k] = v`) therefore leaks
    into the parent and every sibling branch. Always add per-projection data
    with `with_property`, which copies the Dict so branches stay isolated; treat
    `ctx.properties` as read-only.
"""
function make_child_context(ctx::PrinterContext, steps::ReferenceStep...)
    PrinterContext(
        append_reference(ctx.reference, steps...),
        ctx.available_width,
        ctx.available_height,
        ctx.properties,
        ctx.clock)
end

"""
    make_child_context(ctx, ref::ReferencePath) -> PrinterContext

Build a child context whose `reference` is the given path directly (rather
than extending `ctx.reference`). Inherits available size, clock, and
properties. Useful when the caller already constructed the full child path
with `@reference`.
"""
function make_child_context(ctx::PrinterContext, ref::ReferencePath)
    PrinterContext(
        ref,
        ctx.available_width,
        ctx.available_height,
        ctx.properties,
        ctx.clock)
end

"""
    with_available_size(ctx; width=ctx.available_width, height=ctx.available_height)

Return a copy of `ctx` with the available size on either axis replaced.
Either axis may be left as-is by omitting the keyword. Values are `Cell`s
(holding `Int`) so the allocation can change reactively without
re-projection: descendants wire their own adaptive cells to read the
allocation cell, and the reactive engine propagates resizes through the
existing dependency graph.
"""
function with_available_size(ctx::PrinterContext;
                             width::Union{Nothing, Cell}=ctx.available_width,
                             height::Union{Nothing, Cell}=ctx.available_height)
    PrinterContext(ctx.reference, width, height, ctx.properties, ctx.clock)
end

"""
    with_clock(ctx, clock) -> PrinterContext

Return a copy of `ctx` bound to a different `clock`. Used by the editor loop
to mint the root context with its own private clock so per-editor
invalidation stays independent.
"""
with_clock(ctx::PrinterContext, clock::Clock) =
    PrinterContext(ctx.reference, ctx.available_width, ctx.available_height,
                   ctx.properties, clock)

"""
    with_property(ctx, key, value) -> PrinterContext

Return a copy of `ctx` with `properties[key]` set to `value`. The
properties dict is copied so sibling branches do not see each other's
writes.
"""
function with_property(ctx::PrinterContext, key::Symbol, value)
    props = copy(ctx.properties)
    props[key] = value
    PrinterContext(ctx.reference,
                   ctx.available_width, ctx.available_height, props, ctx.clock)
end

"""
    get_property(ctx, key, default=nothing)

Look up `key` in `ctx.properties`, returning `default` when missing.
"""
get_property(ctx::PrinterContext, key::Symbol, default=nothing) =
    get(ctx.properties, key, default)

end # module
