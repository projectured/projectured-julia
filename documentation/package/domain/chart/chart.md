# Chart domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [plot.md](../../platform/plot/plot.md), [reference.md](../../kernel/reference.md)

`ProjecturedChart` draws line, scatter, bar, pie, histogram and colored-strip charts as documents, with a projection straight to graphics and no plotting library. This document says how a chart holds its data, how its cost stays bounded by the pixels, how a reference names one sample, and which features of the simulation analysis tool that it follows it leaves out.

<img width="396" alt="Chart example" src="../../../asset/image/example/chart.png">

## How it works

### The documents

| Document | What it holds |
| --- | --- |
| `Chart` | `title`, `series`, `x_axis`, `y_axis`, `legend`, `style`, and the bar settings `bar_placement`, `bar_baseline` and `bar_baseline_color` |
| `ChartAxis` | a numeric axis: `title`, `min` and `max` (`nothing` fits the data), `log`, `grid`, and two visibility flags |
| `ChartCategoryAxis` | a category axis: `title` and `categories` |
| `ChartLegend` | `visible`, `position`, `anchor`, `border`, `sort` |
| `ChartStyle` | the theme colours and fonts, the colour and marker cycles, and three limits: `marker_limit`, `scatter_fold_threshold`, `bin_fold_px` |
| `ChartLineSeries`, `ChartScatterSeries` | `x` and `y` columns, and the line and marker style |
| `ChartBarSeries` | one value for each category |
| `ChartPieSeries` | `categories` and `values`, one slice for each, and `colors`, one for each slice or `nothing` for the colour cycle |
| `ChartHistogramSeries` | `binedges`, `binvalues`, the underflow and overflow, and the `cumulative` and `density` flags |
| `ChartStripSeries` | `x` times, `values` as state codes, the `states` name table, `x_end`, and `state_colors` |

The order of `series` is the draw order and the legend order. A chart has two axis families: a `ChartAxis` on x carries line, scatter, histogram and strip series, and a `ChartCategoryAxis` on x carries bar series. The renderer leaves out a series of the wrong family and still draws the frame. A chart of pie series draws no axis: the first visible pie series fills the plot, from the top, clockwise, a polygon for each slice of positive value, and the legend lists the slices.

**A series holds whole columns, one cell for each column.** A column is numeric leaf data and no caret goes into it, so a cell for each sample costs about 88 bytes and gives nothing. An assignment of a new column, `chart.series[1].y = v`, repaints the chart without a new print of the projection. Any `AbstractVector{<:Real}` works, so a column of a data frame goes into a series directly. This is an exception to `PAR-FINEST-GRANULARITY`, on the same grounds as `GraphicsPolyline.points`.

### The chain

```
Chart ──ChartToChartPlot──▶ ChartPlot ──ChartPlotToGraphicsCanvas──▶ GraphicsCanvas
```

`ChartToChartPlot` wraps the chart in a `ChartPlot`, the presentation document. It holds the `view`, a zoom window in data coordinates, the `cursor` and the state of a drag. The series that the mouse target of the plot names lights, and the others are veiled. None of this is chart content: a saved chart has no scroll position, and two panes can zoom one chart in two ways. The stage builds the `ChartPlot` once and keeps its identity, so a zoom survives a change of the data. It maps a reference by one step, `chart`, and takes the node type from `get_reference_node_type`, so a `ChartNothing` root also gets a typed step.

`ChartPlotToGraphicsCanvas(; measure, width, height, minimum_width, minimum_height)` is the renderer. `width` and `height` are the chart's own size: an exact range from the parent replaces it, and a bounded range caps it at the edge. `minimum_width` and `minimum_height`, 120 and 80 by default, are the least size that it draws at; a chart in a cell of a pivot takes 24 and 16. One computed cell derives the frame from the chart, the view and that size: the data ranges, the plot rectangle, the ticks and their measured labels. The margins of the axes follow from the measured labels. A zoom writes a new data window, and the ticks, the grid and the decimation follow from it, so a zoom shows more detail and does not magnify pixels.

### Colored strips

A `ChartStripSeries` draws a sequence of enumerated values over time, such as the states of a machine. Segment *i* spans `[x[i], x[i+1])`, and the last one runs to `x_end`, or to the edge of the view when `x_end` is `nothing`. `values` holds 1-based codes into `states`. A column of strings or symbols becomes codes and a table, in the order of first appearance. `x` must ascend, but two equal times are allowed, and a segment of zero width folds away.

- **Rows.** Each visible strip takes one integer row, the first series on top, and a band spans the row centre ± 0.4 in data coordinates. A chart with only strips labels its y axis with the names of the series and draws no horizontal grid lines.
- **Colours.** A colour follows the state code, not the series. `strip_state_color` takes the `state_colors` entry of the series, or else the entry of the chart's cycle at the code. So two strips with different tables give their first state the same colour, unless one of them sets `state_colors`.
- **Legend.** The legend lists the states after the series. The entry of a strip has a grey swatch, and a click on it still hides or shows the series. A click on a state entry selects the legend.

### A reference step into a column

A column has no document for each sample, so no field or element step can name one sample. `ChartSampleReferenceStep`, written `.sample(i)`, names a position inside the opaque column instead. It is a `:structural` step, as `PointReferenceStep` is for a pixel inside a graphics element.

The step file registers the step with the reference DSLs through `build_reference_step` and `match_reference_step`, so `@reference_case` can match `::Chart.series[i].sample(k)`. The domain supplies `evaluate_reference_step`, because what a sample is depends on the series: `get_chart_sample` returns an `(x, y)` pair, a `(lower, upper, value)` bin, a bar value, or a `(lower, upper, state_name)` strip segment in data coordinates.

```julia
make_chart_sample_reference(chart, 1, 5)   # ::Chart.series[1]::ChartLineSeries.sample(5)
get_selected_sample(chart)                 # (1, 5), or nothing for a coarser selection
```

`make_chart_sample_reference` builds the path from steps and calls `annotate_reference_types`. The `@reference` macro can not build it, because it reads a lowercase `::t` as a type at run time and can not continue into an extension step. The selection still ends at a real document, the series, so no sample needs a cell. `SequenceChartRowReferenceStep` of the sequence chart is the same idiom for a row of a table; see [sequencechart.md](../sequencechart/sequencechart.md).

### Selection and gestures

`collect_chart_parts(chart)` lists the parts in reading order: the title, the x axis, the y axis, the legend, and one part for each series. Each part is selected as a whole. `style` is not a part, because nothing on the chart would show that it is selected; the property inspector edits it.

A click on a part selects it. A click on a data point or on a strip segment selects that sample, and the renderer draws a ring around it. A selected sample still counts as its series for the navigation, the hover and the legend. Inside a strip the reader finds the segment by the time under the pointer and by the raw sample index, so the reference is still correct after a zoom that folds the runs in a different way.

| Gesture | Effect |
| --- | --- |
| arrows, Home, End, Ctrl+Home, Ctrl+End | move the selection between the parts |
| Alt+Up, Ctrl+Alt+Home | select the whole chart |
| Alt+Down, Alt+Left, Alt+Right | select the first, the previous or the next part |
| Ctrl+Shift+Up, Ctrl+Shift+Down | move the selected series in the list |
| Alt+Delete | remove the selected series |
| click on a legend item; hover on it | hide or show that series; veil the other series |
| wheel over the plot; over an axis | zoom about the pointer; zoom that axis alone |
| Shift+wheel, Shift+drag, Shift+arrows | pan |
| drag in the plot | rubber-band zoom |
| double click, `0`; `+`, `-` | fit to the data; zoom about the centre |

The `@gestures Chart` table in `ChartDocument.jl` holds the navigation and the edits. The reader of the renderer holds the view gestures. The arrow keys move the selection, as in every other document, so a pan takes Shift. A drag computes from its anchor, which holds the point of the press, the window and the two axis scales at the press, and the reader writes no window equal to the one that the plot holds. So a move to the point of the last move writes no cell, also after a pan changed the geometry. A drag goes on while the button is held, also off the plot. A move with no button held during a drag follows a release that the plot did not get, and it ends the drag with no change, as Escape does. A move off the plot area clears the cursor.

### Scale

The cost of a chart depends on the size of its plot rectangle, not on the length of its data. The renderer calls the functions of [plot.md](../../platform/plot/plot.md):

- **Visible range.** A binary search finds the part of an ascending column inside the window.
- **Decimation.** At most four samples for each pixel column: the first, the lowest, the highest and the last. The result is exact.
- **Scatter folding.** Past `scatter_fold_threshold` visible points, the cloud becomes a density grid of eight shades, and neighbour cells of equal shade merge into one band.
- **Bar and bin folding.** Bars narrower than `bin_fold_px` merge into min and max envelopes.
- **Strip folding.** Equal neighbour values merge into runs. Runs narrower than a pixel fold into one span with the state that holds it longest. This is the one output that is not exact, because a span below a pixel has no one colour.
- **Label thinning and markers.** A dense category axis draws every k-th label. Markers draw only while fewer than `marker_limit` points are visible.

`test_chart_scale()` holds a million-sample line, a million-point scatter, a million-sample strip, a ten-thousand-category bar chart and a ten-thousand-bin histogram each under 4,000 graphics elements. A click finds a sample with a binary search too, so it costs the same on a million samples as on a hundred.

### The theme

`ChartTheme` holds what `ChartPlotToGraphicsCanvas` draws when the chart says
nothing: the colors of the backgrounds, the axis, the grid, the text, a selection,
the hover, a strip and the crosshair band, the title, axis and legend fonts, and
the padding, the tick length, the gap of a label, the spacing of the ticks, the
swatch and the gap of the legend. A value that `ChartStyle` sets keeps its
priority; the legend draws with `legend_font`. The printer takes `theme`, scaled
or not, holds all its values as one style field and no theme, reads it once at
each print, and gives the tuple to its helpers as `theme_values`. The natural registration of a frame time series gives the
scaled theme of the `Appearance`. The symbols that cycle over the series are the
chart's own (`ChartStyle.symbol_cycle`). The colors are the chart's own when
`ChartStyle.color_cycle` names a cycle; by default it is `nothing`, and the series
take the `series_colors` of the theme, the roles `series_1` to `series_8`, which
follow the colour settings of the appearance.

## How it fits

`ProjecturedChart` depends on the kernel and the platform. It registers one natural row, `:frame_time_series`: `FrameTimeSeriesToChart` draws the `FrameTimeSeries` of the statistics as a chart, one line for each time measurement. The projection lives here and not in the statistics slice, because the statistics are a part of the platform, which depends on no domain; see [statistics.md](../../platform/statistics/statistics.md). For a chart of its own, a caller builds the chain, or adds one entry to the natural renderer to draw a chart inside another document:

```julia
NaturalToGraphics(measure = FontFileMeasure(),
                  extra = Pair{Type,Any}[Chart => make_chart_pipeline_example()])
```

## Design decisions

- **Every visual property is a typed field.** The tool that the chart follows keeps its properties in a bag of strings. Here each one is a field of a document, so a selection and the inspector edit it. See [plan/done/chart-domain.md](../../../../plan/done/chart-domain.md).
- **The presentation state is on `ChartPlot`.** A saved chart has no view state, and two views of one chart zoom apart. The reader marks each write of it as view state, so a history records no zoom, hover or drag. `GraphLayout` makes the same split. See [plan/done/chart-domain.md](../../../../plan/done/chart-domain.md).
- **One cell for each column, not for each sample.** A cell for each of a million samples costs memory and gives no place for a caret. See [plan/done/chart-domain.md](../../../../plan/done/chart-domain.md).
- **A sample is a reference step, not a child.** The selection reaches one sample and no sample needs a cell. See [plan/done/chart-polygon-and-point-selection.md](../../../../plan/done/chart-polygon-and-point-selection.md).
- **The keyboard stops at the parts.** The navigation sweeps of the tests walk every reachable selection breadth first. Samples on the keyboard would make the state space of a chart as large as its data. A pointer reaches a sample.
- **Strips are rows in one plot, and the y axis names them.** A `ChartCategoryAxis` on y would change the whole numeric path of the y axis for what a tick-label mode already says. See [plan/done/chart-colored-strips.md](../../../../plan/done/chart-colored-strips.md).
- **The colour cycle is indexed by the code.** The tool that the chart follows indexes its colour map by position, so a sparse enumeration such as `A=1, C=5` takes the last colour. Here a code indexes the cycle directly. See [plan/done/chart-colored-strips.md](../../../../plan/done/chart-colored-strips.md).

## Usage

```julia
t = collect(0.0:0.1:30.0)
chart = Chart("Queue delay",
    [ChartLineSeries("q1", t, sin.(t) .* 4 .+ 10),
     ChartLineSeries("q2", t, cos.(t ./ 2) .* 3 .+ 12; line_style = :dashed, line_width = 2)];
    x_axis = ChartAxis(; title = "time (s)"), y_axis = ChartAxis(; title = "delay (ms)"),
    legend = ChartLegend(; position = :inside, anchor = :northeast, border = true))
chart.series[1].y = sin.(t) .* 6 .+ 10       # repaints; the projection does not print again

ChartHistogramSeries("service", randn(10_000); nbins = 30)
Chart("Throughput", [ChartBarSeries("run A", [12.0, 19.0, 7.0])];
      x_axis = ChartCategoryAxis(; categories = ["baseline", "tuned", "burst"]),
      bar_placement = :stacked)
Chart("MAC states", [ChartStripSeries("channel", [0.0, 4.0, 9.0], ["idle", "busy", "idle"]; x_end = 20.0)])

projection = ChainingProjection(ChartToChartPlot(),
                                ChartPlotToGraphicsCanvas(measure = FontFileMeasure()))
```

- Examples: `chart` (four charts in a `WidgetTable`), `chart_line`, `chart_bar`, `chart_histogram`, `chart_scatter`, `chart_strip` and `chart_inspector`, in `example/domain/chart/`. The atomic catalog has `chart/plot`.
- Test: `test_chart()` runs the layering guard, `test_chart_projection()` and `test_chart_scale()`.

## Limits

- A strip series together with line, scatter or histogram series is allowed but reads badly: the y axis stays numeric and the strips sit on its integer rows. A log y axis under strips reads badly in the same way. The renderer shows no warning for either.
- The line styles are `:solid`, `:dotted` and `:dashed`. A dash-dot line needs a pattern of four elements, and the graphics polyline has one on-off pair.
- No label rotates, because the SDL and PDF backends draw no rotated text. A dense category axis thins its labels instead, and a state name that does not fit in its segment is left out.
- A folded scatter cloud has no single points, so a click there selects the series.
