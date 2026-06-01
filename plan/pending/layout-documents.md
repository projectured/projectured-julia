# Layout Documents

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

## Summary

Introduce four small layout document types — `HorizontalLayout`,
`VerticalLayout`, `GridLayout`, `FlowLayout` — and their projections to
`GraphicsCanvas`. Each layout holds an ordered list of child documents
(of any type) and a few axis-specific knobs (alignment, gap, max
extent). The corresponding projection always works in the same two
phases:

1. **Recurse first.** Project every child through `recursion` to obtain
   a `GraphicsCanvas` per child.
2. **Then measure.** Read each child canvas's `w` / `h` cells and
   compute a position for it. Wrap each child canvas at its computed
   `(x, y)` and emit one outer `GraphicsCanvas` whose own `w` / `h` are
   computed from the children.

Every position and every outer dimension is a *computed* `Cell`
reading from the child canvases' `w` / `h` cells. Edits inside a child
(text change, sub-layout reflow) invalidate exactly the cells that
depend on the child's new extent — siblings re-position lazily on the
next print, no re-projection of the layout itself required.

This is a domain peer to the widget layer, not a replacement for it.
A `WidgetShell.content` can be a `HorizontalLayout`; a layout's
children can be widgets, or other layouts, or any other document type
with a `…ToGraphicsCanvas` projection. The layout types know nothing
about widgets and have no widget-specific fields.

This plan stands alone but is the natural collaborator of the widget
layout plan ([widget-layout.md](widget-layout.md)): layout documents
handle the *intrinsic, content-driven* case (stack children at their
natural sizes); the widget plan's `wire_split_h!` / `wire_split_v!`
handle the *extrinsic, parent-bounded* case (split a fixed parent
extent across children). Both can coexist in one tree.

---

## Why this shape

- **No new mechanism.** The reactive cell system already supports
  "child extent → parent layout → outer extent" via ordinary computed
  cells. The projection just wires the dependency graph correctly the
  first time it runs.
- **Recurse before measure.** The projection produces the child
  canvases, then reads their cells. This is the only ordering that
  works in ProjecturEd: a parent cannot ask "how big are you?" of an
  unprojected child because intrinsic size is a property of the
  *projection output*, not the document.
- **Type-agnostic children.** A layout's `children::CellVector` holds
  arbitrary `Document`s. Whatever projection the recursion picks for
  each child (via `TypeDispatchingProjection` or whatever the caller
  composed) is fine — the layout only needs the resulting
  `GraphicsCanvas`'s `w` / `h` cells.
- **Composes with widgets.** A `WidgetShell.content` set to a
  `VerticalLayout` of `WidgetLabel`s renders exactly the way you'd
  expect; the existing widget projections produce `GraphicsCanvas`
  outputs that the layout consumes uniformly.

---

## The four documents

All four go in a single module `program/src/document/Layout.jl` →
`LayoutModule`. All four use the `@document` macro and follow the
standard pattern (selection field, reactive cells for every property).

### `HorizontalLayout`

```julia
@document struct HorizontalLayout <: Document
    children::CellVector       # element type: Document
    vertical_align::Symbol     # :top, :center, :bottom
    gap::Int                   # px between adjacent children
    selection::Reference
end
```

Row of children. Outer width = sum of child widths + gaps. Outer
height = max child height. Per-child `y` derived from
`vertical_align`.

### `VerticalLayout`

```julia
@document struct VerticalLayout <: Document
    children::CellVector       # element type: Document
    horizontal_align::Symbol   # :left, :center, :right
    gap::Int                   # px between adjacent children
    selection::Reference
end
```

Column. Symmetric to `HorizontalLayout`.

### `GridLayout`

```julia
@document struct GridLayout <: Document
    children::CellVector       # element type: Document; row-major
    columns::Int               # number of columns; rows derived from len(children)
    horizontal_align::Symbol   # within a cell
    vertical_align::Symbol     # within a cell
    horizontal_gap::Int
    vertical_gap::Int
    selection::Reference
end
```

Children fill row by row. Column widths = max child `w` in each
column. Row heights = max child `h` in each row. Children that don't
fill a full last row leave empty cells.

### `FlowLayout`

```julia
@document struct FlowLayout <: Document
    children::CellVector       # element type: Document
    max_width::Int             # the wrap threshold
    horizontal_align::Symbol   # within each line: :left, :center, :right
    vertical_align::Symbol     # within each line: :top, :center, :bottom
    horizontal_gap::Int
    vertical_gap::Int          # between lines
    selection::Reference
end
```

Like `HorizontalLayout` but wraps when the next child would push the
line past `max_width`. Line height = max `h` of children on that line.
Outer width = `max_width`. Outer height = sum of line heights + vertical
gaps.

---

## The projection pattern

Every projection has the same shape; only the placement math differs.
The pattern:

```julia
struct XxxLayoutToGraphicsCanvas <: Projection end

function projection_print(p::XxxLayoutToGraphicsCanvas, doc::XxxLayout, recursion, reference)
    # 1. Recurse into each child to get its canvas.
    child_iomaps = Any[]
    child_canvases = GraphicsCanvas[]
    for i in eachindex(doc.children)
        cim = projection_print(recursion, doc.children[i], recursion,
                               @reference ^(reference).children[i])
        push!(child_iomaps, (Cell(Int32(0)), Cell(Int32(0)), cim))   # x/y filled in below
        push!(child_canvases, cim.output::GraphicsCanvas)
    end

    # 2. Build computed cells for per-child (x, y) and outer (w, h).
    #    This is the only piece that varies per layout type.
    child_x, child_y, outer_w, outer_h = compute_placement(doc, child_canvases)

    # 3. Wrap each child canvas at its computed (x, y).
    elems = Any[]
    for i in eachindex(child_canvases)
        cc = child_canvases[i]
        push!(elems, GraphicsCanvas(child_x[i], child_y[i],
                                    Cell(Int32(0)), Cell(Int32(0)),
                                    cc.elements, cc.layout, cc.overlapping_elements,
                                    Cell(nothing)))
        child_iomaps[i] = (child_x[i], child_y[i], child_iomaps[i][3])
    end

    # 4. Outer canvas; w/h are computed cells from the children.
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                            Cell(() -> Int32(outer_w[])),
                            Cell(() -> Int32(outer_h[])),
                            CellVector(Cell[Cell(e) for e in elems]),
                            layout_none, true, Cell(nothing))

    ChildrenIoMap(p, doc, canvas, Cell(child_iomaps))
end
```

`compute_placement` is the only per-layout-type function. It returns
four things: a `Vector{Cell{Int32}}` of `x` positions, a
`Vector{Cell{Int32}}` of `y` positions, and two `Cell{Int}` for outer
extent. Below is the math for each.

### `HorizontalLayout.compute_placement`

```julia
function compute_placement(doc::HorizontalLayout, ccs::Vector{GraphicsCanvas})
    gap = getfield(doc, :gap)
    align = getfield(doc, :vertical_align)

    outer_h = Cell(() -> begin
        h = 0
        for c in ccs; h = max(h, Int(c.h[])); end
        h
    end)

    outer_w = Cell(() -> begin
        n = length(ccs)
        n == 0 ? 0 : sum(Int(c.w[]) for c in ccs) + (n - 1) * gap[]
    end)

    child_x = [Cell(() -> begin
        x = 0
        for j in 1:(i-1); x += Int(ccs[j].w[]) + gap[]; end
        Int32(x)
    end) for i in eachindex(ccs)]

    child_y = [Cell(() -> begin
        ch = Int(ccs[i].h[]);  oh = outer_h[]
        a = align[]
        Int32(a === :center ? div(oh - ch, 2) :
              a === :bottom ? oh - ch         :
                              0)
    end) for i in eachindex(ccs)]

    (child_x, child_y, outer_w, outer_h)
end
```

### `VerticalLayout.compute_placement`

Symmetric: swap x/y, swap width/height, swap `vertical_align` →
`horizontal_align`.

### `GridLayout.compute_placement`

```julia
function compute_placement(doc::GridLayout, ccs::Vector{GraphicsCanvas})
    cols  = getfield(doc, :columns)
    hgap  = getfield(doc, :horizontal_gap); vgap = getfield(doc, :vertical_gap)
    halign = getfield(doc, :horizontal_align); valign = getfield(doc, :vertical_align)

    # row/column index for each child (1-based, row-major).
    row_of(i, ncols) = div(i - 1, ncols) + 1
    col_of(i, ncols) = mod(i - 1, ncols) + 1

    # Column widths: max child.w over the column.
    col_w = [Cell(() -> begin
        c = cols[]
        w = 0
        for i in eachindex(ccs)
            col_of(i, c) == col && (w = max(w, Int(ccs[i].w[])))
        end
        w
    end) for col in 1:max_cols_estimate(doc)]   # see Open Questions

    # Row heights: max child.h over the row.
    row_h = [...similar...]

    # Per-child placement reads col_w[col_of(i)] / row_h[row_of(i)] and
    # cumulative sums for the cell origin, then applies alignment within
    # the cell using the child's own w/h.
    ...
end
```

The tricky part is that `cols[]` is reactive, so the *number* of
columns can change. The plan addresses this in Open Questions; a v1
can pin `cols` as a fixed `Int` (not a reactive write target) and
keep the math straightforward.

### `FlowLayout.compute_placement`

Wrapping needs a "line plan": for each child, which line is it on and
what's its x within that line. A single computed `Cell` produces the
plan; per-child placements derive from it.

```julia
line_plan = Cell(() -> begin
    mw = max_width[];  hg = hgap[]
    plan = Tuple{Int,Int}[]              # (line_index, x_in_line) per child
    line, x_cursor = 1, 0
    for i in eachindex(ccs)
        w = Int(ccs[i].w[])
        if x_cursor > 0 && x_cursor + w > mw
            line += 1; x_cursor = 0
        end
        push!(plan, (line, x_cursor))
        x_cursor += w + hg
    end
    plan
end)

line_count = Cell(() -> isempty(line_plan[]) ? 0 : line_plan[][end][1])

line_h = [Cell(() -> begin
    h = 0
    for i in eachindex(ccs)
        line_plan[][i][1] == ln && (h = max(h, Int(ccs[i].h[])))
    end
    h
end) for ln in 1:max_lines_estimate(doc)]

line_y = [Cell(() -> sum(line_h[1:ln-1][]) + (ln - 1) * vgap[])
          for ln in 1:max_lines_estimate(doc)]

child_x = [Cell(() -> Int32(line_plan[][i][2] + line_align_offset(...)))
           for i in eachindex(ccs)]

child_y = [Cell(() -> begin
    ln, _ = line_plan[][i]
    ch = Int(ccs[i].h[]);  lh = line_h[ln][]
    a = valign[]
    Int32(line_y[ln][] +
          (a === :center ? div(lh - ch, 2) :
           a === :bottom ? lh - ch         :
                           0))
end) for i in eachindex(ccs)]

outer_w = Cell(() -> max_width[])
outer_h = Cell(() -> sum(lh[] for lh in line_h) + (line_count[] - 1) * vgap[])
```

The `max_lines_estimate` is bounded by `length(children)`; allocating
the vector at that upper bound is fine. Lines past `line_count[]` hold
height 0.

---

## Prerequisite: child canvases must populate `w` and `h`

`GraphicsCanvas` already has reactive `w` / `h` fields ([Graphics.jl:148-157](../../program/src/document/Graphics.jl#L148-L157)),
but most existing projections create canvases with `w = h = 0` (see
`_make_canvas` in [WidgetToGraphics.jl:232-236](../../program/src/projection/primitive/WidgetToGraphics.jl#L232-L236)).
The renderer doesn't need them today — it walks elements and clips
against the viewport — but a parent layout has no other way to ask
"how big are you?".

**Every projection that produces a `GraphicsCanvas` must compute its
output's `w` and `h`.** Two strategies:

1. **Compute at projection time.** Each leaf projection already
   measures its content for box-model rendering — pass the result
   through to the canvas's `w` / `h` cells. One- or two-line change
   per leaf projection.
2. **Compute lazily from elements.** A helper
   `canvas_bounds(canvas) -> (w, h)` walks elements, takes the
   max of `x + w` and `y + h`, returns the result. Slower but doesn't
   require touching every projection.

Use strategy 1 where the measurement is already available (most leaf
widgets, syntax/text projections). Use strategy 2 as a fallback for
projections where intrinsic size is genuinely unknown until elements
are produced.

For container widgets (`WidgetComposite`, `WidgetTitlePane`,
`WidgetMenu`, `WidgetToolbar`, `WidgetSplitPane`, `WidgetTabbedPane`,
`WidgetScrollPane`, `WidgetShell`), the output's `w` / `h` are
themselves computed cells deriving from the children's wrapped
canvases (just like the layout projections in this plan). For
`WidgetScrollPane`, the `w` / `h` reported to the parent is the
*viewport* extent, not the inner content extent — clients of the
canvas see only the visible box.

This prerequisite is non-trivial but it is the same thing that would
have to happen for any cross-layer measurement; it's not specific to
this plan.

---

## Reactivity flow

For `HorizontalLayout`, the dependency graph after `projection_print`
returns:

```
each child's content (text, etc.)
  └→ child[i].w / .h         (set by child projection)
       ├→ outer_h            (max of all h)
       │    └→ each child_y  (depends on h, outer_h, align)
       ├→ outer_w            (sum of all w + gaps)
       └→ child_x[j]         (sum of preceding w + gaps), for j > i
            └→ wrapped canvas's x
       └→ wrapped canvas's y
            └→ renderer
```

A label's text edit invalidates `child[i].w`, which invalidates
`outer_w`, `child_x[j]` for `j > i`, and possibly `outer_h` and every
`child_y` if the height changed. The renderer pulls and recomputes
exactly those. The layout itself is never re-projected.

Adding or removing a child *does* re-project the layout: the
`children::CellVector` structural cell invalidates and the projection
re-runs, producing a fresh set of wrapper canvases and placement
cells. This is correct and standard — it's the same thing the
widget-layout plan ([widget-layout.md](widget-layout.md)) calls
"rebuild on structural change."

---

## Selection / reference / event mapping

All four layouts follow the same uniform pattern, since they all have
a single `children::CellVector` field:

- `map_reference_forward`: a `ConcreteReferencePath` whose head is
  `FieldReference("children")` followed by `RangeReference(i)`
  routes to `child_iomaps[i+1]`'s forward.
- `map_reference_backward`: symmetric.
- `projection_read`: mouse events route to the child whose wrapper
  canvas's hit-test succeeds — use `_route_click_to_children` and
  `_route_scroll_to_children` from [WidgetToGraphics.jl:243-263](../../program/src/projection/primitive/WidgetToGraphics.jl#L243-L263)
  (or copies adapted to live in `LayoutToGraphicsModule`).

The `child_iomaps` triples carry `(child_x[i], child_y[i], cim)` —
the helpers already expect `(ox, oy, cim)` with `ox`/`oy` as integers,
so they need a small tweak to read from `Cell{Int32}` instead, or the
plan supplies wrappers that snapshot the cells at routing time.

---

## Implementation Steps

### Step 1 — Populate `w` / `h` on existing canvases

- For each leaf projection in [WidgetToGraphics.jl](../../program/src/projection/primitive/WidgetToGraphics.jl)
  (`WidgetLabel`, `WidgetText`, `WidgetCheckbox`, `WidgetButton`,
  `WidgetTooltip`, `WidgetMenuItem`, `WidgetScrollBar`), thread the
  already-computed `(cw, ch)` or `(bw, bh)` through to the
  `GraphicsCanvas` constructor.
- For container widgets, change the output canvas's `w` / `h` to
  computed cells reading from the wrapped children's geometry.
- For text/syntax/primitive projections, same: compute output extent
  and write it.
- Add a `canvas_bounds(canvas)` helper as a fallback for callers that
  need it without modifying upstream.
- Tests: assert that every `…ToGraphicsCanvas` output's `w` / `h` cell
  matches the visual extent.

### Step 2 — `LayoutModule`

- New file `program/src/document/Layout.jl` defining the four
  document types via `@document`.
- Convenience constructors with sensible defaults
  (`vertical_align=:top`, `gap=0`, etc.).
- Register the module in [Projectured.jl](../../program/src/Projectured.jl).

### Step 3 — `LayoutToGraphicsModule`

- New file `program/src/projection/primitive/LayoutToGraphics.jl`
  defining the four projections.
- Implement `compute_placement` per layout type.
- Implement `map_reference_forward` / `map_reference_backward` /
  `projection_read` per layout type. The routing helpers may need a
  cell-aware variant; factor as needed.

### Step 4 — Shared cursor helper (optional but recommended)

If `HorizontalLayout`, `VerticalLayout`, and the per-line case in
`FlowLayout` all want the same "cumulative offsets with gap" math,
extract it as:

```julia
cumulative_offsets(extents::Vector{Cell}, gap::Cell) -> Vector{Cell{Int}}
```

— the same shape as the `cumulative_offset` proposed in
[widget-layout.md](widget-layout.md). If the widget plan also lands,
share the helper. If not, ship a layout-local copy.

### Step 5 — Test cases

For each layout type:

- **Trivial:** one child; outer extent equals child extent.
- **Alignment:** three children of differing heights/widths; assert
  cross-axis offset per alignment mode.
- **Gap:** two children with non-zero gap; assert positions.
- **Reflow:** edit the content cell of one child to change its size;
  assert that exactly the cells downstream of that child's `w`/`h`
  invalidate via `perf_counters()`.
- **Structural:** push/pop a child; assert the projection re-runs and
  produces correct geometry.
- **Layout-specific:**
  - `GridLayout` with a non-full last row.
  - `FlowLayout` that wraps to 2 lines, then changes `max_width` so
    it wraps to 3 lines.

### Step 6 — Example

Add a single example under [example/src/](../../example/src/) that
nests all four layouts — e.g. a `VerticalLayout` containing a
`HorizontalLayout` of widget labels, a `GridLayout` of buttons, and a
`FlowLayout` of tags. Exercises composition with widgets and with
each other.

---

## What is intentionally NOT here

- **No widget integration of these types.** A `WidgetShell.content`
  can be a `HorizontalLayout` without any glue, because the shell
  already projects `content` through `recursion`. Layouts are
  consumers of projections, not widget subtypes.
- **No measure/arrange protocol.** Recurse-then-measure is the
  protocol; child canvases publish their intrinsic size via cells,
  parents read it. No separate measure pass.
- **No min/max child constraints.** A layout takes children at their
  intrinsic size. Constraining a child is the child's job (its own
  document or projection clamps).
- **No stretch policies.** A child is exactly as wide/tall as its
  canvas's `w`/`h` cells say. If you want stretch-to-parent, use the
  widget layer's `wire_split_h!` / `wire_split_v!` instead (see
  [widget-layout.md](widget-layout.md)).
- **No baseline alignment.** Vertical alignment is by box edges only.
- **No RTL / vertical-text reading order.**
- **No virtualization.** All children are projected. A long list
  goes through every child every print (modulo the reactive engine
  not pulling invariants).

---

## Limitations

### Recurse-before-measure means projection runs once per child per layout pass

The projection visits every child to obtain its canvas, then reads
`w` / `h`. There is no "measure without projecting" shortcut. For
expensive child projections, the cost is paid once per layout
projection invocation — which happens only when the layout's
structural cell invalidates. Subsequent geometry-only changes (text
edits inside a child) don't re-project the layout, just invalidate
the relevant computed cells. So the cost is bounded to structural
churn, not editing.

### Children must produce a `GraphicsCanvas`

The recursion's eventual output for each child must be a
`GraphicsCanvas`. A child whose projection emits e.g. a `WidgetText`
that is later projected to a canvas works fine (the recursion
composes); a child whose projection emits something else doesn't
compose. In practice every backend-bound projection ends at a canvas,
so this is rarely binding — but a layout whose children are a
mixture of "already projected to canvas" and "still at widget level"
needs the widget-to-graphics layer threaded through the recursion the
layout is invoked with.

### Reading `w`/`h` only works if upstream projections populated them

Step 1 ("populate w/h on existing canvases") is a prerequisite for
this entire plan. Until it's done, layouts will see `w = h = 0` and
collapse to zero extent. The `canvas_bounds(canvas)` fallback exists
but is O(elements) per measure, paid each time the dependency graph
pulls.

### Wrapper canvas allocation per child

Each child gets a wrapper `GraphicsCanvas` with computed `x`/`y`
cells. For a 1000-element flow layout that's 1000 wrappers and ~4
extra cells each. Cheap individually; if the layout is rebuilt
frequently (structural churn), allocation pressure is real.
Virtualization is out of scope.

### `GridLayout.columns` and `FlowLayout.max_width` aren't smoothly reactive in v1

If `columns` or `max_width` is a primitive cell that changes at
runtime, the number of allocated row/column extent cells doesn't
change with it — the projection pre-allocated `max_cols_estimate`
or `max_lines_estimate` cells. Edge cases (column count growing past
the estimate) require re-projecting. Acceptable for typical use
(static grid dimensions, occasional flow re-wrap on resize); not
acceptable if grid dimensions thrash. The fix is to re-run the
projection on dimension change, which the cell system does
automatically if `columns`/`max_width` is the structural input.

### Cell graph cost on flow wrap recomputation

`FlowLayout.line_plan` is one cell that reads every child's `w`. A
single child's width change invalidates `line_plan`, which
invalidates every line height, every line y-offset, and every child
y. This is correct (wrapping is non-local) but it's the most
expensive layout reactively. Width changes inside a flow effectively
re-do all placement math; only the per-child *projection* output
stays cached.

### No incremental support for "insert child at position i"

Inserting into `children::CellVector` invalidates the layout's
structural cell, which re-runs the projection from scratch — fresh
recursion on every child. The reactive cell system doesn't yet
distinguish "structural change at index i" from "structural change in
general." A high-frequency insert/delete pattern would benefit from
finer-grained structural tracking; not in scope.

### Cross-axis cell graph is denser than along-axis

Along the main axis, child `j`'s position depends on children
`1..j-1`. Along the cross axis, *every* child's position depends on
the max over *all* children. So in a layout of N children, the main
axis has O(N²) dependency edges (partial sums) but the cross axis
has O(N) edges sharing one `outer_h`/`row_h` cell. The N² shape is
the natural cost of "child position depends on earlier widths"; it
can be reduced by chaining (each `child_x[i+1]` reads `child_x[i] +
ccs[i].w[]`) for an O(N)-edge graph at the cost of deeper
invalidation chains. Pick chaining over partial sums for `N > ~50`.

### No layout transitions / animation

Position cells either hold a value or don't. Animating a child from
one row to another is not a primitive operation. A separate layer
would tween between two layouts; not in scope.

---

## Open Questions

- **Should `columns` (Grid) and `max_width` (Flow) be `Cell{Int}` or
  plain `Int`?** Plain `Int` is simpler; `Cell{Int}` allows runtime
  re-flow without re-projecting the layout (the placement cells
  pick the change up). Probably `Cell{Int}` for both, with the
  pre-allocation upper bounds from Limitations.
- **Should layouts have a `position` / `size` of their own?** The
  plan makes them intrinsic only — a layout's outer canvas extent is
  whatever its children require. If a layout needs to be *placed*
  inside a parent, the parent (a widget split pane, another layout)
  positions it via the wrapper-canvas pattern. If a layout needs to
  be *bounded* (clip overflow), wrap it in a `WidgetScrollPane`.
  Worth confirming this is sufficient before adding `position` /
  `size` fields.
- **Should `GridLayout` support per-cell sizing overrides?** v1 picks
  "uniform by column / by row." A future extension could allow a
  `row_heights::CellVector{Int}` / `col_widths::CellVector{Int}`
  override; defer.
- **Should `FlowLayout` justify lines?** "Distribute leftover space
  between items on a line" (CSS `justify-content: space-between`)
  is appealing. Skipped for v1; horizontal alignment is per-line
  via `horizontal_align`. Adding a `:justify` value to that field
  later is non-breaking.
- **Single `LayoutModule` vs. four modules?** One module is simpler
  and matches `WidgetModule`'s precedent of holding many related
  types together.
- **Should the routing helpers in [WidgetToGraphics.jl:243-263](../../program/src/projection/primitive/WidgetToGraphics.jl#L243-L263)
  be promoted to a common location?** They'll be wanted in every
  `ChildrenIoMap`-based projection. The `LayoutToGraphics` module
  is a good moment to factor them out.

---

## Relationship to Existing Architecture

| Concept | Current | With layout documents |
|---------|---------|------------------------|
| How to lay out a row of widgets | `WidgetToolbar` (toolbar-specific) or `WidgetComposite` (no layout, manual positions) | `HorizontalLayout` of widgets |
| How to wrap text-like items | Not supported | `FlowLayout` |
| How to grid widgets | Not supported | `GridLayout` |
| Where layout lives | Inside widget projections that walk children | A separate document layer; widget projections only handle widget-specific rendering |
| Child intrinsic size | Mostly implicit; `WidgetToolbar` re-measures widget content directly | Read from `child_canvas.w[]` / `child_canvas.h[]`, populated by upstream projections |
| New projection types | — | Four small `…ToGraphicsCanvas` projections, one per layout type, plus `compute_placement` per type |
| Reactivity of child re-size | Limited; many widgets snapshot extents during print | Full: every position derives from child `w`/`h` cells; edit → ripple |
| Composition with widgets | Widgets contain widgets only | Widgets contain layouts contain widgets contain layouts (any depth) |

The change is additive on the document side (one new module with
four types) and on the projection side (one new module with four
projections). The only upstream change is the Step 1 prerequisite:
existing `…ToGraphicsCanvas` projections must start populating their
output's `w` / `h` cells. That change is small per projection but
spread across the codebase, and it's the natural prerequisite for
any cross-projection measurement — not unique to this plan.
