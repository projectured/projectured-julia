# Graphical Layout Projections

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

> Generalize layout from being baked into a few specific projections
> (`SyntaxToText`, `TextToGraphics`, `TableToGraphics`, `WidgetSplitPane`) into
> a family of domain-preserving projections on the **graphics** domain that
> arrange a collection of graphics elements according to an explicit layout
> strategy: horizontal, vertical, grid, flow, stack, and (eventually)
> constraint-based.

This expands section 10 of [further-development.md](further-development.md).

---

## Motivation

Today, layout is mostly fused with content generation:

- `SyntaxToText` decides indentation, line breaks, and the vertical stack of
  syntax-node children at the **text** level. The result is a flat `TextText`
  with positioned spans and newlines.
- `TextToGraphics` performs word wrapping and the final pixel-positioning of
  `GraphicsText` and `GraphicsRect` primitives.
- `TableToGraphics` computes column widths / row heights from cell projections
  and emits a custom grid in `GraphicsCanvas`.
- `WidgetSplitPaneToGraphicsCanvas`, `WidgetTabbedPaneToGraphicsCanvas`,
  `WidgetScrollPaneToGraphicsCanvas`, etc. each re-implement their own
  positioning logic.

Every container projection re-derives the same primitives:

- "Place these N children one after another along an axis"
- "Track running cursor (x, y)"
- "Compute parent bounding box from child bounds"
- "Skip children outside a clipping rectangle"

Each implementation diverges in alignment behaviour, spacing convention,
overflow handling, and how `w`/`h` are propagated up. This is the kind of
thing a small family of dedicated **layout projections** should own.

The result is a layout vocabulary on the graphics domain that any projection
can compose with by emitting a `GraphicsCanvas` whose `layout` strategy is set
appropriately — letting the layout projection (not the producer) do the
positioning math.

---

## Design Summary

1. Layout is a **domain-preserving projection** `GraphicsCanvas →
   GraphicsCanvas`. It walks the input canvas's element list (positions
   ignored or taken as preferred sizes), positions each child according to
   its strategy, and outputs a new canvas with positioned children.
2. Layout projections **only assign positions**. They do not generate or
   delete elements. The IO map records, for each input element, where it
   ended up — sufficient to translate child-level references unchanged
   (positions are not part of the reference path).
3. Layouts compose. A `HorizontalLayout` containing children that are
   themselves canvases (each with their own layout) recurses through
   `RecursiveProjection`. Each layout reports its computed bounding box
   (`w`, `h` of the output `GraphicsCanvas`) so parents can lay out around it.
4. Layouts read **preferred sizes** from their children. A child canvas's
   `w`/`h` cells are its preferred size; leaf elements (`GraphicsText`,
   `GraphicsRect`, `GraphicsImage`) expose intrinsic dimensions through a
   small `preferred_size(elem)` helper.
5. Existing layout-bearing projections become *thin* — they emit a
   `GraphicsCanvas` with the appropriate `layout` strategy and leave
   positioning to the layout projection downstream.

---

## Existing Infrastructure

The graphics domain already has:

- `GraphicsCanvas` — collection of elements with `x`, `y`, `w`, `h`,
  `layout::LayoutDirection`, `overlapping_elements::Bool`.
- `LayoutDirection` enum: `layout_none`, `layout_horizontal`, `layout_vertical`.
  Used today only for hit-test early-stop and renderer culling, not for
  actually positioning elements.
- `GraphicsFence` — a barrier that splits a canvas into regions where the
  non-overlapping invariant holds piecewise.
- `GraphicsViewport` — a clipping rectangle for the rendered output.
- `hit_element_at` — already understands `layout` and `overlapping_elements`
  for early-stop hit-testing; layout projections must preserve those
  invariants on their output.

What's missing:

- No projection actually *uses* `layout_horizontal` / `layout_vertical` to
  position children. Producers (e.g. `TextToGraphics`) compute positions
  inline.
- No primitive for grid, flex, or constraint-based arrangement.
- No standard way to report a child's preferred size before placement.

---

## Files to Create

### 1. `program/src/projection/primitive/HorizontalLayout.jl` — `HorizontalLayoutModule`

```julia
struct HorizontalLayout <: Projection
    spacing::Int           # pixels between adjacent children
    align::Symbol          # :top | :center | :bottom | :baseline
    padding::NTuple{4,Int} # (top, right, bottom, left)
end

HorizontalLayout(; spacing=0, align=:top, padding=(0,0,0,0)) =
    HorizontalLayout(spacing, align, padding)
```

- `projection_print(p, input::GraphicsCanvas, recursion, reference)`:
  - For each child of `input.elements`, recurse via the recursion arg to
    obtain its laid-out version (so nested canvases lay themselves out
    first).
  - Compute each child's `(w, h)` via `preferred_size`.
  - Position children left-to-right starting at `(padding.left,
    padding.top)`, advancing `x` by `child.w + spacing`.
  - For `align`: top → y = padding.top; center → y = (max_h - child.h) / 2;
    bottom → y = max_h - child.h; baseline → align by font baseline (only
    meaningful when children are `GraphicsText`).
  - Output: a new `GraphicsCanvas` whose `layout = layout_horizontal` and
    `w`, `h` reflect the total bounding box.
- `projection_read`: delegate via the IO map to children (positions don't
  affect selection; references pass through unchanged).
- IoMap: `ChildrenIoMap` (already exists) — one inner iomap per child.

### 2. `program/src/projection/primitive/VerticalLayout.jl` — `VerticalLayoutModule`

Symmetric to `HorizontalLayout` but along the y-axis. `align` values:
`:left | :center | :right`. Output canvas has `layout = layout_vertical`.

This replaces ad-hoc vertical stacking currently inlined in `SyntaxToText`
(but `SyntaxToText` is a text-domain projection — keep that one;
`VerticalLayout` is its graphics-domain counterpart for non-text content).

### 3. `program/src/projection/primitive/StackLayout.jl` — `StackLayoutModule`

```julia
struct StackLayout <: Projection
    align::Symbol     # :start | :center | :end | :stretch
    padding::NTuple{4,Int}
end
```

Children are laid on top of each other (z-order = element order). Used for
overlays, badges, and composing background/foreground (e.g. cursor rect over
text). All children share the same `(x, y)` region; the parent's `(w, h)` is
the maximum of children's preferred sizes.

### 4. `program/src/projection/primitive/GridLayout.jl` — `GridLayoutModule`

```julia
struct GridLayout <: Projection
    columns::Int                       # fixed column count; 0 = derive from rows
    rows::Int                          # fixed row count;    0 = derive from columns
    column_widths::Vector{Sizing}      # per-column sizing (see below)
    row_heights::Vector{Sizing}        # per-row sizing
    gap::NTuple{2,Int}                 # (horizontal_gap, vertical_gap)
    padding::NTuple{4,Int}
end

abstract type Sizing end
struct AutoSize   <: Sizing end                 # fit content
struct FixedSize  <: Sizing; pixels::Int end    # explicit pixels
struct FractionSize <: Sizing; fraction::Float64 end  # share of remaining space
```

The child order is row-major: child index `i` lands at
`(row=(i-1)÷columns, col=(i-1)%columns)`.

The projection:

1. Recurses into each child to obtain its preferred size.
2. Computes column widths: any `AutoSize` column takes the max of its
   children's preferred widths; `FixedSize` is taken as-is; `FractionSize`
   columns split the remaining width.
3. Same for row heights.
4. Positions each child at `(sum_prior_col_widths + col_gaps + padding.left,
   sum_prior_row_heights + row_gaps + padding.top)`.
5. Output canvas `w` / `h` = total grid size + padding.

This subsumes the current `TableToGraphics` layout logic. `TableToGraphics`
could be reimplemented as: produce a canvas containing per-cell projected
canvases, then compose with `GridLayout(columns=ncols, row_heights=...)`.
Whether to migrate `TableToGraphics` is a separate decision; the migration is
optional.

### 5. `program/src/projection/primitive/FlowLayout.jl` — `FlowLayoutModule`

```julia
struct FlowLayout <: Projection
    max_width::Int
    spacing::NTuple{2,Int}    # (h, v)
    align::Symbol             # :start | :center | :end
end
```

Line-wrapping horizontal layout: children fill the current row until the
next child would overflow `max_width`, then wrap to a new row. This is the
graphics-domain analogue of `TextToGraphics` word-wrapping, but for
arbitrary graphics elements (icons, badges, tag chips).

`TextToGraphics` could in principle be split into:
- A `TextToCharGraphics` projection that emits one `GraphicsText` per word
  (or run of styled characters) plus measurement metadata.
- A `FlowLayout` (or `TextFlowLayout`) projection that wraps the resulting
  graphics elements.

This factoring is appealing but invasive — current `TextToGraphics` carries
a rich `char_to_coord` IO map for click → character mapping. Splitting it
would require the IO map to thread through both projections. Defer this
migration; treat it as a separate plan if pursued.

### 6. `program/src/projection/primitive/ConstraintLayout.jl` — `ConstraintLayoutModule`

The eventual end-state for arbitrary arrangements (e.g. dashboards). Each
child carries a set of constraints relating its edges to those of siblings
or the parent. A solver (incremental, Cassowary-style) computes positions
satisfying all constraints.

Initial scope:

- Subset of constraints: per-edge equality / inequality with another
  element's edge, plus min/max sizing.
- A naive solver (Gauss-Seidel-style relaxation iterating until convergence
  or a max-iteration cap) is enough to validate the design.
- Cassowary or a more sophisticated incremental simplex can come later if
  the naive solver proves too slow.

This is **optional and deferred** — it's listed last in the steps below.

### 7. `program/src/projection/primitive/PreferredSize.jl` — `PreferredSizeModule`

```julia
function preferred_size(elem::GraphicsDocument)::Tuple{Int,Int}
    elem isa GraphicsCanvas    && return (Int(elem.w), Int(elem.h))
    elem isa GraphicsViewport  && return (Int(elem.w), Int(elem.h))
    elem isa GraphicsRect      && return (Int(elem.w), Int(elem.h))
    elem isa GraphicsImage     && return (Int(elem.w), Int(elem.h))
    elem isa GraphicsText      && return _text_intrinsic_size(elem)  # needs measure
    elem isa GraphicsFence     && return (0, 0)
    error("preferred_size: unknown element type $(typeof(elem))")
end
```

`GraphicsText`'s intrinsic size depends on a `measure(text, font) -> (w, h)`
function (already passed to `TextToGraphics` by the backend). Layout
projections need access to the same `measure` function — store it as a field
on the projection struct (like `TextToGraphics` does).

---

## Files to Modify

### `program/src/document/Graphics.jl`

- Add `layout_stack`, `layout_grid`, `layout_flow` to `LayoutDirection` enum
  (currently only `none`/`horizontal`/`vertical`). Hit-testing's early-stop
  optimisations only fire for `horizontal`/`vertical`; for new layouts,
  early-stop is disabled (fall back to scanning all elements) unless we add
  per-layout hit-test helpers.

### `program/src/projection/primitive/TableToGraphics.jl`

Optional migration: replace the inline grid arithmetic in
`projection_print(p::TableTableToGraphicsCanvas, ...)` with a composition
that produces an un-positioned canvas of cell projections and then chains
through `GridLayout`. The IO map shape stays compatible
(`ChildrenIoMap` flows the same way). Defer if the gain is marginal.

### `program/src/projection/primitive/WidgetToGraphics.jl`

`WidgetCompositeToGraphicsCanvas`, `WidgetShellToGraphicsCanvas`, and
`WidgetSplitPaneToGraphicsCanvas` all do their own positioning. These could
in principle become thin wrappers over `HorizontalLayout` /
`VerticalLayout` / `StackLayout`. Tackle one at a time after the layout
projections are in.

### `program/src/Projectured.jl`

- `include` each new layout module under the primitive-projections section.
- Add `using` lines and exports for the new projection types.

### `guide/projection-system.md` and `guide/document/graphics.md`

Document the layout family: what each layout does, what shape of input it
expects, what its output canvas looks like, and how to compose them.

---

## IoMap Design

Layout projections do not change the **identity** or **count** of children;
they only rewrite positions. The selection model is reference-based and
positions are not part of references, so child-level references map through
unchanged.

The simplest IO map is `ChildrenIoMap` (already exists): an array of inner
iomaps, one per child. `map_reference_forward` / `map_reference_backward`
recurse into the child iomap matched by the path's `ElementReference`.

The only layout-specific concern: if a child gets clipped out entirely
(e.g. doesn't fit even after wrapping in `FlowLayout`), its iomap slot is
still present but the child has zero output area — this is fine for
selection (the path resolves), but it means the renderer / hit-tester will
just not visit that region.

---

## Mouse Hit-Testing Across Layouts

`hit_element_at` already handles `layout_horizontal` and `layout_vertical`
canvases by short-circuiting when an element's coordinate exceeds the click
point along the layout axis. For new layouts:

- **Stack**: must scan all children (they overlap by definition); the
  top-most match wins (iterate in reverse so later elements shadow earlier
  ones).
- **Grid**: hit-test by computing `(col, row) = ((x - padding.left) /
  col_width, (y - padding.top) / row_height)` directly, then test only that
  cell.
- **Flow**: each *row* is a sub-region with horizontal layout; if we
  represent the flow output as a vertical layout of horizontal-layout
  rows (an internal grouping), the existing hit-test logic falls out for
  free.

The Flow → "vertical of horizontals" representation is appealing because it
makes hit-testing free, but it also nests the IO map: a flat child index now
sits inside a `(row, position_in_row)` path. Need to decide whether to
expose this nesting in the reference path or to flatten it back at the
layout output. Flattening preserves the simple `ChildrenIoMap` shape — do
that.

---

## Steps

1. **Add `preferred_size` helper** — minimum viable: a function on
   `GraphicsDocument` returning `(w, h)`. Requires a `measure` function for
   `GraphicsText`.
2. **Implement `HorizontalLayout`** — simplest case. Verify a hand-built
   `GraphicsCanvas` of mixed leaf elements is correctly positioned.
3. **Implement `VerticalLayout`** — symmetric. Verify nested
   horizontal/vertical compositions.
4. **Implement `StackLayout`** — needed for cursor overlay, badges.
5. **Implement `GridLayout`** with `AutoSize` + `FixedSize` sizing. Defer
   `FractionSize` until a use case appears.
6. **Implement `FlowLayout`** as vertical-of-horizontals.
7. **Migrate one existing positioner** — pick `WidgetCompositeToGraphicsCanvas`
   or `WidgetSplitPaneToGraphicsCanvas`. Validate that selection /
   hit-testing / rendering all still work.
8. **(Optional) Migrate `TableToGraphics`** to use `GridLayout`. Defer if
   the existing implementation works fine.
9. **(Optional, deferred) Implement `ConstraintLayout`** with a naive
   solver. Only pursue when a real use case (dashboard editor, free-form
   document layout) demands it.

---

## Open Questions

- **Layout in text vs. graphics domain.** `SyntaxToText` performs vertical
  stacking *at the text level* — it inserts `TextNewline`s. Should syntax
  nodes instead emit a graphics canvas with `VerticalLayout`, skipping the
  text-level newline-stacking? That would unify all layout in one domain
  but loses the ability to copy/paste a flat textual representation of a
  syntax tree. Probably keep text-level layout for things that have a
  natural textual rendering (code, prose) and use graphics-level layout for
  things that don't (graphs, tables, dashboards).
- **Preferred-size cycles.** If a child's preferred size depends on
  available space (e.g. word-wrapped text wants to know parent width
  before computing its own height), the layout needs a two-pass model: a
  first pass collects intrinsic widths, the parent assigns available
  widths, a second pass measures heights. `FlowLayout` already faces this
  — its `max_width` is a configured parameter, not derived from the
  parent. A future "content-aware" layout would need the two-pass model
  (or a ProjectionContext field carrying available width — see the
  `projection-context.md` plan).
- **Reactivity granularity under layout.** Each layout's output positions
  depend on every child's preferred size. Adding or removing a child
  invalidates all sibling positions. For a 10,000-element grid this is
  fine (positions are computed in one pass). For an interactive layout
  where children resize independently, every position is recomputed on
  every change. Whether that becomes a bottleneck is an empirical
  question — needs the benchmark suite (further-development §17).
- **Animation / transitions.** None of the proposed layouts handle
  animated transitions between layout configurations (e.g. an element
  smoothly moving from row 1 to row 2 when its sort key changes).
  Animation is out of scope for this plan — it would need a separate
  "interpolating layout" or post-layout animation projection.
- **Layout debug overlay.** A debug projection that paints layout cell
  boundaries (grid lines, gutter areas, padding regions) on top of the
  output canvas, similar to a CSS dev-tools "show layout" mode. Probably
  cheap to add and worth doing for the developer-experience track
  (further-development §19).
- **Relationship to `ProjectionContext`.** Layout projections want to pass
  `:available_width` / `:available_height` down to children (see the
  `projection-context.md` plan). Once `ProjectionContext` lands, layout
  projections should set these context properties before recursing into
  children, so content projections can adapt (e.g. word-wrap to the
  available width without hard-coding a `max_width` argument). Layout
  projections are one of the strongest motivators for `ProjectionContext`.

---

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Layout projections re-implement subtle positioning logic that already works in `TableToGraphics` / `TextToGraphics`. | Don't migrate existing projections in this plan; only add the layout projections and use them in new code. Migration is a separate, optional follow-up. |
| Hit-testing logic divergence between layout strategies. | Keep the early-stop optimisations in `hit_element_at` axis-only (horizontal / vertical). For other layouts, fall back to a linear scan (they have small element counts in practice). |
| Preferred-size measurement needs a `measure` function for text. | Pass `measure` to layouts that may contain text, exactly as `TextToGraphics` does. Backends already inject `sdl_measure_text`. |
| Constraint solver complexity. | Defer `ConstraintLayout` indefinitely; ship the box-model layouts first and revisit only if a real use case demands the generality. |
| Layout output canvas's `w`/`h` cells become hot dependencies. | Confirmed acceptable: layout output is one canvas per layout invocation, so the cell graph grows linearly with layout depth, not with element count. |

---

## Summary

Add a family of domain-preserving `GraphicsCanvas → GraphicsCanvas`
projections — `HorizontalLayout`, `VerticalLayout`, `StackLayout`,
`GridLayout`, `FlowLayout`, and (eventually) `ConstraintLayout` — that
position children according to an explicit strategy. Layout becomes a
composable concern handled by dedicated projections rather than logic
fused into content-generating projections. Existing positioners
(`TableToGraphics`, widget containers) can migrate incrementally without
breaking the projection pipeline, since layout projections preserve the
graphics domain and the child reference structure.
