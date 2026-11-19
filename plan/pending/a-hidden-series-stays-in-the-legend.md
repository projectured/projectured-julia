# A hidden series stays in the legend

**Status:** proposed on 2026-11-19. Not approved, and not started.

The plan lands nothing and pushes nothing: it ends with a request to land.

**If a step needs a change of a kernel file, or a mechanism that this plan does
not name, the work stops and the session asks.**

## The problem

A click on a legend entry hides its series. Then the legend lists only the
series that are shown, so the entry is gone. Nothing on the chart can show the
series again.

```julia
chart = Chart("delay", [ChartLineSeries("a", x, y1), ChartLineSeries("b", x, y2)])
# legend:                      ■ a   ■ b
click on "b" in the legend     # sets chart.series[2].visible = false
# today:      ■ a              # "b" is gone, and there is nothing to click
# expected:   ■ a   ▪ b        # "b" stays in its place, faded; a click on it shows the line again
```

The cause is in the layout of the chart. `_layout` gives the legend the series
of `_visible_series(chart)` only, and `_legend_items` makes one entry for each
of them. The reader already answers a click on an entry with
`ReplaceReferencedValueOperation(s, "visible", !s.visible)`. So a click on a
hidden entry shows the series again, when the legend draws that entry.

Each chart with a legend gets the fix: a line, scatter, function, bar,
histogram, pie, strip or matrix chart, also a result chart of omnet-julia. The
sequence chart has no legend, and a pivot chart turns its legend off.

## The decision of the owner that this plan builds

- **A hidden entry is faded** (2026-11-19: "I agree, faded"). Its swatch and
  its label are drawn at about a quarter of their strength. The person still
  sees the color of the line that comes back.
  *Not chosen:* a hollow swatch with a grey label, and a line through the
  label.

## Proposed decisions

They are the decisions of the session. They become decisions of the owner when
the owner approves the plan.

1. **A hidden entry keeps its place.** The legend lists every series in the
   order of the list of series, or in the order of the labels when the legend
   has `sort = true`. A hidden series is in that order too. So the legend box
   keeps its size, an outside legend keeps the size of the plot, and no entry
   moves under the pointer when a click hides or shows a series.
   *Not chosen:* the hidden entries at the end of the legend. Then the entries
   move at each click, and a second click at the same point hits another entry.
2. **A new theme value `hidden_alpha`, with the default 0.25.** Its text in
   `ChartTheme`: "The opacity of the legend entry of a hidden series, relative
   to its own color." The swatch and the label of a hidden entry take their
   color with the alpha times `hidden_alpha`. The default is the value of
   `veil_alpha` now.
   *Not chosen:* `veil_alpha` for both. The veil says "the pointer is on
   another series". A theme that changes the one must not change the other.
3. **A pointer on a hidden entry fades no line.** The entry gets the hover fill,
   as a shown entry does. But the shown lines keep their full color, because
   the series under the pointer draws nothing. A click and an Alt+click on the
   entry act as now: the click shows the series, and the Alt+click selects it.
   *Not chosen:* the veil as now. Then every shown line fades, and the plot
   looks as if it turned off.
4. **An entry that explains a color is faded when no shown series draws that
   color.** After its series, the legend lists the states of the strips and the
   values of the lightest and the darkest shade of a matrix. Such an entry
   keeps its place. Example: two strips `a` and `b` share the states `idle` and
   `busy`. Hide `a`: `idle` and `busy` stay at full strength, because `b` draws
   them. Then hide `b`: the two state entries fade too.
   *Not chosen:* leave out the entries of the hidden series. Then the legend
   changes its size at a click.
5. **A pie hides as one series.** The legend has one entry for each slice of a
   pie, and each entry names the pie series. A click on a slice entry hides the
   whole pie, as now. Then each slice entry of that pie fades.
   *Not chosen:* hide one slice. A slice is not a series, and a pie series has
   no field that hides one slice.

## Facts of the code

All lines are in
[ChartPlotToGraphics.jl](../../source/domain/chart/ChartPlotToGraphics.jl).

- `_visible_series(chart)` (line 103) gives the shown series with their places
  in the list. The color cycle uses the place, so a hidden series keeps its
  color, and its faded entry shows the color that comes back.
- `_legend_items(chart, series, t, samples)` (line 553) makes the entries as
  `(series_index, label, swatch_color)`. The index 0 is an entry that names no
  series: a state of a strip, or a value of a shade of a matrix.
- `_legend_plan` (line 599) gives `nothing` when the legend has no entries. So
  now a chart whose series are all hidden draws no legend. With this plan it
  draws the legend, with each entry faded. Its plot draws the axes and no line,
  as now.
- `_legend_elements!` (line 670) draws each entry: the hover fill or the
  selection fill, the swatch, and the label. It records the label of a series
  as the text of its field `label`, so an Alt+click puts the caret in it. A
  hidden entry keeps this.
- The reader (line 2332) answers a click on an entry with the change of
  `visible`, and an Alt+click with the selection of the series. This plan does
  not change the reader.
- The veil fades each series but the series of `lit_index` (`_veiled`, line 43,
  and the strips, line 1523). The element pass sets `lit_index` from the mouse
  target (line 1989).
- A function series that is hidden computes no samples. So its entry shows the
  label without the reason why the series draws no line. The reason comes back
  with the series.
- The SDL, PDF and web backends pass the alpha of the color of a text.
- No code outside this file and its tests reads the entries of a legend.
  omnet-julia reads none.
- No example draws a chart with a legend and a hidden series. So a chart whose
  series are all shown draws the same elements as on `main`.
- The tests: `test/domain/chart/projection/ChartProjectionTest.jl` has "legend
  interaction" (a click hides the series), "strip legend" and "legend".
  `test/domain/chart/editor/ChartViewGestureTest.jl` sends window input at the
  pixels of a chart in a tab. `test_chart()` runs both.

## Steps

The work is in a worktree of projectured-julia. Each step ends with a commit.
Before step 1, `test_chart()` runs on `main` once, for the baseline.

- [ ] **1. The legend lists every series, and a hidden entry is faded.** The
  decision of the owner, and proposed decisions 1, 2 and 5. `_legend_items`
  takes each series of the chart, and each entry carries whether it is shown.
  `_legend_elements!` draws the swatch and the label of a hidden entry with
  `hidden_alpha`. `ChartTheme` gets `hidden_alpha`.
  *Check:* the test "legend interaction" grows: after the first click, the
  entry is at the same rectangle, and its swatch and label have the faded
  alpha. A second click at the same point gives `value == true`, and then the
  line draws again. New tests: a chart with every series hidden draws a legend
  with each entry faded; one click hides a pie, and each slice entry fades.
  `test_chart()` passes.
- [ ] **2. The entries of the states and the shades, and the veil.** Proposed
  decisions 3 and 4.
  *Check:* the test "strip legend" grows with the example of decision 4. A new
  test: a pointer on a hidden entry gives the entry the hover fill, and the
  shown lines keep their alpha. `test_chart()` passes.
- [ ] **3. The editor, and the documentation.** A new test in
  `ChartViewGestureTest.jl`: window input at the pixels of a legend entry of a
  chart in a tab. The first click hides the line, and the entry stays, faded.
  The second click at the same pixels shows the line again. A live check in the
  editor window with the line chart example: a screenshot after each of the two
  clicks. [chart.md](../../documentation/package/domain/chart/chart.md): the
  text of the legend and the table of the gestures say that a hidden entry
  stays faded in its place, and the list of the theme names `hidden_alpha`.
  *Check:* `test_chart()` passes. `Pkg.precompile` of omnet-julia against the
  branch passes. The plan moves to `plan/done/`. Then the session asks for the
  landing, and for the push apart.

## Risks

1. **Text with alpha in SDL.** The SDL backend gives the alpha to the glyph
   render. If a faded label draws at full strength, step 3 finds it in the
   screenshot. Then the label takes a color that is mixed with the background of
   the legend, which is opaque.
2. **Other plans change the same file.** The branch follows `main` by a
   rebase, and `test_chart()` runs again after it.

## Not in this plan

- **The frame of a chart whose series are all hidden.** A pie chart then draws
  axes, and a chart of strips draws a y axis of numbers. This is so on `main`.
- **A key or a menu item that hides or shows the selected series.**
- **The text of the verbs of omnet-julia**, which says that a click on a legend
  entry hides the series.
