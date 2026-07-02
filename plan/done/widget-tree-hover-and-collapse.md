# WidgetTree: mouse hover feedback + click-to-collapse/expand

## Motivation

Moving the mouse over `widget_tree_example` rows produces no visual change: the
`WidgetTree` renderer only draws a **selection** band (updated on click / arrow
keys) and has no hover state. The chevron (`▾`) drawn on parent rows is also
purely decorative — there is no collapse/expand behaviour.

Two features:

1. **Hover feedback** — highlight the row under the pointer with a faint band,
   updated live as the pointer moves and cleared when it leaves the tree.
2. **Collapse/expand** — clicking a parent row's chevron toggles whether its
   children are shown; the chevron flips `▾` (expanded) ⇄ `▸` (collapsed).

## Key facts discovered

- The hover pipeline already exists generically: `make_widget_projection_example`
  wraps the tree in `WidgetHoverTrackingProjection`, which turns `MouseMove` into
  `MouseEnter`/`MouseLeave` crossings and forwards the real `MouseMove` to inner.
  The tree simply never handled any of these events (only `MousePress` + `KeyDown`).
- `WidgetHoverTrackingProjection._target_of` treats the whole `WidgetTree` as ONE
  hover target (a `ReplaceReferencedValue` op's `.document`). So **per-row** hover
  updates must ride the forwarded `MouseMove` (`inner_op`), not the synthetic
  `MouseEnter` (which fires only on tree-boundary crossings). Therefore:
  - `MouseEnter` → **always** emit the identifying op when over a row (so the
    tracker keeps the tree as its target); `nothing` when outside the canvas.
  - `MouseMove` → emit only when the hovered row **changed** (avoid churn).
  - `MouseLeave` → clear `hovered`.
- Hover + chevron hit-testing **reuse the existing `_wtree_mouse_select` hit-test**
  (`geom.rows` in canvas-local coords), so they are coordinate-space-agnostic —
  whatever space selection clicks already work in, these work in too.
- The example tree is built from `(label, children)` tuples / plain `String`s
  (not `WidgetTreeNode`), which are immutable & non-reactive. So collapse state
  cannot live on the nodes — it lives on the `WidgetTree` as **transient UI
  state**, a `Set{Vector{Int}}` of collapsed node paths (mirroring how
  `selection`/`hovered` are transient path state; cf. accordion's `expanded::Int`).
- Toggling must store a **new** `Set` (not mutate in place) so the backing cell
  invalidates the geometry thunk and the tree re-flattens.

## Design

### Document (`package/domain/src/document/Widget.jl`)

Add two transient fields to `@document struct WidgetTree`:

- `hovered::Reference` — path-ref of the row under the pointer, or `nothing`.
- `collapsed::Set{Vector{Int}}` — node paths whose children are hidden.

Extend the hand-written outer constructor + the direct positional call in
`FileSystemToWidget.jl` to pass the two new cells.

### Renderer (`package/domain/src/projection/primitive/WidgetToGraphics.jl`)

- `WTreeRow` gains `collapsed::Bool`, `chevron_x0::Int`, `chevron_x1::Int`.
- Geometry `walk` reads `w.collapsed`; a collapsed parent is not recursed into;
  the row records the chevron hit-box and its collapsed flag.
- Printer draws a **hover band** overlay (fainter `_WT_HOVER_COLOR`) behind the
  selection band, reading `w.hovered` via the existing `_wtree_highlight_band`.
- Chevron direction: `row.collapsed ? :right : :down`.

### Reader

- Left `MousePress` on a parent's chevron column → toggle collapse
  (`ReplaceReferencedValue(w, "collapsed", newset)`); otherwise select the row.
- `MouseEnter`/`MouseMove` → set `hovered` (enter forces; move only on change).
- `MouseLeave` → clear `hovered`.

## Status — DONE

- [x] Document fields + constructors (`hovered::Reference`, `collapsed::Set{Vector{Int}}`)
- [x] WTreeRow (`collapsed`, `chevron_x0/x1`) + collapse-aware geometry flatten
- [x] Printer: `_WT_HOVER_COLOR` hover band overlay + `row.collapsed ? :right : :down` chevron
- [x] Reader: chevron-column click toggles collapse, else selects; `MouseEnter` (force) /
      `MouseMove` (on change) / `MouseLeave` drive `hovered`
- [x] `FileSystemToWidget` positional ctor call extended to 6 fields
- [x] Tests: new `WidgetTreeTest.jl` (`test_widget_tree`, 23 assertions, all green),
      wired into `ProjecturedTest`

### Notes discovered during implementation

- `WidgetHoverTrackingProjection` passes non-`MouseMove` events straight through to
  inner, so `MouseEnter`/`MouseLeave`/`MousePress` reach the tree reader directly;
  only `MouseMove` triggers its enter/leave synthesis. This is why the tree must
  handle `MouseMove` itself (the tracker returns the tree's `MouseMove` `inner_op`
  when the target is unchanged), while `MouseEnter` must *always* re-emit the
  identifying op (never `nothing` over a row) so the tracker keeps the tree as its
  hover target.
- Toggling `collapsed` must store a **new** `Set` (`copy` + push/delete) so the
  backing cell invalidates and the geometry thunk re-flattens.
- Pre-existing (unrelated) failure: `test_widget_icon`'s "disabled button tints its
  icon" reads `en[1].r` on a `GraphicsPolyline` (no such field; it has `.color`) —
  broken since before this branch (last touched 2026-06-30), not a regression.
