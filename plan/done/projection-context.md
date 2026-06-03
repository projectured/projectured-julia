# Plan: Replace `reference` with `ProjectionContext`

Replace the 4th `reference` argument of `projection_print` with a richer
`ProjectionContext` struct that carries the reference path **plus** optional
fields projections can use to pass information downward through the tree.

---

## Motivation

Today every `projection_print` method receives `(projection, input, recursion,
reference)` where `reference :: ReferencePath` is the sole channel for
top-down information flow. Any time a projection needs context from its
ancestors — depth, available width, theme, whether it sits inside a
collapsed region — it must either:

1. Hard-code it in the projection struct (static, not tree-position–aware).
2. Smuggle it through the document itself (mixes concerns).
3. Add yet another argument (breaks the uniform interface).

A **ProjectionContext** replaces `reference` with a lightweight, extensible
bag of downward-flowing state. The reference path becomes one field inside
it, and projections that don't care about anything else keep working with
minimal change.

---

## Design

### The struct

```julia
struct ProjectionContext
    reference::ReferencePath                      # mandatory — existing behaviour
    depth::Int                                    # tree depth (0 = root)
    available_width::Union{Nothing, Cell{Int}}    # parent-allocated width (down), or nothing
    available_height::Union{Nothing, Cell{Int}}   # parent-allocated height (down), or nothing
    properties::Dict{Symbol, Any}                 # open-ended per-projection data
end
```

`available_width` / `available_height` are explicit, typed fields rather
than `properties` keys because they are *universal* layout concerns that
any container may set and any content may read — promoting them to fields
keeps that path type-stable and avoids boxing the reactive `Cell` in
`Any`. They are `Cell{Int}` (not plain `Int`) so the allocation can change
reactively without re-projecting — see [The cell approach](#the-cell-approach-reactive-no-re-projection)
below. (`Cell` is imported from `ReactiveModule`.)

**Convenience constructor** preserving the old call pattern:

```julia
ProjectionContext() =
    ProjectionContext(EmptyReferencePath(), 0, nothing, nothing, Dict{Symbol,Any}())
ProjectionContext(ref::ReferencePath) =
    ProjectionContext(ref, 0, nothing, nothing, Dict{Symbol,Any}())
```

**Builder helpers** so projections extend the context without knowing its
full set of fields:

```julia
# Extend reference + bump depth (most common case). The available-size
# fields are inherited unchanged — a pass-through wrapper keeps the
# parent's allocation; a layout overrides it explicitly with
# `with_available_size` (below).
function child_context(ctx::ProjectionContext, steps::ReferenceStep...)
    ProjectionContext(
        append_reference(ctx.reference, steps...),
        ctx.depth + 1,
        ctx.available_width,
        ctx.available_height,
        copy(ctx.properties))
end

# Set / override the size allocated to a child. Either axis may be left
# as-is by omitting the keyword. Values are `Cell{Int}` so the allocation
# can change reactively without re-projecting (see below).
function with_available_size(ctx::ProjectionContext;
                             width::Union{Nothing, Cell{Int}}=ctx.available_width,
                             height::Union{Nothing, Cell{Int}}=ctx.available_height)
    ProjectionContext(ctx.reference, ctx.depth,
                      width, height, ctx.properties)
end

# Set / override a property
function with_property(ctx::ProjectionContext, key::Symbol, value)
    props = copy(ctx.properties)
    props[key] = value
    ProjectionContext(ctx.reference, ctx.depth,
                      ctx.available_width, ctx.available_height, props)
end

# Read a property (with default)
get_property(ctx::ProjectionContext, key::Symbol, default=nothing) =
    get(ctx.properties, key, default)
```

### Signature change

```
# Before
projection_print(projection, input, recursion, reference)

# After
projection_print(projection, input, recursion, context::ProjectionContext)
```

The 2-arg convenience wrapper becomes:

```julia
function projection_print(projection, input)
    projection_print(projection, input, nothing, ProjectionContext())
end
```

---

## What the context enables

### 1. Depth-aware rendering

Projections can inspect `ctx.depth` to:

- **Auto-collapse** nodes beyond a configurable depth (e.g. JSON trees
  deeper than 3 levels start collapsed).
- **Truncate** large sub-trees with a "…" placeholder beyond a limit.
- **Vary indentation** — deeper nodes could use tighter indentation or
  switch to a compact inline style.

```julia
function projection_print(p::JsonArrayToSyntaxNode, j::JsonArray, recursion, ctx)
    if ctx.depth > p.max_expand_depth
        return _collapsed_placeholder(p, j, ctx)
    end
    # ... normal expansion, passing child_context(ctx, ...) to children
end
```

### 2. Available-size / layout constraints

A parent projection (a table cell, a split pane, a layout document, or a
scroll container) knows how many pixels are available for a given child.
It sets the context's `available_width` (and/or `available_height`) field
so that downstream projections adapt:

```julia
ctx = with_available_size(ctx; width = Cell(() -> 400))
# child TextToGraphics reads the field directly:
max_w = ctx.available_width === nothing ? p.max_width : ctx.available_width[]
```

This eliminates the need to hard-code `max_width` in `TextToGraphics` or
thread it through multiple layers manually.

#### Why the context is the only correct channel for available space

Available space is **contextual**, not a property of the document. A
document can appear at multiple positions in the object graph (the
document graph is a DAG, not a tree), and each occurrence may be given a
different amount of space by a different parent. Storing the allocation on
the document would force one document to carry a single parent's
allocation — wrong the moment it is shared.

This is the *same* reason `reference` is contextual: the same document at
two graph positions has two different references. Available space has the
identical shape, so it belongs in the same per-invocation context that
`reference` already lives in — not on the document, and not in the
projection struct.

#### Intrinsic up, available down

Layout needs two opposite-flowing channels, and they must stay distinct:

| Channel | Direction | Carrier | Meaning |
|---|---|---|---|
| **Intrinsic size** | child → parent (up) | `GraphicsCanvas.w`/`.h`, `WidgetXxx.size` | the content's *natural* size |
| **Available size** | parent → child (down) | `ProjectionContext.available_width` / `.available_height` | the space the parent *allocated* |

Intrinsic-size cells are never overwritten with an allocated value; the
allocation flows only through the context. The layout-policy degrees of
freedom (min / preferred / max / weight) and the allocation algorithm that
*produces* the available size live in a separate `LayoutConstraint`
document — see [widget-layout.md](../pending/widget-layout.md). **This plan
owns only the downward channel** that carries the resulting available
size to the child.

#### The cell approach (reactive, no re-projection)

The available-size fields are typed `Union{Nothing, Cell{Int}}` — a
`Cell{Int}`, not a plain `Int`, for incremental relayout:

```julia
ctx = with_available_size(ctx; width = alloc_w_cell)   # alloc_w_cell::Cell{Int}
```

A plain value bakes the allocation into the projection output, so any
change (window resize, sibling resize) forces the parent to re-project the
child just to hand it a new number. A `Cell` instead lets the child *wire*
its own adaptive cells to read the available-size cell, so the reactive
engine propagates a change without re-running `projection_print`:

```julia
function projection_print(p::TextToGraphics, t, recursion, ctx)
    avail_w = ctx.available_width                            # Cell{Int} or nothing
    wrap_w  = avail_w === nothing ? Cell(() -> p.max_width) :
                                    Cell(() -> avail_w[] - 2 * p.padding)
    # text layout reads wrap_w[] to choose line breaks;
    # output canvas.h is a computed cell over wrap_w → re-wraps lazily.
end
```

Resize flow with the cell approach:

```
window_w (write) → alloc_w_cell → wrap_w → [re-wrap] → canvas.h → parent vertical layout
```

A single write to `window_w` invalidates exactly the cells downstream of
the available-width cell. No projection re-runs; the next print pulls the
re-wrapped result. This is the same incremental story the rest of the
reactive system provides — the context cell just extends the dependency
graph across the parent → child boundary.

#### Worked example: word wrap

Word wrap is the canonical case where **width is extrinsic (top-down) and
height is intrinsic (bottom-up)**:

1. Parent computes the child's allocated width as `alloc_w_cell`.
2. Parent recurses with `with_available_size(ctx; width = alloc_w_cell)`.
3. Child reads `ctx.available_width`, sets `wrap_w`, breaks lines at that
   width.
4. Child's `canvas.h` is a computed cell over `wrap_w` (more wrapping →
   taller) — flowing back *up* via the intrinsic-size channel.
5. Parent reads `canvas.h` to place the child vertically.

The two channels carry the two axes: width down through the context,
height up through `canvas.h`. The reactive graph *is* the two-pass
measure — no explicit measure/arrange phase is needed.

**Caveat — preferred-main-axis must stay intrinsic.** A child's preferred
size on the *main* axis (flowing up) must not itself depend on the
available size on that axis (flowing down), or the dependency graph
cycles. For text, "preferred width = natural single-line width" is safe
because it doesn't read the allocation. Keep that rule for any content
that participates in main-axis allocation.

### 3. Theme / style inheritance

A top-level "theme" projection can inject `:theme` into the context.
Every downstream leaf projection reads it instead of carrying its own
font/color fields:

```julia
ctx = with_property(ctx, :theme, dark_theme)
# later, in a leaf:
theme = get_property(ctx, :theme, default_theme)
font  = theme.code_font
color = theme.string_color
```

This makes theming a single-point-of-change concern rather than a
per-projection-struct concern.

### 4. Ancestor / breadcrumb awareness

Projections can record their identity so children know what they are
nested inside:

```julia
ctx = with_property(ctx, :inside_table, true)
# A child projection can then:
if get_property(ctx, :inside_table, false)
    # use compact single-line layout instead of multi-line
end
```

Or accumulate a breadcrumb trail:

```julia
crumbs = get_property(ctx, :breadcrumbs, Symbol[])
ctx = with_property(ctx, :breadcrumbs, [crumbs..., :json_array])
```

### 5. Collapsed-region propagation

Today `collapsed` is a per-node boolean on `SyntaxNode`. With context,
a parent that is collapsed can tell all descendants, avoiding redundant
work:

```julia
if get_property(ctx, :ancestor_collapsed, false)
    return _skip_subtree(p, input, ctx)
end
```

### 6. Focus / read-only flags

The editor could set `:focused_path` in the context. Projections compare
`ctx.reference` against it to decide whether to show a cursor, enable
editing, or dim unfocused regions:

```julia
focused = get_property(ctx, :focused_path, nothing)
is_focused = focused !== nothing && is_prefix_of(focused, ctx.reference)
```

### 7. Debug / instrumentation

A diagnostic mode can set `:trace => true` in the context. Projections
that opt in emit timing or logging without any global flag:

```julia
if get_property(ctx, :trace, false)
    @info "projection_print" projection=p depth=ctx.depth ref=ctx.reference
end
```

---

## Migration strategy

### Phase 0 — Add the type (non-breaking)

1. Create `ProjectionContext` in a new module (`ProjectionContextModule`)
   next to `ReferenceModule`.
2. Export it and the builder helpers.
3. Add a convenience conversion so existing code that passes a bare
   `ReferencePath` still works during transition:

   ```julia
   # Temporary bridge — remove after full migration
   to_context(ctx::ProjectionContext) = ctx
   to_context(ref::ReferencePath) = ProjectionContext(ref)
   ```

### Phase 1 — Update higher-order projections

Higher-order projections only forward the 4th argument. Change their
signatures and pass `ctx` through:

| Module | Change |
|---|---|
| `Sequential.jl` | `reference` → `ctx`, forward as-is |
| `Recursive.jl` | same |
| `TypeDispatching.jl` | same |
| `PredicateDispatching.jl` | same |
| `ReferenceDispatching.jl` | read `ctx.reference` for dispatch, forward `ctx` |
| `Alternative.jl` | same |
| `Nesting.jl` | same |

These are mechanical renames; behaviour is identical because they only
pass the argument through (or, in `ReferenceDispatching`, read
`.reference` from it).

### Phase 2 — Update primitive projections

Primitive projections that call `append_reference(reference, ...)` switch
to `child_context(ctx, ...)`. Those that only receive `reference` and
ignore it just rename the parameter.

Rough count from the codebase:

- **Leaf projections** (JsonNull, JsonBool, MathVariable, …): ~15 methods.
  Only rename `reference` → `ctx`. No `append_reference` calls.
- **Node projections** (JsonArray, JuliaCall, MathBinaryOp, …): ~20 methods.
  Replace `append_reference(reference, ...)` with `child_context(ctx, ...)`.
- **Layout projections** (TextToGraphics, WidgetToGraphics, …): ~17 methods.
  Rename + optionally read new context fields.

### Phase 3 — Update the API module docstring and the 2-arg wrapper

- `ProjectionApiModule`: update the docstring of `projection_print` to
  describe `ProjectionContext` instead of `reference`.
- `ProjectionModule` (common): update the 2-arg wrapper to construct a
  `ProjectionContext()`.
- `Editor.jl`: already calls the 2-arg wrapper; no change needed.

### Phase 4 — Start using context fields

Once the plumbing is done, individual projections can opt in to context
features incrementally:

1. `depth` — add depth-based auto-collapse to `JsonArrayToSyntaxNode`.
2. `available_width` / `available_height` — have `WidgetToGraphics` set them
   for children via `with_available_size`.
3. `:theme` — prototype a `ThemeProjection` higher-order wrapper.

Each of these is an independent, additive change.

---

## Files affected (exhaustive)

| File | Kind of change |
|---|---|
| **New**: `program/src/context/ProjectionContext.jl` | New module |
| `program/src/api/Projection.jl` | Docstring update |
| `program/src/common/Projection.jl` | 2-arg wrapper, default context |
| `program/src/editor/Editor.jl` | No change (uses 2-arg wrapper) |
| `program/src/projection/higherorder/*.jl` (7 files) | Rename `reference` → `ctx` |
| `program/src/projection/primitive/*.jl` (~18 files) | Rename + `child_context` |
| `program/src/reference/Reference.jl` | No change |
| `guide/design.md` | Document the new signature |
| `guide/projection-system.md` | Document ProjectionContext |

---

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Performance: `Dict` allocation per recursive call | Use `copy` only when a property is actually added; most calls just bump depth + extend reference. Consider a persistent/immutable dict later. |
| API churn: every projection method signature changes | Phase 0 bridge (`to_context`) allows gradual migration; one module at a time. |
| Over-engineering: properties bag becomes a grab-bag | Keep the named fields (`reference`, `depth`, `available_width`, `available_height`) for universal concerns; reserve `properties` for genuinely per-projection data. Establish conventions in the guide. |
| Breaking `ReferenceDispatchingProjection` | It reads `.reference` explicitly — after the change it reads `ctx.reference`. Mechanical. |

---

## Open questions

1. **Immutable vs mutable context?** Immutable (current proposal) is safer
   for reactive invalidation. Mutable would avoid copies but risks
   accidental cross-contamination between branches.

2. **Typed fields vs Dict?** A `Dict{Symbol,Any}` is maximally flexible
   but loses type safety and boxes values in `Any`. The policy is to
   *promote hot, universal properties to explicit typed fields* — which
   is exactly what `available_width` / `available_height` are: typed
   `Union{Nothing, Cell{Int}}` fields rather than `:available_width` /
   `:available_height` Dict keys, so layout code stays type-stable and the
   reactive cell isn't boxed. The `properties` Dict remains for genuinely
   open-ended, per-projection data (theme, breadcrumbs, debug flags).
   Promote any property to a field once it becomes hot or universal.

3. **Should `recursion` also live in the context?** It's another piece of
   downward-flowing state. Merging it would simplify the signature to
   `projection_print(projection, input, ctx)` (3 args). Downside: it
   conflates two concerns and makes the common "pass recursion through"
   pattern less explicit. Defer for now.

---

## Summary

Replace the bare `ReferencePath` 4th argument with a `ProjectionContext`
that carries `reference` + `depth` + explicit `available_width` /
`available_height` fields + an extensible `properties` Dict. Migration
is mechanical (rename + wrap), risk is low (bridge type during transition),
and the payoff is a clean channel for depth-aware rendering, layout
constraints, theming, focus tracking, and diagnostics — all without
touching the 4-arg interface contract.
