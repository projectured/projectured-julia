# Drag-to-resize splitters for `WidgetSplitPane`

> **Status: DONE.** Phases 1 and 2 implemented and verified end-to-end
> (unconstrained + constrained regimes). Phase 3 polish (cursor feedback) left
> out of scope as planned. New reader test `test_split_pane_drag` (26 assertions)
> passes; `test_example(widget_split_pane_example)` shows no new failures (the 5
> pre-existing typein/navigation failures exist identically on the base branch
> and are unrelated to drag-resize). See **Implementation notes** at the bottom.

## Goal

Let the user grab a splitter between two slots of a `WidgetSplitPane` with the
left mouse button and drag it to redistribute space between the adjacent slots,
with live repaint during the drag. Today the splitter is a purely decorative
`GraphicsRect` and clicks on it fall through to a dead gap.

## Current state (what exists today)

- **Document**: [`WidgetSplitPane`](../../program/src/document/Widget.jl#L556-L568)
  holds `orientation`, `elements::CellVector`, `sizes::CellVector` (per-slot
  main-axis pref/intrinsic extents), inset/colour cells, and a `selection`.
  `sizes` may be **empty** (`CellVector()`) when constructed without `sizes=`.
- **Render**: [`projection_print(::WidgetSplitPaneToGraphicsCanvas, …)`](../../program/src/projection/primitive/WidgetToGraphics.jl#L1231-L1340)
  computes per-slot main-axis extents into `slot_main` cells (two regimes — see
  below), positions children via `child_x`/`child_y` cursor cells, and draws each
  splitter as a `GraphicsRect` of `splitter_thickness` in the gap between slots
  ([lines 1394-1404](../../program/src/projection/primitive/WidgetToGraphics.jl#L1394-L1404)).
- **Read**: [`projection_read(::WidgetSplitPaneToGraphicsCanvas, …)`](../../program/src/projection/primitive/WidgetToGraphics.jl#L1439-L1469)
  handles only `MouseScroll` and `MousePress`, routing them to the **child slot**
  under the cursor via `_route_split_event`; all other events (incl. `MouseMove`,
  `MouseDown`, `MouseUp`) hit the `_ =>` branch and are forwarded to the focused
  child. A press in the splitter gap hits no child canvas, so it is silently
  dropped — the gap is currently inert (good: we can claim it).
- **Event model**: the backend emits `MouseDown` / `MouseUp` / `MousePress`
  (synthesised click) / `MouseMove` (carrying the held `buttons` symbol) — see
  [`Mouse.jl`](../../program/src/device/Mouse.jl#L41-L96). `MouseMove` with a held
  button does reach the reader ([`Sdl.jl`](../../program/src/backend/Sdl.jl#L1547)).
- **Op flow**: [`read!`](../../program/src/editor/Editor.jl#L72-L94) turns each
  envelope into at most one `Operation`; `evaluate!` applies it and `print!`
  repaints, every frame. So an op emitted on each `MouseMove` gives live drag.
- **Precedent**: the scroll-bar knob ([`projection_read`](../../program/src/projection/primitive/WidgetToGraphics.jl#L1968-L1987))
  is **stateless** — it reacts to a single `MousePress` and computes the value
  from the absolute click position. There is **no existing stateful drag** in the
  codebase, and the editor has no mouse-capture / drag-state concept.

## Key design challenges

1. **Drag is stateful, the event pipeline is not.** Once the cursor leaves the
   splitter band mid-drag we still need to know which splitter is being dragged.
   We must persist "active splitter index" across `MouseDown → MouseMove* →
   MouseUp`. There is no editor-level capture slot; the established pattern is to
   keep transient view state **on the widget document** (selection, scroll
   position, scrollbar value, tab selection all already live there).

2. **Two sizing regimes** in `projection_print`:
   - *Unconstrained* (`avail_main === nothing`): slot extent =
     `_split_intrinsic(elem, sizes, i, axis)` = `sizes[i]` or a 200px fallback.
     Writing `sizes[i]` directly sets the slot — drag maps cleanly.
   - *Constrained* (`avail_main !== nothing`): [`allocate_axis`](../../program/src/projection/primitive/WidgetToGraphics.jl#L1298-L1313)
     redistributes the available main extent from per-slot `(min, max, pref,
     weight)`, where `pref` comes from `sizes`/intrinsic and `weight` from
     `layout_weight(elem)`. Setting `sizes[i]` only changes `pref`; non-zero
     weights can pull the final size away from the dragged boundary.
   The drag must behave predictably in **both**.

3. **`sizes` may be empty.** Before the first drag we must materialise `sizes`
   from the *currently measured* slot extents, otherwise there is nothing to
   mutate (and dragging from the 200px fallback would jump).

4. **Total must be conserved.** Dragging splitter *k* should grow slot *k* and
   shrink slot *k+1* (or vice-versa) by the same delta — never change the pane's
   overall extent — and respect each slot's `layout_min`/`layout_max`.

## Design decisions

- **State location — transient cell on the document.** Add
  `active_splitter::Cell{Int}` to `WidgetSplitPane` (0 = no drag in progress,
  `k` = dragging the splitter after slot `k`). Also store
  `drag_anchor::Cell` (the main-axis coordinate where the grab started and the
  two slot sizes at grab time) so each `MouseMove` resizes relative to the grab
  origin rather than accumulating rounding drift. Mark these clearly as
  transient UI state in the docstring; they are not serialised.

- **Operations** (added in `Widget.jl`, evaluated by `evaluate_operation`):
  - `StartSplitterDragOperation(split, splitter_index, anchor_coord, size_a,
    size_b)` — materialise `sizes` if empty, set `active_splitter` and
    `drag_anchor`.
  - `ResizeSplitPaneOperation(split, splitter_index, new_size_a, new_size_b)` —
    write the two adjacent `sizes[]` cells (clamped to each slot's
    min/max). Total conserved by construction.
  - `EndSplitterDragOperation(split)` — reset `active_splitter = 0`.
  Carrying the `WidgetSplitPane` identity directly mirrors
  `ScrollWidgetOperation` / `SetScrollBarValueOperation`.

- **Hit-testing the splitter band in the reader.** The band geometry is fully
  recoverable in `projection_read`: `orientation = iomap.input.orientation`,
  `splitter_thickness = max(1, _sc(p.splitter.width))`, and each child's screen
  rect from the `(x_cell, y_cell, cim)` tuples in `iomap.child_iomaps[]`
  (`cim.output::GraphicsCanvas` gives `.x/.y` + size). Splitter `k` occupies the
  main-axis gap between child `k`'s end and child `k+1`'s start; widen it by a
  small grab tolerance (e.g. ±3px) so a 1px hairline is easy to grab.

- **Resize semantics.** On drag of splitter `k` by main-axis delta `d` from the
  anchor: `new_size_a = clamp(size_a + d, min_a, max_a)`,
  `new_size_b = size_b - (new_size_a - size_a)` (then clamp `b` and re-derive `a`
  so both stay in range and the sum is preserved). Cross-axis movement ignored.

- **Constrained regime correctness.** To stop `allocate_axis` from fighting the
  drag, the two dragged slots must read their dragged size as a *hard* pref. Two
  options, decide during Phase 2:
  - (A) After a drag, treat the pane as pref-pinned: have `allocate_axis` honour
    pref exactly for slots whose size was set by a drag (e.g. zero their
    effective weight). Cleanest, keeps `sizes` the single source of truth.
  - (B) Require dragged slots to be wrapped in fixed-size `LayoutConstraint`s and
    rewrite the constraint extent on drag. More invasive.
  Recommended: **(A)** — add a per-slot "pinned" flag (a `CellVector{Bool}` on
  the pane, or sentinel weight 0) consulted in the `alloc_main_ref` builder.

## Implementation phases

### Phase 1 — unconstrained regime, end-to-end drag ✅ DONE
1. ✅ Added `active_splitter`/`drag_anchor` cells + the three operations to
   [`Widget.jl`](../../program/src/document/Widget.jl) with `evaluate_operation`
   methods.
2. ✅ In [`projection_read`](../../program/src/projection/primitive/WidgetToGraphics.jl)
   added a `_split_drag_read` dispatcher called **before** child routing:
   - `MouseDown(:left)` inside a splitter band → `StartSplitterDragOperation`.
   - `MouseMove` while `active_splitter != 0` → `ResizeSplitPaneOperation`
     (does **not** forward to children).
   - `MouseUp(:left)` while dragging → `EndSplitterDragOperation`.
   `MousePress`/`MouseScroll`/keyboard routing unchanged. Drag ops carry the
   pane identity directly, so they flow up through `prepend_steps_to_op`
   unchanged (no slot re-rooting needed).
3. ✅ Helper `_splitter_band_hit(orientation, child_iomaps, thickness, x, y, tol)`
   recovers band geometry from child positions (splitter `k` = the
   `thickness`-wide gap before child `k+1`, widened by `_SPLITTER_GRAB_TOL = 3`).
4. ✅ `_split_measured_sizes` seeds `sizes` from on-screen slot extents on drag
   start when empty.
5. ✅ Verified via a synthetic down/move/up sequence through the standard widget
   renderer (see test) — total conserved, second move resizes relative to the
   anchor (not cumulatively).

### Phase 2 — constrained regime (`avail_main !== nothing`) ✅ DONE
6. ✅ Implemented decision (A): per-slot `pinned::CellVector` on the pane. A
   dragged slot is pinned (`ResizeSplitPaneOperation` sets `pinned[k]`/`pinned[k+1]`),
   and the `alloc_main_ref` builder consults it — for a pinned slot it uses the
   dragged `sizes[i]` as a **hard pref** (overriding any `LayoutConstraint`
   `preferred_*`) and zeroes its weight, so `allocate_axis` leaves it alone.
   Verified: a drag inside a width-constrained pane sticks across a reprint.

### Phase 3 — polish (optional, can defer) — NOT DONE (out of scope)
7. Hover/grab cursor feedback (resize cursor over the band) — needs backend
   cursor support; **out of scope** unless cheap.
8. Honour `layout_min`/`layout_max` clamps visibly (don't let a slot collapse
   below its min).
9. Update [`guide/document/widget.md`](../../guide/document/widget.md) splitter
   section and the [`layout-extensions`](../tentative/layout-extensions.md) note.

## Testing

- **Reader unit test** (new, in `test/src/projection/`): feed a synthetic
  `MouseDown`→`MouseMove`→`MouseUp` sequence on a known-geometry split and assert
  the emitted operations and resulting `sizes`. Mirror the routing-test style in
  [`ProjectionConfiguringTest.jl`](../../test/src/projection/ProjectionConfiguringTest.jl#L88).
- **Regression**: existing `MousePress` child routing and `test_repl` for the
  split example must still pass — run `test_example(widget_split_pane_example)`
  (or the narrowest split test) per the repo "smallest test" rule, **not**
  `test_all`.
- **Geometry edge cases**: empty `sizes`; 2 vs 3+ slots; vertical orientation;
  drag past a slot's min/max.

## Out of scope

- Cursor shape changes (Phase 3, backend-dependent).
- Persisting split sizes across sessions / serialising the transient cells.
- Keyboard-driven splitter nudging.

## Open questions (resolved)

- ✅ `MouseDown`/`MouseUp`/`MouseMove` *are* delivered during a press-drag-release.
  [`Sdl.jl`](../../program/src/backend/Sdl.jl#L1545-L1572) returns `MouseDown` on
  button-down, `MouseUp` on button-up (and only synthesises `MousePress` when the
  up lands within 5px/300ms of the down — so a real drag never collides with a
  click), and `MouseMove` carrying the held button while a button is down.
- ✅ Phase 2 pin mechanism: chose **per-slot `CellVector` of `Bool`** on the pane
  (`pinned`). Reads cleanly in the `alloc_main_ref` builder and keeps `sizes` the
  single source of truth.

## Implementation notes (as built)

- **Files changed:**
  - [`program/src/document/Widget.jl`](../../program/src/document/Widget.jl):
    added `active_splitter`, `drag_anchor`, `pinned` fields to `WidgetSplitPane`
    (+ keyword-constructor defaults `0` / `nothing` / empty); the three
    operations + their `evaluate_operation` methods; module exports.
  - [`program/src/projection/primitive/WidgetToGraphics.jl`](../../program/src/projection/primitive/WidgetToGraphics.jl):
    `_splitter_band_hit`, `_split_measured_sizes`, `_split_drag_read` helpers;
    `_split_drag_read` called at the top of `projection_read` before child
    routing; the `alloc_main_ref` builder now honours `pinned`; imports for
    `MouseDown`/`MouseUp`/`MouseMove` and the three operations.
  - [`program/src/Projectured.jl`](../../program/src/Projectured.jl): re-export
    the three operations.
  - [`test/src/projection/SplitPaneDragTest.jl`](../../test/src/projection/SplitPaneDragTest.jl)
    (new) + wiring in `ProjecturedTest.jl`.
  - [`guide/document/widget.md`](../../guide/document/widget.md): splitter
    drag-to-resize section.
- **Conservation/clamping (the resize math):** on each move,
  `new_a = clamp(size_a + delta, min_a, max_a)`,
  `new_b = clamp(size_b - (new_a - size_a), min_b, max_b)`, then re-derive
  `new_a = clamp(size_a + size_b - new_b, min_a, max_a)` and
  `new_b = size_a + size_b - new_a` so the pair's total is exactly preserved and
  both stay within their min/max. `delta` is measured from the grab anchor, not
  accumulated, so it doesn't drift.
- **Last-slot measurement gotcha:** the trailing slot's extent is derived from
  the outer canvas main extent (`outer_main - pos(n) - pos(1)`), *not* the child
  canvas width — a child (e.g. a title pane) need not expand to fill its slot, so
  its canvas width is an unreliable proxy.
- **Known limitation (accepted):** there is still no editor-level mouse capture.
  If the cursor leaves the pane's bounding box mid-drag the parent stops routing
  events to the pane, so the drag pauses (and a `MouseUp` outside the pane won't
  end it). For drags that stay within the pane — the normal case — this is a
  non-issue. A real capture slot is future work if it becomes annoying.
