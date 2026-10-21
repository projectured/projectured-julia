# Ctrl and the wheel zoom, and the wheel scrolls

Status: IN PROGRESS, 2026-10-21, on the branch `wheel-zoom`, in the worktree
`projectured-julia-wheel-zoom`. Not landed on `main`.

## The ask

The owner, 2026-10-21: Ctrl and the wheel over a plot in a card of a dashboard
scrolled the dashboard, and did not zoom the plot. Then: "we should also change
all charts: ctrl+wheel zooms, normal wheel scrolls vertically, shift+wheel
scrolls horizontally".

## The problem

The facts at `main` `a1cbc1e5c`. Find each function by its name.

1. **A card drops the wheel.** The reader of `WidgetCardToGraphicsCanvas` answers
   `nothing` for each `MouseScroll`, so the content of a card never gets a turn.
   The dashboard prints each card as a `WidgetCard` (`_build_card_grid`). The
   scroll pane gives a turn to its content first, and scrolls only when the
   content answers `nothing`, so it scrolled the dashboard, with or without Ctrl.
2. **The charts zoom on a plain wheel.** `_scroll_intent` of the chart zooms on a
   plain turn and pans on Shift. `read_intent` of `SequenceChartPlotToGraphicsCanvas`
   for a `MouseScroll` zooms on a plain turn, pans on Shift, and scrolls the lanes
   over the lane labels. A pan has no bound: a chart takes each turn, so a page
   can not scroll past a chart.
3. **The rest of the editor already has the rule.** `WidgetTransformPane` zooms
   on Ctrl and the wheel, and pans on a plain wheel. The SDL backend changes a
   turn with Shift into a horizontal turn (`dx`), so a scroll pane scrolls across
   on Shift and the wheel.
4. **Ctrl and the wheel can scroll.** Three readers scroll on a turn and do not
   read Ctrl: `_self_scroll` of the scroll pane (the cells of a table scroll by
   it too), the tab strip of `WidgetTabbedPane`, and `TaskStreamLinesToWidget`.
   So a zoom that stops at its limit, such as `WidgetTransformPane` at 4×, gives
   the next notch to the page, which scrolls.

## The decision

The owner agreed, 2026-10-21, to the rule and to two parts of it that I
recommended:

- **The rule.** Ctrl and the wheel zoom. The wheel scrolls up and down. Shift and
  the wheel, or a horizontal turn, scroll across. Over an axis of a chart, Ctrl
  and the wheel zoom that axis alone, as now.
- **A chart scrolls only while there is data to scroll to.** The extent of a
  chart is the window that it shows before a zoom: the fit of its data. A pan
  stops at the edge of the extent, and a turn that moves nothing answers
  `nothing`, so the page around the chart scrolls. This is the rule of the scroll
  pane (`_scroll_by`). A chart that shows all its data takes no plain turn.
- **Ctrl and the wheel never scroll.** Each reader that scrolls on a turn answers
  `nothing` for a turn with Ctrl.

A turn moves the view in the direction that a scroll pane moves it: a turn away
from the user shows what is above, and a turn to the left (or Shift and a turn
away) shows what is to the left.

## Steps

Do the work in the worktree on the branch `wheel-zoom`. Commit each step. Do not
land on `main` before the owner approves.

1. [x] **The card gives the wheel to the slot under the pointer.** Done in
   `962dbbcc6`. The reader of the card routes a `MouseScroll` with `_card_route`,
   as a press. Two tests in `WidgetTransformPaneTest.jl`: Ctrl and the wheel zoom
   a transform pane in a card in a scroll pane, and a turn that no slot uses
   scrolls the pane. `test_widget_transform_pane`, `test_widget_card_fold`,
   `test_scroll_pane_hover`, `test_widget_button_behavior` and `test_explorer`
   pass.
2. [x] **Ctrl and the wheel never scroll.** Done. `_self_scroll`, the tab strip of
   `WidgetTabbedPane` and `TaskStreamLinesToWidget` answer `nothing` for a turn
   with Ctrl. Tests: Ctrl and the wheel over a scroll pane with room give
   `nothing`; Ctrl and the wheel over a transform pane at 4× in a scroll pane give
   `nothing`; Ctrl and the wheel move no line of a task stream. The tests of step
   1 and `test_task_pages` pass (37, 48 and 240 assertions in the three suites
   that changed or cover the dashboard).
3. [x] **The chart.** Done; see [As built](#as-built). In `_scroll_intent`: Ctrl and the wheel zoom, as the plain
   wheel does now. A vertical turn pans the y window, and a horizontal turn pans
   the x window, inside the fit of the data, by `_PAN_STEP` of the window for each
   notch and by the fraction of a notch from a touchpad. A pan that moves nothing
   answers `nothing`. The name and the signature of `_scroll_intent` stay, because
   the precompile statements of omnet-julia name it. Tests in
   `ChartProjectionTest.jl` change to the new rule, and new ones: a plain turn over
   a chart that shows all its data answers `nothing`; a turn after a zoom pans and
   stops at the edge. `chart.md` gets the new table. Run `test_chart_projection`.
   Commit.
4. [ ] **The sequence chart.** Ctrl and the wheel zoom about the pointer. The
   direction of the turn on the screen picks the axis by the orientation: along
   the time it pans the window inside the first and the last event; across the
   time it scrolls the lanes, inside the lanes, also over the lane labels. A pan
   back from the end of a plot that follows the end stops the follow, as a scroll
   pane does. A turn that moves nothing answers `nothing`. Tests in
   `SequenceChartProjectionTest.jl`; `sequencechart.md` gets the new table. Run
   `test_sequencechart_projection`. Commit.
5. [ ] **The guides and the close.** `widget.md` says that a card gives the wheel
   to its slot and that Ctrl and the wheel never scroll. Run `test_platform()`
   (12 GB) once, and the chart and sequence chart suites. The plan moves to
   `plan/done/`. Commit.

## Not in this plan

- `WidgetTransformPane` pans on a plain wheel with no bound, so in a card of a
  dashboard it takes each plain turn. A bound needs the extent of its content.
- A zoom of the whole editor on Ctrl and the wheel.
- The views of omnet-julia, which this plan does not read.

## As built

- **Step 1.** The card routes the turn by `_card_route`, the helper that a press
  uses, so the answer is rerooted by the slot that answered.
- **Step 3.** `resolve_view` gives the fit to `_compute_fit_view`, and the scroll
  reads that fit as its extent. `_scroll_view` does the scroll, and
  `_clamp_pan(d; window, extent)` takes the two bounds as named pairs, because a
  caller could swap two bounds. Shift makes a turn go across also when it comes
  as a vertical turn, because a backend other than SDL can give Shift and the
  wheel as `dy`. `test_chart_projection` passes, 332 assertions.
