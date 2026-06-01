# Widget Layout via Reactive Cells

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

## Summary

Today every widget that has a `position::Point2D` and `size::Point2D`
carries those as `Cell`s, but they're written once at construction time
with hardcoded numbers (see [WorkbenchToWidget.jl:111-216](../../program/src/projection/primitive/WorkbenchToWidget.jl#L111-L216)).
`WidgetSplitPane` doesn't have its own `size`; it walks a cursor through
a `sizes::CellVector` of slot widths and stacks children at those
offsets, never telling the children how big their slot is. So a
1600-wide `WidgetScrollPane` inside a 200-wide split slot still renders
at 1600.

This plan introduces a small set of layout helpers in `WidgetModule`
(`compute_extents`, `cumulative_offset`, `wire_split_h!`, `wire_split_v!`)
and uses them **inline inside the projection that creates the widget
tree** — `WorkbenchWorkbenchToWidgetShell.projection_print` and friends.
Each helper wires the child's `position`/`size` cells as computed cells
reading from the parent's geometry. Because cells track dependencies
automatically, a single write to the root's size (window resize)
invalidates the transitive set of position/size cells, which in turn
invalidates the canvases that consumed them — incremental relayout
falls out of the existing reactive plumbing described in
[reactive-cells.md](../../guide/reactive-cells.md).

There is **no separate layout DSL**, no `LayoutSpec` value type, no
`splith`/`splitv` constructors. Layout is just inline `Cell(() -> ...)`
and `setfn!` calls inside the projection that already builds the widget
tree. The reactive system *is* the DSL.

---

## Why this shape

The projection system already re-runs `projection_print` when its input
invalidates and caches the output via the iomap. That mechanism is the
right place for "the widget tree gets rebuilt when something
structural changes." A separate construction-time DSL would have
duplicated that.

- **No new types.** `Cell(() -> shell_size.x[] - 200)` is what a "30%
  width minus 200" policy looks like. Helper functions encapsulate the
  arithmetic; values flow through `Cell`s.
- **No side effect during the *graphics* print.** The widget→graphics
  printer (the per-frame inner loop) stays purely read-only. The
  `setfn!` calls happen inside the upstream projection that *builds*
  the widget tree — and they're safe there because they target cells
  the same call just allocated, which have no downstream dependents at
  the moment of wiring. (See "The wiring safety invariant" below.)
- **Dynamic tree shape works for free.** Add a page to the workbench →
  the workbench-to-widget projection re-runs → a new pane comes out
  pre-wired. No external `layout!` call to remember.
- **One source of truth.** The same `projection_print` that allocates
  `WidgetSplitPane` chooses the slot policies and writes them into the
  children's geometry cells. There's no chance of `WidgetSplitPane.sizes`
  drifting from the child sizes — they're computed from the same input.
- **Selection / iomap mapping stays consistent.** The widget tree and
  its iomap are built in the same function, so slot reordering updates
  both at once.

---

## The helpers

A small module-internal API in `WidgetModule`. None of these are exported
as a user-facing DSL — they're tools for *projection authors*.

### Size policies

Plain immutable value types:

```julia
abstract type SizePolicy end
struct FixedSize   <: SizePolicy; px::Int       end   # exactly px pixels
struct FractionSize <: SizePolicy; r::Float64   end   # r ∈ [0,1] of the parent's extent on the split axis
struct FlexSize    <: SizePolicy; weight::Float64 end # default weight = 1.0
```

A projection that wants drag-to-resize stores a slot's policy in a
`Cell{SizePolicy}` so a `ResizeSplitOperation` can write into it; a
static layout passes plain `FixedSize(200)` values. `compute_extents`
accepts either a `Vector{SizePolicy}` or a `Vector{Cell{SizePolicy}}`
— in both cases its output is a `Vector{Cell{Int}}` and the dependency
graph naturally tracks whichever the caller chose.

### Allocator

```julia
"""
Given a Cell{Int} carrying the parent's extent on the split axis and a
list of slot policies + a fixed inter-slot gap, return one Cell{Int}
per slot holding that slot's allocated pixel extent. The returned cells
read `parent_extent` lazily, so the reactive engine invalidates only
the slot extents that actually depend on it.
"""
compute_extents(parent_extent::Cell, policies::Vector, gap::Int) -> Vector{Cell{Int}}

"""
Given a vector of slot extents and a fixed inter-slot gap, return one
Cell{Int} per slot holding that slot's pixel offset from the start of
the parent's content area.
"""
cumulative_offset(extents::Vector{Cell{Int}}, gap::Int) -> Vector{Cell{Int}}
```

Allocation order, all integer pixels:

1. `FixedSize` slots reserve their exact `px`.
2. `FractionSize` slots reserve `round(r * available_extent)` of the
   *full* parent extent (not what's left after Fixed).
3. `FlexSize` slots share whatever is left, in proportion to `weight`.
4. Overflow (Fixed+Fraction > parent) shrinks Flex first, then
   proportionally squeezes Fractions. Underflow remainder goes to the
   last Flex, or to the last Fraction if there's no Flex.

### Wirers

```julia
"""
Wire each child widget's position/size cells so they describe a row of
slots inside `parent_position` × `parent_size`. Children are laid out
along the x axis; each fills the parent's y extent. `gap` reserves
inter-slot pixels for splitter rects.

Safe to call only on children whose position/size cells have no
downstream dependents yet — i.e. children allocated in the same call
as this wiring. See "The wiring safety invariant".
"""
function wire_split_h!(parent_position::Point2D,
                       parent_size::Point2D,
                       children::Vector{<:WidgetDocument},
                       policies::Vector,
                       gap::Int=0)
    extents = compute_extents(getfield(parent_size, :x), policies, gap)
    offsets = cumulative_offset(extents, gap)
    for (i, child) in enumerate(children)
        setfn!(getfield(getfield(child, :position), :x),
               () -> parent_position.x[] + offsets[i][])
        setfn!(getfield(getfield(child, :position), :y),
               () -> parent_position.y[])
        setfn!(getfield(getfield(child, :size), :x),
               () -> extents[i][])
        setfn!(getfield(getfield(child, :size), :y),
               () -> parent_size.y[])
    end
end

wire_split_v!(...)  # symmetric, swapping x ↔ y
```

That's the whole "DSL". Two wirers, two allocator helpers, three
policy types. Everything else is ordinary Julia inside a
`projection_print`.

---

## Example: the workbench shell

Today's `WorkbenchWorkbenchToWidgetShell.projection_print` looks like
[WorkbenchToWidget.jl:106-121](../../program/src/projection/primitive/WorkbenchToWidget.jl#L106-L121):

```julia
function projection_print(::WorkbenchWorkbenchToWidgetShell, w, recursion, reference)
    nav_iomap  = _recurse(recursion, w.navigation_page,  …)
    edit_iomap = _recurse(recursion, w.editing_page,     …)
    info_iomap = _recurse(recursion, w.information_page, …)
    right_split = WidgetSplitPane(:vertical,
                                  WidgetDocument[edit_iomap.output, info_iomap.output];
                                  sizes=[800, 200])
    main_split  = WidgetSplitPane(:horizontal,
                                  WidgetDocument[nav_iomap.output, right_split];
                                  sizes=[200, 1000])
    shell = WidgetShell(main_split;
                        size=Point2D(1280, 720),
                        border=_PAD5)
    WorkbenchWorkbenchToWidgetShellIoMap(nothing, w, shell, nav_iomap, edit_iomap, info_iomap)
end
```

After this plan:

```julia
function projection_print(::WorkbenchWorkbenchToWidgetShell, w, recursion, reference)
    nav_iomap  = _recurse(recursion, w.navigation_page,  …)
    edit_iomap = _recurse(recursion, w.editing_page,     …)
    info_iomap = _recurse(recursion, w.information_page, …)

    shell = WidgetShell(nothing; size=Point2D(1280, 720), border=_PAD5)

    # Right column: editor on top (70%), info pane below (fixed 200).
    right_split = WidgetSplitPane(:vertical,
                                  WidgetDocument[edit_iomap.output, info_iomap.output])
    wire_split_v!(right_split.position, right_split.size,
                  [edit_iomap.output, info_iomap.output],
                  [FlexSize(1.0), FixedSize(200)],
                  3)  # 3px splitter gap

    # Top-level: navigator left (fixed 200), right column right (flex).
    main_split = WidgetSplitPane(:horizontal,
                                 WidgetDocument[nav_iomap.output, right_split])
    wire_split_h!(main_split.position, main_split.size,
                  [nav_iomap.output, right_split],
                  [FixedSize(200), FlexSize(1.0)],
                  3)

    # The main split fills the shell's content area.
    wire_split_h!(shell.position, shell.size,
                  [main_split],
                  [FlexSize(1.0)])

    shell.content = main_split

    WorkbenchWorkbenchToWidgetShellIoMap(nothing, w, shell, nav_iomap, edit_iomap, info_iomap)
end
```

A 30% / 70% horizontal split is one substitution — `FixedSize(200)`
becomes `FractionSize(0.30)`, `FlexSize(1.0)` becomes `FractionSize(0.70)`.

Selection mapping at [WorkbenchToWidget.jl:227-274](../../program/src/projection/primitive/WorkbenchToWidget.jl#L227-L274)
is unaffected: the shell still contains a `WidgetSplitPane` whose
`elements[1]` is the nav iomap output and `elements[2]` is the right
split.

---

## How sizes and positions actually propagate

`wire_split_h!` is the only place writes happen. Inside it:

```julia
extents[i] = Cell(() -> compute_slot_i_extent(parent_size.x[], policies, gap))
offsets[i] = Cell(() -> sum(extents[1..i-1]) + i*gap)

setfn!(child.position.x.cell, () -> parent_position.x[] + offsets[i][])
setfn!(child.size.x.cell,     () -> extents[i][])
```

The dependency graph after wiring (for one child):

```
parent_size.x  ─┐
                ├─→ extents[i] ─┬─→ offsets[i] ─→ child.position.x
                │               │
                │               └────────────────→ child.size.x
                │
parent_pos.x ───┼─────────────────────────────────→ child.position.x
```

A resize → write to `parent_size.x[]` → invalidates `extents[i]` and
`offsets[i]` → invalidates `child.position.x` and `child.size.x` →
invalidates whatever canvas read those cells. Recompute is pulled
lazily on the next print, exactly as documented in
[reactive-cells.md:46-55](../../guide/reactive-cells.md#L46-L55).

### Window-size propagation

The shell's `size::Point2D` is the root parent. Today it's a primitive
cell set at construction. Once the multiple-windows plan lands
([multiple-windows.md](multiple-windows.md)), `WindowDocument.width`
and `.height` describe the OS window, and the natural follow-up is:

```julia
shell_size_x = Cell(() -> window_doc.width[])
shell_size_y = Cell(() -> window_doc.height[])
shell = WidgetShell(...; size=Point2D(shell_size_x, shell_size_y))
```

A SDL resize → backend writes into `window_doc.width[]` → shell size
cells invalidate → split extents invalidate → child geometry
invalidates → next print redraws only the dirty subtrees.

No new mechanism is needed — the dependency graph the helpers build
is the propagation path.

---

## The wiring safety invariant

`setfn!` is documented as "switch this cell to a thunk; invalidate
every downstream dependent." If the cell being wired already has
dependents, those get invalidated immediately — a write that ripples.
That would be a real side effect during print.

The reason the helpers are safe is structural: each helper is called
on **children allocated in the same `projection_print` call**. At the
moment of `setfn!`, those cells have no downstream dependents yet —
the downstream graphics projection hasn't seen them. `setfn!`'s
invalidation walk visits an empty set. It's idempotent setup, not a
propagating mutation.

The rule for future projection authors:

> `wire_split_h!` / `wire_split_v!` may only be called on widgets
> constructed in the same `projection_print` invocation. Never reach
> into a long-lived widget tree from inside a printer and rewire it.

If a projection ever wants to mutate the wiring of an existing widget
(e.g. swap a slot's policy at runtime), the right tool is *not*
calling the wirer again — it's making the policy itself a
`Cell{SizePolicy}` and writing into that cell. The wirer's existing
extent thunks will pick the change up reactively.

A defensive runtime check ("error if `setfn!` would invalidate a
non-empty dependent set") could be added to the wirers themselves
during development; remove for production.

---

## What changes in the widget tree

### `WidgetSplitPane`

Needs `position::Point2D` and `size::Point2D` of its own. Today it has
neither — it has only orientation, elements, and `sizes`. Adding them
is the minimum structural change.

`sizes::CellVector` can either be kept as a redundant cache that the
wirer writes into (so `WidgetSplitPaneToGraphicsCanvas` keeps reading
it for splitter-bar placement) or removed in favour of having the
projection compute splitter positions from `position`/`size` and the
children's geometry. Start with "keep `sizes`, write to it from the
wirer for splitter visuals"; remove as a follow-up cleanup.

### `WidgetScrollPane`

Already has `position::Point2D` and `size::Point2D`. The wirer writes
into both for the pane itself.

If a projection wants to lay out content *inside* a scroll pane that
extends past the viewport, it needs an explicit "content surface"
geometry to wire children against — the viewport size won't do,
because that's what `Flex` would read and the content would never
exceed the viewport. Add one field:

```julia
content_size::Point2D   # extent of the scrollable content surface
```

Defaults to `size` (a computed cell mirroring the pane's own size) so
nothing changes for callers that don't need it. `WidgetScrollPaneToGraphicsCanvas`
keeps using `size` for viewport clipping and doesn't need to change.

### `WidgetShell`

No structural change. `size` already exists; the wirer treats it as a
root parent.

### Other compound widgets

`WidgetComposite`, `WidgetTitlePane`, `WidgetTabbedPane` are not in
scope. They can adopt the same pattern (and the same wirers) when a
caller needs it — none of them need it for the current workbench.

---

## Implementation Steps

### Step 1 — Add `position` and `size` to `WidgetSplitPane`

- Edit the `@document struct WidgetSplitPane` in
  [Widget.jl:554-566](../../program/src/document/Widget.jl#L554-L566)
  to include `position::Point2D` and `size::Point2D`.
- Update its constructor with default `Point2D(0,0)` for position and
  `Point2D(0,0)` for size (the wirer overrides both immediately).
- `WidgetSplitPaneToGraphicsCanvas.projection_print` doesn't need to
  read them yet; the existing cursor-walks-`sizes` logic still works
  unchanged in this step.

### Step 2 — `SizePolicy` and the allocator

- New file `program/src/document/WidgetLayout.jl` (or extend
  `Widget.jl`) defining `SizePolicy`, `FixedSize`, `FractionSize`,
  `FlexSize`, `compute_extents`, `cumulative_offset`.
- Unit-test the allocator directly: given a parent extent cell and
  a list of policies, assert each output cell holds the right pixel
  count; mutate the parent extent and re-read.

### Step 3 — Wirers

- `wire_split_h!`, `wire_split_v!` in the same module.
- Each calls `compute_extents` + `cumulative_offset` once, then loops
  over children calling four `setfn!`s per child.
- Optional debug check: assert each cell being wired has an empty
  dependent set at wire time.

### Step 4 — `WidgetScrollPane.content_size`

- Add the field; constructor defaults it to a computed cell that
  mirrors `size`.
- No change to `WidgetScrollPaneToGraphicsCanvas` needed.

### Step 5 — Convert `WorkbenchToWidget`

- Replace the hardcoded numbers in
  [WorkbenchToWidget.jl:106-216](../../program/src/projection/primitive/WorkbenchToWidget.jl#L106-L216)
  with `wire_split_h!` / `wire_split_v!` calls as shown in the
  example above.
- Pick policies that reproduce today's layout (`FixedSize(200)` /
  `FlexSize(1.0)` etc.) so the first frame is pixel-equivalent.
- Confirm `WorkbenchWorkbenchToWidgetShellIoMap`'s downstream
  consumers (selection, reader) still resolve correctly.

### Step 6 — Make the shell size reactive on window resize

- Today: shell `size` is primitive `Point2D(1280, 720)`. The backend
  can `setval!` into `shell.size.x` / `.y` on `SDL_WINDOWEVENT_RESIZED`.
- Once `WindowDocument` lands, swap the primitive cells for computed
  cells reading `window_doc.width` / `.height`.
- Verify with `perf_counters()` (see
  [reactive-cells.md:58-63](../../guide/reactive-cells.md#L58-L63))
  that a resize invalidates only the cells that depend on size, not
  the whole document.

### Step 7 — Splitter drag

- Define `ResizeSplitOperation(split::WidgetSplitPane, slot_index::Int, new_policy::SizePolicy)`.
- For a split that wants to be draggable, store its policies as
  `Cell{SizePolicy}` in the projection's iomap (so they survive across
  projection re-runs) and pass them to the wirer as cells.
- `WidgetSplitPaneToGraphicsCanvas.projection_read` recognises
  splitter-rect hits and emits the operation.
- The evaluator writes into the policy cell. The extent thunks pick
  it up; geometry invalidates; redraw.

### Step 8 — Optional cleanup: remove `WidgetSplitPane.sizes`

- Once everyone goes through the wirers, `sizes` is redundant.
- Migrate `WidgetSplitPaneToGraphicsCanvas` to compute splitter rect
  positions from `position`, `size`, and child geometry instead of
  from `sizes`.
- Drop the field.

### Step 9 — Tests

- Allocator tests (Step 2).
- A test that constructs the workbench shell and asserts each child's
  `position`/`size` after `projection_print`.
- A test that mutates the shell's size and re-reads every child cell;
  asserts via `perf_counters()` that only the expected cells
  invalidated.
- A test for a 30%/70% split nested inside a 70%/30% split.
- A test that adding a page to the workbench (re-running
  `projection_print`) produces a wired pane.

---

## What is intentionally NOT here

- **No `LayoutSpec`, no DSL value type, no `splith`/`splitv` sugar
  constructors.** Layout is whatever Julia code the projection
  author writes, with the wirer helpers doing the per-slot
  arithmetic. The previous draft of this plan had a DSL; it was
  redundant with the projection system's own
  "rebuild-when-input-changes" mechanism.
- **No measure/arrange two-pass layout.** This is a constraint-based
  allocator over a tree the projection just built, not a
  content-aware layout engine. A leaf that needs content-driven
  sizing has the projection measure it and pass `FixedSize(measured_px)`.
- **No min/max constraints.** `FixedSize`, `FractionSize`, `FlexSize`
  only. Min/max can be added as a new policy type without changing
  the wirer shape.
- **No alignment / cross-axis policies.** Children always fill the
  cross axis. Centring or trailing alignment is a follow-up.
- **No animation.** Cells either hold a value or don't.

---

## Limitations

Most of the limitations listed in earlier drafts dissolved when the
layout moved into the creating projection — dynamic tree shape, the
double-`layout!` footgun, and the `sizes`/policy duplication are all
gone. What's left is the irreducible cost of an integer-pixel
constraint allocator.

### No content-aware sizing (no measure/arrange)

The allocator never inspects what a leaf *wants* to be.
`FixedSize(80)` is 80 pixels even if the leaf's text needs 200;
`FlexSize(1.0)` collapses to zero pixels if `FixedSize` siblings
consume the parent extent. There is no `Auto` policy.

For widgets whose natural size is content-driven (a `WidgetLabel`, a
`WidgetButton` sized to its text), the *projection* measures and
passes `FixedSize(measured_px)`. The measure function is already
threaded through the projection (see
[WidgetToGraphics.jl:226-228](../../program/src/projection/primitive/WidgetToGraphics.jl#L226-L228)),
so this is mechanically easy; it's just one more thing the
projection has to do.

### Fractions don't compose multiplicatively across nesting

`FractionSize(0.30)` reads its parent's extent, not its grandparent's.
A `wire_split_h!(...)` with two `FractionSize(0.5)` children inside a
horizontal `FractionSize(0.30)` slot of a 1280-wide root gives each
grandchild 192px — half of 384, not half of 1280. This is the natural
meaning but catches people used to CSS Grid's `fr` units or to global
percentage schemes.

### Pixel rounding can leave 1px asymmetry

Fractions produce floats; per-slot rounding can sum to one pixel less
or more than the parent extent. The plan picks "residual goes to the
last Flex; if no Flex, the last Fraction absorbs ±1px." Total stays
exact; adjacent slots can have a single-pixel asymmetry under
adversarial sizes. Visible only if you're looking for it.

### Sub-pixel allocation under shrink

When the parent extent is smaller than the sum of `FixedSize` slots,
the allocator squeezes proportionally to integer pixels, which can
collapse a `FixedSize(8)` to zero. There is no minimum-pixel floor.
The shell is expected to be at least as wide as its Fixed total;
below that, users get visual breakage rather than graceful overflow.

### No cross-axis policies; children always fill the cross axis

A `wire_split_h!` child cannot ask to be 80% of the parent's height
while siblings are 100%. Centring, trailing alignment, "fill less
than 100% of the cross axis" — none of that is in the model. If a
leaf needs cross-axis padding, it goes through its `margin`/`padding`
inset fields, not through layout.

### Unbounded `FlexSize` inside a `Scroll` has no reference frame

`WidgetScrollPane.content_size` defaults to mirror `size` (the
viewport). If a projection wires inner children with `FlexSize`
against an unbounded content surface, there's no finite extent to
flex against — `Flex` reads the viewport, content never grows.

In practice an inner scrolled layout must either use `FixedSize`
throughout, or have its `content_size` explicitly driven by some
other cell (the total height of a virtual list, etc.). There is no
"shrink-wrap to children" mode.

### Cell graph growth

Each laid-out child adds at minimum 4 cells (px, py, sx, sy). Each
split adds one extent cell and one offset cell per slot. A tree with
N nodes adds ~6N cells. Cheap — the reactive engine is small — but
invalidation walks scale with the dependent-set size. Measure with
`perf_counters()` for very deep nesting.

### Resize during a print is best-effort

The editor's main loop runs read → eval → print. A resize that fires
between the read and the print uses whichever cell values were live
when the print pulled. No atomic per-frame snapshot. The next frame
catches up, invisible at 60fps but can briefly desync a single-frame
screenshot.

### The wiring safety invariant is a rule, not a check (by default)

The wirers are safe because they target cells whose dependent set is
empty at wire time. Calling a wirer on a widget that's *already* in a
rendered tree would invalidate downstream during print — a real bug.
The plan documents the rule; it doesn't enforce it. An optional
runtime assertion in the wirers is cheap to add during development.

### Re-running a projection rebuilds the widget tree

When the workbench-to-widget projection re-runs (structural change
upstream), it allocates new `WidgetSplitPane`s, new cells, new
everything. Downstream iomap caches that pointed at the old widgets
go stale; the whole subtree re-renders next print. This is correct
and standard for ProjecturEd projections, but it means structural
changes are *not* incremental at the widget level — only geometry
changes are. If structural churn turns out to be frequent (e.g.
animated pane appearance), more aggressive identity-preservation
would be needed; out of scope for v1.

### User-supplied policy cells can introduce cycles

If a projection wires a policy `Cell{SizePolicy}` to read from a
*downstream* cell (a child's measured size, say), it constructs a
cycle. The reactive engine doesn't detect cycles; the next pull will
loop. Policies should depend on upstream state only.

---

## Open Questions

- **Should the wirers live in `WidgetModule` or a separate `WidgetLayoutModule`?**
  Probably the latter; layout is a concern that builds on the widget
  types but isn't part of them.
- **Should `FractionSize` be "of the original parent extent" or "of
  what remains after Fixed"?** Plan picks the first because 30%
  means 30% of the whole. Worth confirming with a concrete example
  before locking in.
- **Granularity of cells.** Four cells per child (px, py, sx, sy)
  lets the engine invalidate only the axis that changed. One
  `Cell{Rect}` per child would be cheaper to allocate but coarser to
  invalidate. Keep four for now.
- **Should there be a debug-time check that wiring targets have empty
  dependent sets?** Cheap, catches the one real footgun, can be
  gated by a build flag.
- **Per-window content projection.** Open from
  [multiple-windows.md](multiple-windows.md); doesn't affect this
  plan but the shell-size-from-`WindowDocument` wiring depends on
  it landing.

---

## Relationship to Existing Architecture

| Concept | Current | With layout helpers |
|---------|---------|---------------------|
| Where layout is set up | Hardcoded `Point2D(...)` in the projection that builds the widget tree | Same projection, but uses `wire_split_h!` / `wire_split_v!` over `SizePolicy` values instead of magic numbers |
| `WidgetSplitPane.position` / `.size` | Don't exist | Added; act as the parent geometry for the wirer |
| Child size inside `WidgetSplitPane` | Hardcoded on the child; `sizes[i]` placement only | Computed Cell derived from parent `size` + `SizePolicy` |
| `WidgetShell.size` | Primitive cell, set at construction | Same. (Optionally a computed cell reading `WindowDocument.width/height` once multi-window lands.) |
| Window resize → layout | Not propagated | Single primitive write → invalidates dependent cells → next print recomputes only what changed |
| `WidgetSplitPane.sizes` | Authoritative for slot widths | Initially redundant (wirer writes into it for splitter visuals); removed in Step 8 |
| `WidgetScrollPane.content_size` | Doesn't exist; nested layout reads `size` | New field; mirrors `size` by default, overridable for content larger than the viewport |
| Layout DSL | — | None. Projection code uses `wire_split_h!` / `wire_split_v!` directly. |
| New projection types | — | None. |
| Dynamic tree shape | Not supported beyond what `projection_print` re-runs already give you | Same — and the wirers play nicely with it, since re-running the projection produces a freshly-wired tree |

The change is fully additive on the document side (new fields on
`WidgetSplitPane` and `WidgetScrollPane`) and zero on the graphics
projection side. Existing pipelines keep working until a projection
opts in by calling `wire_split_h!` / `wire_split_v!` instead of
hardcoding sizes.
