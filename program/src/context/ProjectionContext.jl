"""
    ProjectionContextModule

The downward-flowing per-invocation context threaded through
`projection_print`. Replaces the bare `ReferencePath` 4th argument with a
lightweight, extensible struct that carries the reference path **plus**
optional fields projections can use to pass information through the tree.

The struct exposes a few named fields for universal concerns (reference
path, tree depth, available width/height) and an open-ended properties
`Dict` for per-projection data (theme, breadcrumbs, ancestor flags, …).

Builder helpers (`child_context`, `with_available_size`, `with_property`)
let projections extend the context without knowing its full field set.
"""
module ProjectionContextModule

import ..ReactiveModule: Cell
import ..ReferenceModule: ReferencePath, EmptyReferencePath, ReferenceStep, append_reference

export ProjectionContext, child_context, with_available_size,
       with_property, get_property

"""
    ProjectionContext(reference, depth, available_width, available_height, properties)

Downward-flowing per-invocation context for `projection_print`.

- `reference` — `ReferencePath` describing where the current input sits
  relative to the document root (replaces the old 4th argument).
- `depth` — tree depth, 0 at the root, incremented by `child_context`.
- `available_width` / `available_height` — the parent-allocated space, as
  reactive cells (or `nothing` if unbounded). Promoted to typed fields
  because layout is a universal concern; using `Cell` (rather than a
  plain value) lets descendants read the allocation reactively so that a
  resize never forces re-projection.
- `properties` — open-ended `Dict{Symbol, Any}` for per-projection data
  (theme, focus, debug flags, …).
"""
struct ProjectionContext
    reference::ReferencePath
    depth::Int
    available_width::Union{Nothing, Cell}
    available_height::Union{Nothing, Cell}
    properties::Dict{Symbol, Any}
end

ProjectionContext() =
    ProjectionContext(EmptyReferencePath(), 0, nothing, nothing, Dict{Symbol,Any}())

ProjectionContext(ref::ReferencePath) =
    ProjectionContext(ref, 0, nothing, nothing, Dict{Symbol,Any}())

"""
    child_context(ctx, steps...) -> ProjectionContext

Return a context for a child position: extends `ctx.reference` by `steps`
and bumps `depth` by 1. Available width/height are inherited unchanged —
pass-through wrappers keep the parent's allocation; a layout that
re-allocates space calls `with_available_size` explicitly.
"""
function child_context(ctx::ProjectionContext, steps::ReferenceStep...)
    ProjectionContext(
        append_reference(ctx.reference, steps...),
        ctx.depth + 1,
        ctx.available_width,
        ctx.available_height,
        ctx.properties)
end

"""
    child_context(ctx, ref::ReferencePath) -> ProjectionContext

Build a child context whose `reference` is the given path directly (rather
than extending `ctx.reference`). Bumps `depth` by 1, inherits available
size and properties. Useful when the caller already constructed the
full child path with `@reference`.
"""
function child_context(ctx::ProjectionContext, ref::ReferencePath)
    ProjectionContext(
        ref,
        ctx.depth + 1,
        ctx.available_width,
        ctx.available_height,
        ctx.properties)
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
function with_available_size(ctx::ProjectionContext;
                             width::Union{Nothing, Cell}=ctx.available_width,
                             height::Union{Nothing, Cell}=ctx.available_height)
    ProjectionContext(ctx.reference, ctx.depth,
                      width, height, ctx.properties)
end

"""
    with_property(ctx, key, value) -> ProjectionContext

Return a copy of `ctx` with `properties[key]` set to `value`. The
properties dict is copied so sibling branches do not see each other's
writes.
"""
function with_property(ctx::ProjectionContext, key::Symbol, value)
    props = copy(ctx.properties)
    props[key] = value
    ProjectionContext(ctx.reference, ctx.depth,
                      ctx.available_width, ctx.available_height, props)
end

"""
    get_property(ctx, key, default=nothing)

Look up `key` in `ctx.properties`, returning `default` when missing.
"""
get_property(ctx::ProjectionContext, key::Symbol, default=nothing) =
    get(ctx.properties, key, default)

end # module
