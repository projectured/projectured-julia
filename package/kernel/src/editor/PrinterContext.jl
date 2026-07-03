"""
    PrinterContextModule

The downward-flowing per-invocation context threaded through
`print_document`. Replaces the bare `ReferencePath` 4th argument with a
lightweight, extensible struct that carries the reference path **plus**
optional fields projections can use to pass information through the tree.

The struct exposes a few named fields for universal concerns (reference
path, tree depth, available width/height) and an open-ended properties
`Dict` for per-projection data (theme, breadcrumbs, ancestor flags, …).

Builder helpers (`child_context`, `with_available_size`, `with_property`)
let projections extend the context without knowing its full field set.
"""
module PrinterContextModule

import ..ReactiveModule: Cell
import ..ReferenceModule: ReferencePath, EmptyReferencePath, ReferenceStep, append_reference

export PrinterContext, child_context, with_available_size,
       with_property, get_property

"""
    PrinterContext(reference, available_width, available_height, properties)

Downward-flowing per-invocation context for `print_document`.

- `reference` — `ReferencePath` describing where the current input sits
  relative to the document root (replaces the old 4th argument). Tree
  depth is `length(reference)` — derive it on demand rather than caching
  a redundant field.
- `available_width` / `available_height` — the parent-allocated space, as
  reactive cells (or `nothing` if unbounded). Promoted to typed fields
  because layout is a universal concern; using `Cell` (rather than a
  plain value) lets descendants read the allocation reactively so that a
  resize never forces re-projection.
- `properties` — open-ended `Dict{Symbol, Any}` for per-projection data
  (theme, focus, debug flags, …).
"""
struct PrinterContext
    reference::ReferencePath
    available_width::Union{Nothing, Cell}
    available_height::Union{Nothing, Cell}
    properties::Dict{Symbol, Any}
end

PrinterContext() =
    PrinterContext(EmptyReferencePath(), nothing, nothing, Dict{Symbol,Any}())

PrinterContext(ref::ReferencePath) =
    PrinterContext(ref, nothing, nothing, Dict{Symbol,Any}())

"""
    child_context(ctx, steps...) -> PrinterContext

Return a context for a child position: extends `ctx.reference` by `steps`.
Available width/height are inherited unchanged — pass-through wrappers
keep the parent's allocation; a layout that re-allocates space calls
`with_available_size` explicitly.

!!! warning "The properties Dict is shared, not copied"
    `child_context` passes the parent's `properties` Dict to the child **by
    reference**. Mutating it in place (`ctx.properties[k] = v`) therefore leaks
    into the parent and every sibling branch. Always add per-projection data
    with `with_property`, which copies the Dict so branches stay isolated; treat
    `ctx.properties` as read-only.
"""
function child_context(ctx::PrinterContext, steps::ReferenceStep...)
    PrinterContext(
        append_reference(ctx.reference, steps...),
        ctx.available_width,
        ctx.available_height,
        ctx.properties)
end

"""
    child_context(ctx, ref::ReferencePath) -> PrinterContext

Build a child context whose `reference` is the given path directly (rather
than extending `ctx.reference`). Inherits available size and properties.
Useful when the caller already constructed the full child path with
`@reference`.
"""
function child_context(ctx::PrinterContext, ref::ReferencePath)
    PrinterContext(
        ref,
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
function with_available_size(ctx::PrinterContext;
                             width::Union{Nothing, Cell}=ctx.available_width,
                             height::Union{Nothing, Cell}=ctx.available_height)
    PrinterContext(ctx.reference, width, height, ctx.properties)
end

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
                      ctx.available_width, ctx.available_height, props)
end

"""
    get_property(ctx, key, default=nothing)

Look up `key` in `ctx.properties`, returning `default` when missing.
"""
get_property(ctx::PrinterContext, key::Symbol, default=nothing) =
    get(ctx.properties, key, default)

end # module
