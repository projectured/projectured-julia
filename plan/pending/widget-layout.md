# Layout Allocation via Layout Documents

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

## Summary

ProjecturEd already has intrinsic layout documents — `HorizontalLayout`,
`VerticalLayout`, `GridLayout`, `FlowLayout` (see
[layout-documents.md](../done/layout-documents.md)) — that stack children
at their *natural* sizes by recursing first and then reading each child
canvas's `w`/`h`. They cannot yet do *extrinsic* layout: split a fixed
parent extent (a window, a pane) across children, or make a child *fill
remaining space*. Today that gap is filled by widget-specific
positioning — `WidgetSplitPane` walks a `sizes::CellVector` and never
tells a child how big its slot is, so a 1600-wide `WidgetScrollPane` in a
200-wide slot still renders at 1600.

This plan extends the existing layout documents with extrinsic
allocation, built on two ideas:

1. A small **`LayoutConstraint`** wrapper document carries the per-child
   degrees of freedom (`min` / `preferred` / `max` / `weight`, per axis)
   so that widgets and canvases stay *pure intrinsic-size* types — no
   layout policy pollutes them.
2. A layout reads the **available space for itself** from its
   [`ProjectionContext`](../tentative/projection-context.md), runs a
   one-pass allocation over its children's constraints, and passes each
   child's resolved extent *down* to that child through the same context.

The two directions never collide: **intrinsic size flows up** through
`canvas.w`/`.h`, **available size flows down** through the context. The
decision is **per axis** — a layout given an available *width* but no
available *height* allocates horizontally and stacks vertically by
content (exactly what word wrap needs).

There is **no widget-side wiring**: the previous `wire_split_h!` /
`wire_split_v!` helpers and the practice of writing allocated sizes onto
widget `size` cells are **dropped**. `WidgetSplitPane` becomes a
constrained `HorizontalLayout` / `VerticalLayout`.

---

## Why this shape

- **Reuse the layout layer that already exists.** The intrinsic layout
  documents already recurse, measure children, and emit a positioned
  canvas. Extrinsic allocation is the same machinery with one extra
  input (available space) and one extra output (per-child available
  space). No second layout system.
- **Keep documents pure.** A widget's `size` and a canvas's `w`/`h`
  always mean *intrinsic* size. Layout policy lives in a separate
  `LayoutConstraint` document, so `WidgetButton` / `WidgetLabel` / etc.
  never grow layout fields, and a shared child can carry different
  policies at different graph positions.
- **One direction each.** Available space flows strictly *down* (context);
  intrinsic size flows strictly *up* (`canvas.w`/`.h`). Nothing is ever
  written back onto a child's intrinsic-size cell, so there is no
  print-time side effect and no wiring-safety footgun.
- **Incremental for free.** A window resize writes one root cell; the
  allocation cells and the per-child available cells downstream of it
  invalidate; the next print pulls the re-allocated, re-wrapped result.
  No projection re-runs for a pure geometry change.
- **Dynamic tree shape works for free.** Add a child → the layout
  projection re-runs → a fresh allocation comes out. Same
  rebuild-on-structural-change story the projection system already gives.

---

## Two channels: intrinsic up, available down

Layout needs two opposite-flowing channels, and they must stay distinct:

| Channel | Direction | Carrier | Meaning |
|---|---|---|---|
| **Intrinsic size** | child → parent (up) | `GraphicsCanvas.w`/`.h`, `WidgetXxx.size` | the content's *natural* size |
| **Available size** | parent → child (down) | `ProjectionContext` property | the space the parent *allocated* |

Intrinsic-size cells are **never overwritten** with an allocated value.
The allocation a layout computes for a child is pushed *down* to that
child as a context property (`:available_width` / `:available_height`),
never written onto the child's `size` or `canvas.w`/`.h`. The downward
channel is owned by the
[`ProjectionContext`](../tentative/projection-context.md) plan; this plan
owns the *policy* (the `LayoutConstraint` document) and the *allocation*
(the one-pass algorithm a layout runs).

Because the channels are independent per axis, a layout can be extrinsic
on one axis and intrinsic on the other. Word wrap is the canonical case:
**width down** (the layout hands the child its allocated width), **height
up** (the child wraps to that width and reports the resulting height via
`canvas.h`). The reactive graph *is* the two-pass measure — no explicit
measure/arrange phase.

## Layout constraints: the `LayoutConstraint` document

Per-child layout policy lives in a dedicated wrapper document, so it
travels *with* the child in the document graph and keeps every other
document free of layout fields:

```julia
@document struct LayoutConstraint <: Document
    child::Document        # wrapped document (widget, layout, anything)
    min_width::Cell        # Cell{Int};     default 0
    preferred_width::Cell  # Cell{Int};     default = child's intrinsic w
    max_width::Cell        # Cell{Int};     default typemax
    weight_width::Cell     # Cell{Float64}; default 0.0
    min_height::Cell
    preferred_height::Cell
    max_height::Cell
    weight_height::Cell
    selection::Reference
end
```

**The point of a separate document is to keep every other document pure.**
A widget's `size` and a `GraphicsCanvas`'s `w`/`h` always mean *intrinsic*
size — the natural size of the content. They never carry layout policy.
`min` / `preferred` / `max` / `weight` are layout concerns, so they live
in the wrapper, not on `WidgetButton`, `WidgetLabel`, or the canvas. This
also respects the DAG: the same child can be wrapped by two different
`LayoutConstraint`s in two places, or wrapped in one place and bare in
another.

Each of the four is a `Cell`, so it can be a calculation —
`preferred_width = Cell(() -> child_canvas.w[])` defers to the child's
intrinsic width, and an explicit value overrides it. A bare (unwrapped)
child behaves as `{min:0, preferred:intrinsic, max:∞, weight:0}`, so
wrapping is opt-in and adds no boilerplate for the common case.

The four degrees of freedom express the familiar sizing policies:

| Policy | min | max | preferred | weight |
|---|---|---|---|---|
| `FixedSize(200)` | 200 | 200 | 200 | 0 |
| `FractionSize(0.3)` | 0 | ∞ | `0.3 * parent` | 0 |
| `FlexSize(1.0)` | 0 | ∞ | 0 | 1.0 |
| intrinsic | `content_w` | `content_w` | `content_w` | 0 |
| bounded flex | 100 | 400 | 0 | 1.0 |

## The allocation algorithm (per axis, one pass)

A layout runs the allocation **independently per axis**, on whichever
axis it received available space for. For a main axis of extent
`available` over children with inter-child `gap`:

1. **Seed.** Give every child its `preferred`, clamped to `[min, max]`.
2. **Slack.** `remaining = available - Σ actualᵢ - gaps`.
3. **Grow** (`remaining > 0`): distribute to children with `weight > 0`
   in proportion to weight, each capped at its `max`. Leftover (all
   maxed out) is dropped — the layout under-fills.
4. **Shrink** (`remaining < 0`): take from children with `weight > 0`
   in proportion to weight, each floored at its `min`. If still over
   budget (all minned out), overflow is allowed — clipping is the
   parent's concern (e.g. a scroll pane).

The output is one `actual` extent **cell** per child. Each step reads
cells (`available`, the children's `min` / `preferred` / `max` /
`weight`), so `actual` is itself a computed `Cell{Int}` — a change to the
available extent or any constraint re-runs only the allocation, not the
projection.

**Cross axis.** On an axis the layout did *not* receive available space
for, it falls back to the existing intrinsic behaviour (sum of preferred
for the stacking axis, max of preferred for the cross axis) — the
already-implemented layout-document math.

**The invariant.** `actual` is **never** written back onto a child's
intrinsic `size` / `w` / `h`. It is the layout's placement value, and —
for children that must *adapt* to it (word wrap, scroll viewport) — it is
handed to the child as `:available_width` / `:available_height` on the
[context](../tentative/projection-context.md), never onto the document.

## How a layout chooses intrinsic vs. extrinsic

The choice is **per axis** and driven entirely by the context — there is
no mode flag on the document:

```julia
function projection_print(p::HorizontalLayoutToGraphicsCanvas, doc, recursion, ctx)
    avail_w = get_property(ctx, :available_width,  nothing)  # Cell{Int} or nothing
    avail_h = get_property(ctx, :available_height, nothing)

    # 1. Recurse first (unchanged): project each child to get its canvas,
    #    its intrinsic w/h, and its LayoutConstraint (if wrapped).
    children = collect_children(doc, recursion, ctx)

    # 2. Main axis (x for a horizontal layout):
    actual_w = avail_w === nothing ?
        intrinsic_main(children) :              # sum of preferred — current behaviour
        allocate(avail_w, children, doc.gap)    # one-pass allocation

    # 3. Cross axis (y): intrinsic unless the layout got an available height.
    ...
end
```

- `avail_* === nothing` → the layout is intrinsic on that axis: it uses
  the existing sum/max-of-preferred math from the layout-documents plan.
- `avail_*` present → the layout allocates that extent across children
  by their `LayoutConstraint`.

A bare child (not wrapped in `LayoutConstraint`) contributes
`{min 0, preferred = intrinsic, max ∞, weight 0}`, so an unconstrained
extrinsic layout pins each child to its intrinsic size and leaves any
slack unused — predictable and boilerplate-free.

## Passing available size down to children

After allocating, the layout hands each child its resolved extent on the
context when it recurses — as a **`Cell`**, so the child can wire its own
adaptive cells to it without re-projection:

```julia
for (i, child) in enumerate(children)
    child_ctx = child_context(ctx, FieldReference("children"), RangeReference(i))
    avail_w !== nothing && (child_ctx = with_property(child_ctx, :available_width,  actual_w[i]))
    avail_h !== nothing && (child_ctx = with_property(child_ctx, :available_height, actual_h[i]))
    cim = projection_print(recursion, child.doc, recursion, child_ctx)
    # position the returned canvas at the running offset (unchanged math)
end
```

The child reads `:available_width` if it cares (e.g. `TextToGraphics`
uses it as the wrap threshold) and reports its resulting height back up
via `canvas.h`, which the layout reads to place it on the cross axis.
A child that ignores the property renders intrinsically — no opt-in cost.

---

## Example: the workbench shell

Today the shell hardcodes split sizes
([WorkbenchToWidget.jl:106-121](../../program/src/projection/primitive/WorkbenchToWidget.jl#L106-L121)).
Under this plan the shell's content is a tree of layout documents whose
children are wrapped in `LayoutConstraint` only where a non-default
policy is needed:

```julia
function projection_print(::WorkbenchWorkbenchToWidgetShell, w, recursion, ctx)
    # Right column: editor fills, info pane fixed 200 tall.
    right = VerticalLayout([
        LayoutConstraint(w.editing_page;     weight_height = Cell(1.0)),          # flex
        LayoutConstraint(w.information_page; min_height = Cell(200),
                                             max_height = Cell(200)),             # fixed 200
    ]; gap = 3)

    # Top level: navigator fixed 200 wide, right column fills.
    main = HorizontalLayout([
        LayoutConstraint(w.navigation_page; min_width = Cell(200), max_width = Cell(200)),
        LayoutConstraint(right;             weight_width = Cell(1.0)),
    ]; gap = 3)

    shell = WidgetShell(main; border = _PAD5)

    # Seed the root available size from the window (a fixed size today;
    # WindowDocument.width/height once multiple-windows.md lands).
    root_ctx = with_property(with_property(ctx,
                   :available_width,  shell_w_cell),     # Cell(1280) today
                   :available_height, shell_h_cell)      # Cell(720)  today
    projection_print(recursion, shell, recursion, root_ctx)
end
```

- A 30% / 70% horizontal split is `weight_width = Cell(0.3)` /
  `Cell(0.7)` on the two children (or `min = max = fraction` for hard
  fractions).
- `WidgetSplitPane` is gone — `main` and `right` *are* the splits.
- Selection mapping routes through the layout's `children[i]` reference,
  exactly as the already-implemented layout projections do — no special
  case for splits.

---

## Reactivity and propagation

All writes happen on the *intrinsic* (up) and *available* (down) cells;
the layout never mutates a child's size. The dependency graph for one
extrinsic axis:

```
window_w (write)
  └→ root :available_width cell
       └→ layout allocate() → actual_w[i]      (one cell per child)
            └→ child's :available_width         (context cell handed down)
                 └→ child wrap_w → [re-wrap] → child canvas.h   (flows back up)
                      └→ layout cross-axis placement → outer canvas
```

A window resize writes one cell. The allocation cells, the per-child
available cells, and any child cell that read them (wrap width, scroll
viewport) invalidate; their dependents (re-wrapped `canvas.h`, the
layout's placement cells) invalidate in turn. The next print pulls only
the dirty subtree. No `projection_print` re-runs for a pure geometry
change — structural changes (adding/removing a child) still re-run the
layout projection, as in the layout-documents plan.

Verify with `perf_counters()`
([reactive-cells.md:58-63](../../guide/reactive-cells.md#L58-L63)) that a
resize invalidates only the size-dependent cells, not the whole document.

---

## Replacing `WidgetSplitPane`

`WidgetSplitPane` exists only to position a row/column of children at
fixed offsets. A constrained `HorizontalLayout` / `VerticalLayout` does
the same thing and more (it can flex, fill, and word-wrap its children),
so the split pane is replaced rather than extended.

- **Static splits** → a `HorizontalLayout` / `VerticalLayout` whose
  children are `LayoutConstraint`-wrapped with the desired weights or
  fixed extents.
- **Draggable splitter** → an operation, not a wiring call. Store the
  draggable slot's `weight_width` (or `preferred_width`) as a writable
  `Cell` on its `LayoutConstraint`; a `ResizeSplitOperation` writes the
  new value; the allocation cells downstream pick it up and the geometry
  re-flows. No projection re-run, no `setfn!` into a live tree.
- **Splitter visuals** (the draggable bar between slots) → the layout
  projection emits a thin `GraphicsRect` in each inter-child `gap`,
  computed from the neighbouring children's placement cells.

Because the split is now a layout document, it composes uniformly: a
slot can hold another layout, a widget, a scroll pane, or any document
with a `…ToGraphicsCanvas` projection — the same composition the
layout-documents plan already provides.

---

## What changes (and what doesn't)

### New: the `LayoutConstraint` document

A new document type (above) plus a trivial projection: recurse into
`child`, pass the context through unchanged, forward the child's canvas
as its own output. The constraint values are read by the *parent*
layout, not by the wrapper's own projection. Lives in `LayoutModule`
alongside the existing layout documents.

### Changed: the four layout projections read/write the context

`HorizontalLayoutToGraphicsCanvas`, `VerticalLayoutToGraphicsCanvas`,
`GridLayoutToGraphicsCanvas`, `FlowLayoutToGraphicsCanvas` each gain:
per-axis reading of `:available_*` from their own context, the one-pass
allocation when present, and handing each child its `actual` extent on
the child's context. With no `:available_*` present they behave exactly
as today (pure intrinsic).

### `WidgetScrollPane`

A scroll pane gives its content an *unbounded* main axis but a *bounded*
cross axis. So when it recurses into its content it sets only the
cross-axis `:available_*` (the viewport extent) and leaves the scroll
axis unset (intrinsic). The content's intrinsic extent on the scroll
axis becomes the scrollable surface; the pane clips to its own `size`.
No new field is required — the asymmetry is just which `:available_*` it
passes.

### Unchanged

`WidgetShell`, `WidgetButton`, `WidgetLabel`, and every other widget keep
their current fields and projections. They gain nothing layout-specific;
their `size` stays intrinsic. `WidgetSplitPane` is removed (see above).

---

## Implementation Steps

### Step 1 — `LayoutConstraint` document

- Add `LayoutConstraint` to `LayoutModule` (fields above), with
  convenience constructors defaulting each field (`min=0`,
  `preferred = Cell(() -> child_canvas.w[])` resolved lazily,
  `max=typemax`, `weight=0.0`).
- A trivial `LayoutConstraintToGraphicsCanvas` projection that forwards
  the child's canvas and context unchanged.

### Step 2 — The allocation helper

- A pure `allocate(available::Cell, children, gap) -> Vector{Cell{Int}}`
  implementing the one-pass algorithm, returning one `actual` cell per
  child. Reads each child's `min` / `preferred` / `max` / `weight`
  (defaults for bare children).
- Unit-test directly: given an available-extent cell and a set of
  constraints, assert each `actual` cell; mutate the available cell and
  re-read; mutate a weight and re-read.

### Step 3 — Per-axis context in the layout projections

- In each `…LayoutToGraphicsCanvas`, read `:available_width` /
  `:available_height` from the context; allocate on present axes, fall
  back to intrinsic on absent axes.
- Hand each child its `actual` extent on the child's context before
  recursing. Position the returned canvases with the existing offset
  math.
- Confirm the intrinsic path is unchanged when no `:available_*` is
  present (existing layout-document tests must still pass).

### Step 4 — `WidgetScrollPane` passes cross-axis available only

- When the scroll pane recurses into its content, set the cross-axis
  `:available_*` to the viewport extent and leave the scroll axis unset.
- No structural change to the widget.

### Step 5 — Seed the root available size

- The shell projection seeds `:available_width` / `:available_height`
  from the window size (fixed today; `WindowDocument.width` / `.height`
  once multiple-windows lands) before projecting its content.

### Step 6 — Replace `WidgetSplitPane` in `WorkbenchToWidget`

- Rebuild the workbench content as constrained `HorizontalLayout` /
  `VerticalLayout` as in the example, picking weights / fixed extents
  that reproduce today's pixels for the first frame.
- Remove `WidgetSplitPane` and its projection once nothing references it.
- Confirm selection / reader mapping resolves through the layouts'
  `children[i]` references.

### Step 7 — Splitter drag (optional)

- Make a draggable slot's `weight_*` (or `preferred_*`) a writable cell
  on its `LayoutConstraint`. A `ResizeSplitOperation` writes it; the
  allocation cells re-flow. The layout projection emits the splitter
  rect in the gap and routes hits to the operation.

### Step 8 — Tests

- Allocator tests (Step 2).
- Word-wrap test: a text child inside a width-constrained horizontal
  layout re-wraps when the available width changes; assert via
  `perf_counters()` that only the wrap/height cells invalidate.
- A fixed + flex split that reproduces the workbench; mutate the root
  available size and assert child extents.
- Nested fractions (30/70 inside 70/30).
- Structural: add a child → layout re-projects → fresh allocation.

---

## What is intentionally NOT here

- **No new layout *primitive*.** Allocation rides on the four existing
  layout documents; this plan adds policy (`LayoutConstraint`) and the
  allocation pass, not new container types.
- **No explicit measure/arrange two-pass.** Intrinsic-up + available-down
  over reactive cells *is* the two pass; there is no separate measure
  phase.
- **No writing allocated size onto widgets.** The dropped wiring approach
  did this; the invariant here is that intrinsic-size cells are
  read-only to layout.
- **No content-aware main-axis preferred that depends on the
  allocation.** `preferred` on the main axis must be intrinsic (see the
  cycle caveat below).
- **No animation.** Cells either hold a value or don't.

---

## Limitations

### Fractions don't compose multiplicatively across nesting

A `weight`/fraction reads its *parent's* allocated extent, not its
grandparent's. Two `0.5`-weighted grandchildren inside a `0.30` slot of
a 1280-wide root get half of 384, not half of 1280. Natural, but catches
people used to global percentage schemes.

### Pixel rounding can leave 1px asymmetry

Weighted shares are floats; per-child rounding can sum to ±1px of the
available extent. Pick a residual rule (e.g. the last weighted child
absorbs the remainder). Total stays exact; adjacent slots can differ by
a pixel under adversarial sizes.

### Overflow under shrink is clipping, not graceful

When `available` is below the sum of `min`s, children stay at `min` and
the layout overflows its box. Containing that is the parent's job (a
scroll pane, or a larger window). There is no automatic squeeze below
`min`.

### Main-axis `preferred` must stay intrinsic (cycle risk)

If a child's main-axis `preferred` reads the *available* extent the
layout is about to allocate from it, the dependency graph cycles. For
text, "preferred width = natural single-line width" is safe. Keep that
rule for any content that participates in main-axis allocation.
Cross-axis preferred depending on the allocated main axis (e.g. wrapped
height depending on width) is fine — that's the intended up-channel.

### Cell graph growth

Each constrained child adds a handful of cells (the constraint fields +
`actual`). A tree with N nodes adds O(N) cells; invalidation walks scale
with dependent-set size. Measure with `perf_counters()` for very deep
nesting.

### Resize during a print is best-effort

The main loop runs read → eval → print. A resize that fires between read
and print uses whichever cell values were live when the print pulled.
The next frame catches up — invisible at 60fps, but can briefly desync a
single-frame screenshot.

### Structural change re-projects the layout

Adding/removing a child re-runs the layout projection (fresh allocation,
fresh cells) — correct and standard, but not incremental at the
structural level. Only geometry changes (resize, drag) are incremental.

---

## Open Questions

- **Where does `LayoutConstraint` live — `LayoutModule` or its own
  module?** Probably `LayoutModule`, next to the layouts that consume it.
- **Per-axis `weight` vs. a single value?** Per-axis (`weight_width` /
  `weight_height`) lets a child flex horizontally but not vertically; a
  single value is simpler. Plan picks per-axis.
- **`preferred` default = intrinsic reads the child canvas.** The
  wrapper's `preferred` cell closes over the child's projected canvas.
  Confirm the recurse-first ordering makes that canvas available before
  the parent reads `preferred`.
- **Grid / Flow under available space.** This plan describes the
  row/column case precisely; how `GridLayout` distributes available
  width across columns (and `FlowLayout` across its fixed `max_width`)
  needs its own short spec.
- **Full `ProjectionContext` migration first?** Yes (decided): the
  `:available_*` channel rides on the finished context. See
  [projection-context.md](../tentative/projection-context.md).

---

## Relationship to Existing Architecture

| Concept | Current | With layout allocation |
|---------|---------|------------------------|
| Layout layer | Intrinsic layout documents (positioning only) | Same documents, now also extrinsic via context-supplied available space |
| Layout policy | None (or hardcoded `sizes` on `WidgetSplitPane`) | `LayoutConstraint` wrapper document (min/preferred/max/weight, per axis) |
| Widget `size` / canvas `w`/`h` | Mixed meaning | Strictly *intrinsic*; never overwritten by layout |
| Available space | Not represented | Flows down via `ProjectionContext` `:available_*` cells |
| `WidgetSplitPane` | Walks a `sizes` cursor; children don't know their slot | Replaced by a constrained `HorizontalLayout` / `VerticalLayout` |
| Window resize → layout | Not propagated | One root-cell write → allocation cells → child available cells → re-flow |
| Splitter drag | — | Operation writes a `weight`/`preferred` cell on a `LayoutConstraint` |
| New projection types | — | `LayoutConstraintToGraphicsCanvas` (trivial forwarder); the four layouts gain context handling |

This plan is additive on the document side (one new `LayoutConstraint`
type) and a focused change on the projection side (the four layout
projections read/write the context). Its one hard prerequisite is the
`ProjectionContext` migration that carries the downward available-size
channel.
