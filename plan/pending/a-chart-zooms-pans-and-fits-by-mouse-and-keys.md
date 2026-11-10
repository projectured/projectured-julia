# A chart zooms, pans and fits by the mouse and the keys

**Status (2026-11-10): in progress.** The owner approved the plan for
implementation on 2026-11-10 ("Let's go"). The owner decided D12, and D9 in its
second form. The assistant proposed the other decisions of §4, and they are
approved with the plan. No question is open.

**Goal:** a person moves the view of a chart as in a plot tool: zoom in and
out, pan, show all the data, fit one axis, with the mouse, the keys, a menu and
buttons that show while the pointer is over the chart, and sees where the view
is in the data. `Chart` and `SequenceChart` take the
same gestures from one window arithmetic.

**Repository:** projectured-julia. The plan changes no file under
`source/kernel/`, and [SEALING.md](../../SEALING.md) seals only kernel files.

**Branch:** `chart-navigation`, in the worktree
`../projectured-julia-chart-navigation`.

## 1. The request

> in projectured-julia charts the user should be able to pan, zoom in/out, fit
> to screen, etc. the usual navigation stuff with the mouse, keyboard etc.
>
> see what we have now and come up with a plan

## 2. What exists (main `b14502b56`)

### The chart

`ChartPlot` holds the window in data coordinates as view state (`view`,
`nothing` = fit the data), and the state of a drag
([ChartPlot.jl](../../source/domain/chart/ChartPlot.jl)). The reader of
`ChartPlotToGraphicsCanvas` reads the view gestures
([ChartPlotToGraphics.jl:1639-1870](../../source/domain/chart/ChartPlotToGraphics.jl#L1639-L1870)):

| Gesture | Effect |
| --- | --- |
| Ctrl+wheel over the plot; over an axis | zoom about the pointer, 1.15 for each notch; zoom that axis alone |
| wheel; Shift+wheel | scroll a tenth of the window up and down; across. The scroll stops at the edge of the fit |
| drag in the plot | band zoom; a band under 6 px on either axis does nothing |
| Shift+drag | pan; Escape puts back the view of the press |
| double click, `0` | show all the data |
| `+`, `-` | zoom about the centre |
| Shift+arrows | pan a tenth of the window |

A probe in the headless editor (2026-11-10) sent each gesture of this table as
window input, in a window scene and in the application window with the chart in
a tab. Each gesture works in both, with and without a click on the chart first.
The reader tests are in `ChartProjectionTest.jl` (`"zoom and pan"`,
`"rubber band"`). No editor-level test of a view gesture exists.

The probe and the code show these faults:

- **A log axis pans in linear data units.** `_drag_move`, `_scroll_view`,
  `_key_intent` and `_pan_by` add a linear distance. A Shift+drag of 100 px on a
  log x axis moved the window from `[0.871, 1148.2]` to `[-54.49, 1092.8]`. The
  bound is negative, and the point under the press does not stay under the
  pointer.
- **Only the wheel stops at the data.** A Shift+drag pan and the Shift+arrows
  have no bound. A zoom out and a zoom in have no limit.
- **A pie chart takes a zoom.** Ctrl+wheel, `+`, `-` and Shift+Right write a
  `ChartView` that nothing draws, because a pie has no axes.
- **The pointer is an arrow during each drag**, also during a pan.

### The sequence chart

`SequenceChartPlot` holds a time window anchored to an event, `follow_end`, and
`cross_offset`, the scroll of the lanes in pixels. Its reader takes Ctrl+wheel
(zoom about the pointer, 0.85 of the span for each notch), the wheel and
Shift+wheel (0.15 of the window along the time, 20 px across the lanes, inside
the first and the last event), and a double click (show the whole trace)
([SequenceChartPlotToGraphics.jl:1218-1270](../../source/domain/sequencechart/SequenceChartPlotToGraphics.jl#L1218-L1270)).
It has no band, no drag pan, no view key, and no limit to a zoom. The arrows
and Shift+←→ move the selection along the events.

### The parts that the plan uses

- `AxisScale` with `to_pixel` and `to_data`, linear or log, in the plot slice
  ([PlotGeometry.jl](../../source/platform/plot/PlotGeometry.jl)).
- The menu of a document on a right click: `make_context_menu_binding`, as the
  menu of `GraphLayout` uses it
  ([GraphLayout.jl:103-115](../../source/domain/graph/GraphLayout.jl#L103-L115)).
- A bar that a maker gives to a `WidgetScrollPane`: the pane draws it and
  computes nothing, the maker turns a write of its `value` into its own scroll,
  and keeps the drag of the thumb with `make_owned_scroll_bar_drag`
  ([widget.md](../../documentation/package/platform/widget/widget.md), the
  paragraphs on `vertical_scroll_bar`).
- The zoom keys of the editor: Ctrl+=, Ctrl+- and Ctrl+0 zoom the interface
  (`AppearanceDocument.jl`). `WidgetTransformPane` reads them first for its own
  zoom, and answers `nothing` at a limit, so the key goes on to the interface.
- The pointer shape `:closed_hand` (`POINTER_SHAPES`).

## 3. What a plot tool does, and where the code stands

| | What a plot tool does | Chart | Sequence chart |
| --- | --- | --- | --- |
| R1 | Zoom about the pointer with the wheel | yes | yes |
| R2 | Zoom one axis | yes, over the axis | the time axis only, by design |
| R3 | Zoom to a dragged band | yes | no |
| R4 | A band that is thin on one axis zooms the other axis only (Plotly) | no | not needed: a band is along the time |
| R5 | Pan by a drag, with a modifier or the middle button | Shift+drag only | no |
| R6 | Pan one axis by a drag on that axis (Plotly) | no | no |
| R7 | Scroll by the wheel inside the data | yes | yes |
| R8 | Show all the data by a double click and by a key | yes | double click only |
| R9 | Fit one axis | no | no |
| R10 | Zoom keys: `+`, `-`, and the zoom keys of the editor | `+`, `-` only | no |
| R11 | Pan keys: a step and a page (Excel: Alt+Page Down for a page across) | a step only | no |
| R12 | Escape stops a drag and puts back the view | yes | no drag |
| R13 | A menu of the view actions, with their keys | no | no |
| R14 | The person sees where the view is in the data: a scroll bar | no | no |
| R15 | The pointer shows a pan | no | no |
| R16 | A log axis zooms and pans in its own space | no | no log axis |
| R17 | The window stays in the data: each pan stops at the edge, a zoom out stops at all the data, a zoom in stops before the ticks become equal | the wheel only | the wheel only |
| R18 | A chart with no axes takes no view gesture | no (pie) | not needed |
| R19 | Buttons for the view actions while the pointer is over the chart (Plotly) | no | no |

## 4. The decisions

Each decision except D12 is proposed by the assistant and approved with the plan
(2026-11-10).

- **D1. Scope: `Chart` and `SequenceChart`.** Each place that shows a `Chart`
  gets the gestures with it: the examples, the pivot cells and the chart of the
  frame statistics. On 2026-10-21 the owner's "all charts" covered both charts.
  The graph is not in the plan: it zooms a layout, not a data window.
  Rejected: the chart alone. The two charts then keep two sets of gestures and
  two sets of numbers (1.15 and 1/0.85 for each notch, 0.1 and 0.15 for each
  scroll).
- **D2. One window arithmetic in the plot slice.** One set of functions on an
  axis window (low, high) and its `AxisScale`: zoom about a point, pan by a
  pixel distance, clamp into an extent, and the two limits. It works in the
  space of the axis, `log10` on a log axis. Both charts call it, and the
  private `_zoom_about`, `_pan_by` and `_clamp_pan` go. Rejected: a fix of the
  log case in the chart reader. The sequence chart then keeps its own copy of
  the arithmetic.
- **D3. The extent is the fit of the data, for each gesture.** A pan of any
  kind stops at the edge of the fit. A zoom out stops at the fit. A zoom in
  stops where the window spans 10,000 times `eps` of its largest bound, so two
  tick labels always differ. A gesture at a limit answers `nothing`, as a notch
  of the graph does. Rejected: a free pan and zoom past the data, as in Plotly.
  The wheel already stops at the edge by the owner's rule of 2026-10-21, and
  two rules for one window confuse.
- **D4. A plain drag stays the band zoom.** Shift+drag and a drag with the
  middle button pan. Rejected: a plain drag pans, as in a map. A band is the
  zoom of Plotly, of Grafana, and of the zoom mode of matplotlib, and the pan
  has two ways.
- **D5. A thin band zooms one axis.** A band under 6 px on one axis zooms the
  other axis only, and the overlay draws it across the whole plot on the thin
  axis, so the person sees what the release does. Rejected: a held key that
  locks an axis, as in matplotlib. The event layer has no held letter key.
- **D6. An axis is a handle.** A drag on an axis pans that axis alone. A double
  click on an axis fits that axis alone. On the y axis, the fit holds the data
  of the x window that shows. Rejected: a fit of y over all the data. After a
  zoom on the time, a time series then shows as a flat line.
- **D7. The keys.**
  - Ctrl+=, Ctrl+- and Ctrl+0 zoom in, zoom out and show all the data in the
    chart that gets the keys, before the zoom of the interface, as
    `WidgetTransformPane` does. At a limit the key answers `nothing`, so Ctrl+0
    on a chart that shows all its data resets the zoom of the interface.
  - `+`, `-` and `0` stay.
  - Page Up and Page Down scroll a page up and down. Alt+Page Up and
    Alt+Page Down scroll a page across, as in Excel.
  - Shift+arrows stay a step of a tenth in the chart. In the sequence chart,
    Shift+←→ stay the moves along the events.

  Rejected: the plain keys only. Ctrl+= and Ctrl+- are the zoom keys of the
  editor in each other view that zooms.
- **D8. A menu on a right click.** The menu of `ChartPlot` holds "Zoom in",
  "Zoom out", "Show all the data", "Fit the x axis" and "Fit the y axis", each
  with its key. The menu of `SequenceChartPlot` holds "Zoom in", "Zoom out" and
  "Show the whole trace". Both use `make_context_menu_binding`, as
  `GraphLayout` does. The menu holds each action, and the buttons of D12 hold
  the three that a person uses most.
- **D9. A zoomed chart shows a scroll bar.** The chart gives two
  `WidgetScrollBar`s, and its renderer prints them through its recursion along
  the bottom and the right edge of the plot area, over the data. The thumb is
  the window among the fit, in the space of the axis. A write of `value` pans the
  window, and the chart keeps the drag of the thumb. A bar shows only while it is
  used, as each bar of the editor. The ground is the owner's rule "a view that
  scrolls shows a scroll bar" (2026-10-06), and a zoomed chart scrolls by the
  wheel. Decided by the owner, 2026-11-10, on the recommendation of the
  assistant ("Agree with your recommendation"), in place of the first form of
  this decision, a `WidgetScrollPane` around the view: a pane puts its bars at
  the outer edges of the whole chart, under the labels and the title of the x
  axis and right of the legend, and it takes the room of its host, so each chart
  could change its size. Rejected also: a bar that the chart printer draws with
  its own elements. The editor then draws a bar in two ways.
- **D10. The pointer is a closed hand while a pan runs.** The band keeps the
  arrow. Rejected: an open hand at the hover. A hover does not know if Shift is
  held.
- **D11. A chart with no axes takes no view gesture.** A pie chart answers
  `nothing` for each view gesture, so the page around it gets the turn, and it
  shows no buttons.
- **D12. A chart shows buttons while the mouse is over it.** Decided by the
  owner, 2026-11-10: "I want the buttons while the mouse is over it". The
  assistant had recommended no buttons.
- **D13. The buttons.** Proposed by the assistant, approved with the plan
  (2026-11-10).
  - **Which:** "Zoom in", "Zoom out" and "Show all the data"; on a sequence
    chart, "Show the whole trace". A press does what the key of D7 does. The
    tooltip names the action and its key. A button whose action is at a limit
    of D3 is disabled, so "Show all the data" is disabled at the fit.
  - **Icons:** three new entries of `LUCIDE_ICON_GLYPHS`, `:zoom_in`,
    `:zoom_out` and `:maximize`, from the glyphs `zoom-in`, `zoom-out` and
    `maximize` of the Lucide font (`asset/font/lucide.ttf`, the full font).
  - **Place:** the top-right corner of the chart, in its top margin. The
    buttons take no space in the layout, so the chart does not move when they
    show, as an overlay bar takes no space.
  - **When:** while the plot has a mouse target, that is, while the pointer is
    over the chart, also over the buttons. They hide while a drag runs, so they
    do not cover a band. A chart whose plot is narrower than four buttons or
    lower than two buttons shows none, such as a chart in a cell of a pivot.
  - **How:** the plot holds a `WidgetToolbar` of three `WidgetToolbarItem`s as
    view state. `ChartToChartPlot` builds it one time with the plot, so it
    keeps its identity. The chart printer prints it through its recursion as a
    child canvas, and the reader gives a press in the toolbar to the IO map of
    that child, as a container gives a press to its child.
  - Rejected: buttons that the chart printer draws as its own icons. The editor
    then draws a button in two ways. Rejected: a new container that draws a band
    of controls over any content. The two charts are its only users now.

- **D14. The two charts share the code of their drawn parts.** Decided by the
  owner, 2026-11-10 ("Shared code", "this structure is acceptable for both
  slices"). The buttons and the bars are widgets that exist: `WidgetToolbar`,
  `WidgetToolbarItem` and `WidgetScrollBar`. The code that both charts share goes
  into two slices that exist, and no slice is new:
  - the graphics slice gets the routing to a child that a view draws at a place
    of its canvas, with no widget type in it: `find_drawn_child_at`,
    `read_drawn_child_event`, `read_drawn_child_move` and
    `map_drawn_child_point`, in `DrawnChild.jl` next to `ChildMove.jl`. The owner:
    "Graphics slice should be about graphics documents not widgets. No widget
    specific code should go there."
  - the widget slice gets the code that names a `WidgetScrollBar`:
    `keep_owned_scroll_bar_drag` and `convert_scroll_bar_value_writes`, next to
    `make_owned_scroll_bar_drag`.

  Each chart keeps where its parts go, their print, its buttons and its two bars
  filled from its own window. Rejected: a copy of the code in the sequence chart.

## 5. The steps

Each step adds the reader tests of what it changes, runs the narrowest suites,
and makes one commit.

1. [x] **The window arithmetic (D2, D3).** The functions of D2 in the plot
   slice, with unit tests in `test_plot_geometry()`: a zoom and a pan on a log
   axis keep the point under the pointer, a pan stops at the extent, and the
   two limits hold. The chart calls them for each gesture that it has now. Its
   pan by a drag and by the keys stops at the fit. A pie takes no view gesture
   (D11). A new test in `ChartProjectionTest.jl` repeats the log pan of the
   probe. Run `test_plot_geometry()`, `test_chart_projection()`.

   *As built (2026-11-10):* `compute_zoomed_window`, `compute_panned_window` and
   `compute_limited_window` in `PlotGeometry.jl`, each on a window `(lo, hi)`
   with `extent` and `log`. Two facts came up in the tests. A zoom in and the
   same zoom out came back to the extent only to within rounding, so a window
   within 1e-9 of the extent is the extent, and the view becomes `nothing`
   again. At the zoom-in limit the rounding of one zoom moved the window again
   on the next notch, so a window within 1.001 of the smallest span is at the
   limit. `format_tick` wrote at most 6 decimals and 2 digits of a mantissa, so
   two ticks got the same label long before the limit, for example on
   `[1e6, 1e6 + 1]`; it now takes the digits from the step in both forms, also
   for the labels of the sequence chart.
2. [x] **The mouse of the chart (D4, D5, D6, D10).** A middle drag pans. A thin
   band zooms one axis. A drag on an axis pans it. A double click on an axis
   fits it. The pointer is a closed hand while a pan runs. Run
   `test_chart_projection()`.

   *As built:* a band is thin across an axis by the rule of Plotly: less than
   0.6 of its length, at least 6 px and at most 20 px (`_THIN_BAND_MAX`). A
   fixed 6 px was too small for a hand that drags across. The strips of the
   axes leave out a legend that lies in them, so a drag or a double click on a
   legend under the plot stays the legend's.
3. [x] **The keys of the chart (D7).** Ctrl+=, Ctrl+-, Ctrl+0, the page keys
   and Alt with the page keys. A test shows that Ctrl+0 on a chart at the fit
   answers `nothing`. Run `test_chart_projection()`.

   *As built:* the pan of Shift and an arrow read only Shift, so Ctrl+Shift+Up,
   the move of a series, also panned; the pan now takes Shift alone. A typed
   `+`, `-` or `0` with Ctrl or Alt is not the chart's, so Ctrl+= does not zoom
   two times when a backend also gives its character.
4. [x] **The menu and the buttons of the chart (D8, D12, D13).** The binding on
   `ChartPlot` and a test of each item. The three icons, the toolbar of the
   plot, its print and its press. Tests: the buttons show while the plot has a
   mouse target and hide at the leave and during a drag; a press on each button
   gives the view of its key; "Show all the data" is disabled at the fit; a pie
   and a small chart show none. Run `test_chart_projection()`.

   *As built:* the menu is `compute_context_menu(::ChartPlot)`, bound with
   `make_context_menu_binding`. The renderer reads a dwell and a right click out
   from the part at their point to the plot (`read_child_part_gesture`), so the
   menu of the plot answers them. The buttons are `make_chart_buttons(plot)`,
   which `ChartToChartPlot` builds once; `follow_output_mouse_target!` gives
   them their part of the mouse target, and `ChartToChartPlot` names a part of
   the buttons by an introduced reference. The renderer prints the buttons
   through its recursion while they show, and gives them the pointer events in
   their frame. A chain of the two stages has no printer of a toolbar, so a
   hover failed there; `make_chart_projection(; measure, theme, widget_theme,
   …)` builds the whole view, a `NestingProjection` whose recursion prints the
   toolbar and its items, as `make_scrolling_graph_projection` does for the
   graph. The natural rows `:chart` and `:frame_time_series`, the pivot cells,
   the frame-time chart and the examples use it. The icons are `:zoom_in`,
   `:zoom_out` and `:maximize`. Steps 2 to 4 share one test run and one commit:
   the memory budget of the machine, which other sessions held, allowed one
   run at a time. Results: `test_plot_geometry()` 133/133, `test_chart()`
   514/514, `test_pivot_chart_views()` 24/24, `test_pivot_cell_views()` 30/30.
   The recorded calls of the workload of `ProjecturedChart` no longer resolve
   (119 of 574); step 7 records them again.
5. [x] **The scroll bars of the chart (D9).** The two bars of the plot, their
   print through the recursion that `make_chart_projection` gives, their place
   along the edges of the plot area, and their gestures. A test of the thumb at
   the fit, after a zoom, after a click on the track and after a drag of the
   thumb. Run `test_chart()`, `test_pivot_chart_views()`,
   `test_pivot_cell_views()`.

   *As built (2026-11-10):* `make_chart_scroll_bar(plot, axis)` makes each bar,
   whose `value` and `thumb_size` are computed from the window and the fit with
   `compute_window_scroll_bar_value` and `compute_window_scroll_bar_thumb` of the
   plot slice; `compute_window_at_scroll_bar_value` gives the window of a value.
   `ChartToChartPlot` builds the two bars with the buttons and names their parts
   by an introduced reference. The renderer prints a bar while its thumb is less
   than 1, as long as its edge of the plot area; the vertical bar runs along the
   whole right edge, and the bar under the plot stops before it. A click on the
   track pages, a write of the value becomes the write of the view, and a press
   on the thumb starts a drag that the chart keeps (`make_owned_scroll_bar_drag`,
   `read_scroll_bar_drag`). `make_chart_projection` prints `WidgetScrollBar` too.
   Results: `test_plot_geometry()` 144/144, `test_chart()` 535/535,
   `test_pivot_chart_views()` 24/24, `test_pivot_cell_views()` 30/30.
6. [ ] **The sequence chart (D2 to D10, D12 to D14).** First the shared code of
   D14, which the chart then calls. Then the window arithmetic, the
   band along the time, the drag pan of the time and the lanes, a drag and a
   double click on the time axis, the keys, the menu, the buttons and the bars. The move back from the end
   of a plot that follows the end still stops the follow. Run
   `test_sequencechart()`.
7. [ ] **The editor, the documents and a live check.** Editor-level tests in
   the headless application window, with the chart in a tab: each gesture of
   both charts as window input, at the pixels of the plot, as the probe did,
   and a move onto the chart, a press on each button and a move off it.
   The tables of
   [chart.md](../../documentation/package/domain/chart/chart.md) and
   [sequencechart.md](../../documentation/package/domain/sequencechart/sequencechart.md),
   [plot.md](../../documentation/package/platform/plot/plot.md) for the
   arithmetic, and a section on charts in
   [keyboard-and-mouse-guide.md](../../documentation/guide/keyboard-and-mouse-guide.md).
   A live check in the SDL window: `run_example("chart")` and a sequence chart
   example, each gesture and each button by hand. Run `test_chart()`, `test_sequencechart()`,
   `test_pivot()`. Move the plan to `plan/done/`.

**Not in this plan:** a history of views (back to the last view); a zoomed
chart that follows the newest data; a pinch on a touchpad (SDL2 gives no pinch
event for a touchpad); keyboard steps between samples (chart.md: "the keyboard
stops at the parts").
