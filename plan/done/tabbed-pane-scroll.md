# Scrollable tab strip for WidgetTabbedPane

## Problem

The editing-page tab strip clips to the column width. When more tabs are open than
fit (e.g. workbench_example at ≤~1400px has 6 editor tabs but the center column fits
~4), the overflow tabs are drawn past the clip and are **completely unreachable** —
there is no tab-strip scrolling, no keyboard tab-switching, and no overflow menu, so
clicking a hidden tab is impossible (the click lands on the neighbouring column).

Measured: at 1280px `factorial.jl`/`table.pred` are unreachable; at ≥1600px all 6 fit.

## Decision

Add **horizontal scrolling of the tab strip** (chosen by the user over an overflow
menu / label elision / widening the column). Mirrors the existing
`WidgetScrollPane.scroll_position` pattern: a transient offset on the widget, the
printer offsets the strip inside its existing clipping `GraphicsViewport`, and the
reader turns a `MouseScroll` over the strip into a `ReplaceReferencedValue` write.

## Design

- **Document** — add `tab_scroll::Int` (horizontal pixel offset, ≥0; transient view
  state like `scroll_position`/`collapsed`) to `WidgetTabbedPane`. Default 0.
- **Printer** (`WidgetTabbedPaneToGraphicsCanvas.projection_print`):
  - `strip_w` is already computed. `view_w` is the selector viewport width (already
    `sel_view_w`). `max_scroll = max(0, strip_w - view_w)`.
  - rendered offset `s = clamp(tab_scroll, 0, max_scroll)` — reactive cell reading
    `tab_scroll`. Shift the selector strip's inner canvas x by `-s` (it currently sits
    at `-cox`; becomes `-cox - s`). Clip rect unchanged, so tabs scroll under it.
  - **Auto-scroll the active tab into view**: if the active tab's `[tab_xs[i],
    tab_xs[i]+tab_rws[i]]` falls outside `[s, s+view_w]`, nudge `s` so it is fully
    visible (clamped). Keeps the selected editor's tab reachable after a width change
    without fighting an explicit user scroll (recomputed from the *clamped* stored
    value each render).
- **Reader** (`projection_read`):
  - `MouseScroll` over the strip (y in the strip band): emit
    `ReplaceReferencedValue(w, "tab_scroll", clamp(old + delta, 0, max_scroll))`.
    Wheel `dy` (and `dx`) both drive horizontal scroll since the strip is horizontal.
    `view_w` is read back from the output selector viewport's `.w[]`; `strip_w` is
    recomputed from the tab label measurements (already done for hit-testing).
  - `MousePress` hit-test: add the rendered `s` to `evt.x` before the existing
    cumulative-`tab_x` comparison, so a click maps to the tab actually drawn there.
- The scroll offset only matters when `strip_w > view_w`; otherwise `s == 0` and
  behaviour is unchanged.

## Steps

1. [x] Add `tab_scroll::Int` field + `tab_scroll::Integer=0` keyword default to
   `WidgetTabbedPane` (Widget.jl). All call sites use the keyword constructor, so the
   default keeps them working.
2. [x] Printer: extracted `_tab_strip_geometry` (shared by printer + reader) and
   `_tab_scroll_offset` (clamp helper). `scroll_x` cell shifts the selector inner
   canvas by `-clamp(tab_scroll, 0, strip_w - view_w)`.
3. [x] Reader: `MouseScroll` over the strip → `ReplaceReferencedValue(w, "tab_scroll",
   …)`; `MousePress` adds the rendered scroll to `evt.x` before hit-testing; `_tab_view_w`
   reads the viewport width back from the output.
4. [x] Tests: third testset in `WorkbenchTabClickTest` — at 1280px the last tab is
   unreachable; a wheel produces a positive `tab_scroll` write; scrolling to the end
   makes the overflow tab reachable and scrolls a leading tab off. 14/14 pass.
5. [x] No regression: `test_workbench_tab_click` 14/14, `test_split_pane_drag` 31/31,
   workbench printer 26456 / reader 225, selection locality 0 errors. (Pre-existing,
   unrelated: WidgetIconTest "disabled button" errors on clean main too.)

## Notes / decisions discovered during implementation

- **Auto-scroll-active-into-view was dropped for v1.** Recomputing the offset to keep
  the active tab visible on every render fights an explicit user scroll — once the
  user scrolls the active tab off-screen it would immediately snap back, making the
  far side unreachable. Manual wheel scroll already solves reachability (the active
  tab's *content* always renders regardless of strip scroll). A one-shot
  scroll-into-view on selection change (stateful) is the proper follow-up.
- **`tab_scroll` persists because the editor builds the iomap once and re-forces.** A
  fresh `projection_print` rebuilds the transient `WidgetTabbedPane` with the default
  `tab_scroll=0`; only the persistent iomap keeps the wheel write. Tests must hold one
  iomap and re-force, not reprint (cost me a false negative mid-implementation).
- **Fixed a latent icon hit-test bug as a side effect.** The old reader measured tab
  widths from *text only*, so a tab with an icon shifted every later tab's hit box
  left of where it was drawn. Both printer and reader now share `_tab_strip_geometry`
  (text + icon + gap), so clicks land correctly on iconned tabs too.
- **No clamp on write (matches `WidgetScrollPane`).** The wheel delta is clamped to
  `[0, max_scroll]`, but a direct out-of-range `tab_scroll` just renders clamped; the
  *rendered* offset is always valid.
