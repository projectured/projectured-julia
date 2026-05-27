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
    reference::ReferencePath          # mandatory — existing behaviour
    depth::Int                        # tree depth (0 = root)
    parent_projection::Any            # the projection that created this ctx (or nothing)
    properties::Dict{Symbol, Any}     # open-ended per-projection data
end
```

**Convenience constructor** preserving the old call pattern:

```julia
ProjectionContext() = ProjectionContext(EmptyReferencePath(), 0, nothing, Dict{Symbol,Any}())
ProjectionContext(ref::ReferencePath) = ProjectionContext(ref, 0, nothing, Dict{Symbol,Any}())
```

**Builder helpers** so projections extend the context without knowing its
full set of fields:

```julia
# Extend reference + bump depth (most common case)
function child_context(ctx::ProjectionContext, steps::ReferenceStep...)
    ProjectionContext(
        append_reference(ctx.reference, steps...),
        ctx.depth + 1,
        ctx.parent_projection,
        copy(ctx.properties))
end

# Set / override a property
function with_property(ctx::ProjectionContext, key::Symbol, value)
    props = copy(ctx.properties)
    props[key] = value
    ProjectionContext(ctx.reference, ctx.depth, ctx.parent_projection, props)
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

### 2. Available-width / layout constraints

A parent projection (e.g. a table cell, a split pane, or a scroll
container) knows how many pixels or columns are available. It can put
`:available_width` into the context so that downstream projections adapt:

```julia
ctx = with_property(ctx, :available_width, 400)
# child TextToGraphics reads:
max_w = get_property(ctx, :available_width, p.max_width)
```

This eliminates the need to hard-code `max_width` in `TextToGraphics` or
thread it through multiple layers manually.

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
2. `:available_width` — have `WidgetToGraphics` set it for children.
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
| Over-engineering: properties bag becomes a grab-bag | Keep the named fields (`reference`, `depth`, `parent_projection`) for universal concerns; reserve `properties` for genuinely per-projection data. Establish conventions in the guide. |
| Breaking `ReferenceDispatchingProjection` | It reads `.reference` explicitly — after the change it reads `ctx.reference`. Mechanical. |

---

## Open questions

1. **Immutable vs mutable context?** Immutable (current proposal) is safer
   for reactive invalidation. Mutable would avoid copies but risks
   accidental cross-contamination between branches.

2. **Typed properties vs Dict?** A `Dict{Symbol,Any}` is maximally
   flexible but loses type safety. An alternative is a type-parameterised
   context or a chain-of-responsibility pattern (each projection wraps the
   context in its own typed layer). Start with Dict, graduate to typed
   layers if hot properties emerge.

3. **Should `recursion` also live in the context?** It's another piece of
   downward-flowing state. Merging it would simplify the signature to
   `projection_print(projection, input, ctx)` (3 args). Downside: it
   conflates two concerns and makes the common "pass recursion through"
   pattern less explicit. Defer for now.

---

## Summary

Replace the bare `ReferencePath` 4th argument with a `ProjectionContext`
that carries `reference` + `depth` + extensible `properties`. Migration
is mechanical (rename + wrap), risk is low (bridge type during transition),
and the payoff is a clean channel for depth-aware rendering, layout
constraints, theming, focus tracking, and diagnostics — all without
touching the 4-arg interface contract.
