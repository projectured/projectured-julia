# Chart Domain

Native line, bar, histogram and scatter charts, re-implementing the chart types
of the OMNeT++ analysis tool as a ProjecturEd domain. A chart is an ordinary
document rendered by a bidirectional projection straight to graphics — no
plotting library and no rasterization, so a chart stays vector output, stays
selectable, and every part of it can be edited the way any other document is.

The slice is independent of any simulator: data enters as plain Julia column
vectors, so a data-frame column can be handed to a series directly.

## Types

Semantic content, in `chart/Chart.jl`:

| Type | What it holds |
|---|---|
| `Chart` | title, series list, the two axes, legend, style, and the chart-wide bar settings |
| `ChartAxis` | a numeric axis: title, `min`/`max` (`nothing` = auto), `log`, `grid`, label/title visibility |
| `ChartCategoryAxis` | a categorical axis: title and `categories` |
| `ChartLegend` | `visible`, `position`, `anchor`, `border`, `sort` |
| `ChartStyle` | theme colours and fonts, the colour and marker cycles, and the three scalability thresholds |
| `ChartLineSeries` | `x`/`y` columns, draw style, line style and width, marker, colour, visibility |
| `ChartScatterSeries` | `x`/`y` columns, marker, colour, visibility |
| `ChartBarSeries` | one `values` entry per category |
| `ChartHistogramSeries` | `binedges` (n+1), `binvalues` (n), under/overflow, the cumulative and density flags |

Presentation state, in `chart/ChartPlot.jl`: a `ChartPlot` wraps a chart with
the `view` window, the `cursor`, what is `hovered`, and any drag in progress.
None of that is chart content — a saved chart does not remember where someone
had scrolled to, and the same chart shown twice can be zoomed differently in
each — so it lives on the projection's output rather than on the document.

Two axis families, which the projection checks: a `ChartAxis` on x carries line,
scatter and histogram series (they may be mixed); a `ChartCategoryAxis` carries
bar series. A series on the wrong family is left out and the frame still draws.

## Examples

```julia
t = collect(0.0:0.1:30.0)
chart = Chart("Queue delay",
    [ChartLineSeries("q1", t, sin.(t) .* 4 .+ 10),
     ChartLineSeries("q2", t, cos.(t ./ 2) .* 3 .+ 12; line_style=:dashed, line_width=2)];
    x_axis=ChartAxis(; title="time (s)"),
    y_axis=ChartAxis(; title="delay (ms)"),
    legend=ChartLegend(; position=:inside, anchor=:northeast, border=true))

# Reactive: replacing a column repaints, without re-running the projection.
chart.series[1].y = sin.(t) .* 6 .+ 10

# A histogram from raw samples, or from edges and counts.
ChartHistogramSeries("service", randn(10_000); nbins=30)
ChartHistogramSeries("queueing", edges, counts; cumulative=true, density=true)

# Bars over named categories.
Chart("Throughput", [ChartBarSeries("run A", [12.0, 19.0, 7.0])];
      x_axis=ChartCategoryAxis(; categories=["baseline", "tuned", "burst"]),
      bar_placement=:stacked)
```

The projection is the two stages chained:

```julia
ChainingProjection(ChartToChartPlot(),
                   ChartPlotToGraphicsCanvas(measure=truetype_measure_text))
```

To put a chart inside another document — a workbench tab, a table cell — add one
dispatch entry: `NaturalToGraphics(measure=…, extra=[Chart => that_pipeline])`.

## Data model

A series holds **whole column vectors, one reactive cell each**. A column is
bulk numeric leaf data, not navigable structure: a cell per sample would cost
about 88 bytes each and buy nothing, since no cursor ever lands on a sample.
Reactive granularity is therefore the whole column, which is exactly what makes
replacing one an efficient repaint — the projection is not re-run, only the
computed geometry cells re-derive.

This is a deliberate exception to `AR-FINEST-GRANULARITY`, on the same grounds
as `GraphicsPolyline.points`.

## Reference paths

Every part of a chart is addressable, and the terminal of each path names the
type it reaches:

```julia
@reference ::Chart.title::String
@reference ::Chart.x_axis::ChartAxis
@reference ::Chart.x_axis::ChartAxis.min
@reference ::Chart.legend::ChartLegend.position::Symbol
@reference ::Chart.series::CellVector[1]::ChartLineSeries
@reference ::Chart.series::CellVector[1]::ChartLineSeries.color
```

A column is not addressable below itself — `series[1].y` names the whole column
— but an individual **sample** is, through a reference step rather than a child:

```julia
chart_sample_reference(chart, 1, 5)   # ::Chart.series[1]::ChartLineSeries.sample(5)::Tuple
```

`ChartSampleReferenceStep` is a `:structural` step naming a position inside an
otherwise opaque leaf, exactly as `PointReferenceStep` names a pixel offset
inside a rendered element. It evaluates to what that sample *is*: the `(x, y)`
pair of a line or scatter point, the `(lower, upper, value)` of a histogram bin,
the value of a bar. The selection still terminates at a real `Document`, the
series, which is what keeps `AR-EVERY-DOCUMENT-HAS-SELECTION` satisfied without
a cell per sample.

Element indices are 1-based, as everywhere else in the repository.

## Selection

`chart_parts(chart)` lists the selectable parts in reading order — title, x
axis, y axis, legend, then one entry per series — and each is selected whole
(an empty path at that node). The whole chart is the empty reference.

The projection draws whichever part is selected: a band behind the title, over
either axis' label strip, an outline around the legend box or the whole canvas,
and a highlighted legend row for a series. Selecting something that nothing
draws would be invisible to the user, which is why `style` is not among the
parts — it is reached through a property inspector instead.

Clicking a part selects it. The reader produces `ChartPlot`-domain references
and the first stage peels its own step off on the way back, so what reaches the
document is a plain `Chart` reference.

Clicking a **data point** selects that sample, and the projection rings it. A
selected sample still counts as its series for everything coarser — navigation,
the hover veil, the legend highlight — so nothing that acts on a series stops
working when a point inside it is selected.

Samples are reached by pointing, not by walking: the arrow keys stay at part
granularity. The navigation sweeps enumerate every reachable selection by
breadth-first search, so letting the keyboard step into samples would make a
chart's state space its sample count — hundreds of reprints for these examples,
and unbounded in principle. Picking a point out of an ascending column is a
binary search, so it costs the same on a million samples as on a hundred; a
folded scatter cloud has no individually drawn points, so a click there selects
the series.

## Interaction

| Gesture | Effect |
|---|---|
| arrows, Home, End, Ctrl+Home, Ctrl+End | move the selection between parts |
| Alt+arrows, Ctrl+Alt+Home | tree navigation: out to the whole chart, back in, between siblings |
| click on title / axis / legend / a series | select that part |
| click a legend item | hide or show that series |
| hover a legend item | veil the other series |
| wheel over the plot | zoom about the cursor |
| wheel over an axis strip | zoom that axis alone |
| Shift+wheel, Shift+drag, Shift+arrows | pan |
| drag in the plot | rubber-band zoom; leaving mid-drag abandons it |
| double-click, `0` | refit to the data |
| `+` / `-` | zoom about the centre |
| pointer in the plot | crosshair snapped to the nearest sample, with a value readout |
| click a data point | select that sample |
| Ctrl+Shift+Up/Down | move the selected series within the list |
| Alt+Delete | remove the selected series |

The series list is both the draw order and the legend order, so reordering it is
how series ordering is controlled. Arrow keys belong to selection navigation, as
they do everywhere else in the editor, which is why panning takes Shift.

Zooming rewrites the **data window**, not a pixel transform: ticks, gridlines,
labels and decimation are all re-derived from it, so zooming in reveals more
detail rather than magnifying pixels.

## Scale

A chart's cost is bounded by its plot rectangle, not by its data. `ChartGeometry`
holds the arithmetic, as pure functions over plain vectors:

- **Visible-range clipping.** A series whose `x` ascends is binary-searched for
  the indices overlapping the window, so panning a huge series touches only what
  shows.
- **Per-pixel decimation.** Samples landing on one pixel column collapse to at
  most four points — the first, the lowest, the highest and the last. That is
  exactly what reproduces the column, so the result is pixel-identical to
  drawing every sample, not an approximation.
- **Scatter folding.** Past `ChartStyle.scatter_fold_threshold` visible points a
  cloud folds into a density map: the points are binned into a pixel grid, the
  density is quantized into eight shades, and neighbouring cells of equal
  darkness merge into one band.
- **Bar and bin folding.** Bars or bins narrower than `ChartStyle.bin_fold_px`
  merge into min/max envelope bars.
- **Label thinning.** A dense category axis draws every k-th label, k derived
  from the measured label width against the per-category pixel width.
- **Marker suppression.** Markers draw only while there are fewer than
  `ChartStyle.marker_limit` visible points; past that they no longer read as
  individual points and the line already carries the shape.

A million-sample line, a million-point scatter, a ten-thousand-category bar
chart and a ten-thousand-bin histogram each stay under four thousand graphics
elements, and a zoomed-in window still renders every sample it contains.

Hit-testing follows from the same discipline: hover and click search the
rendered geometry, never the raw columns, so nothing here degrades into a scan
over a million samples.

## Customization against OMNeT++

Every OMNeT++ `PlotProperty` maps to a typed field rather than a string-keyed
property bag — projectional editing is the property UI. Covered: plot and axis
titles with their fonts and colours, per-axis range/log/grid/label visibility,
all five legend positions with all eight anchors plus border and sort, the six
line draw styles, line style and width, seven marker shapes, the four bar
placements with baseline, the four histogram value transforms with solid and
outline modes and overflow cells, and the colour and marker cycles.

Not covered, and why:

- `Line.Style = DashDot` needs a four-element dash pattern; the graphics
  primitive carries a single on/off pair, so the styles offered are `:solid`,
  `:dotted` and `:dashed`.
- Diamond, triangle, pentagon and star markers need a filled-polygon primitive,
  which does not exist; the seven shapes offered are the ones the existing
  primitives draw exactly.
- Rotated category labels need affine rotation, which the SDL and PDF backends
  drop; labels are thinned instead.

## Key Features

- Four chart types, natively rendered, in one document model with one projection.
- Every visual property is a document field, so it is selectable and editable.
- Interactive: zoom, pan, rubber band, crosshair, legend toggling, reordering.
- Cost bounded by pixels rather than by data, with exact decimation.
- Reactive at whole-column granularity: replace a column, the chart repaints.
- No third-party dependency, and no dependency on any simulator.
