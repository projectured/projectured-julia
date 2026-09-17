# Chart Domain

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md), [domain-inventory.md](../../design/domain-inventory.md)

Native line, bar, histogram, scatter and colored-strip charts, re-implementing
the chart types of the OMNeT++ analysis tool as a ProjecturEd domain. A chart is an ordinary
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
| `ChartStripSeries` | `x` times, `values` state codes, the `states` name table, `x_end`, per-state colours, the label and edge flags |

Presentation state, in `chart/ChartPlot.jl`: a `ChartPlot` wraps a chart with
the `view` window, the `cursor`, what is `hovered`, and any drag in progress.
None of that is chart content — a saved chart does not remember where someone
had scrolled to, and the same chart shown twice can be zoomed differently in
each — so it lives on the projection's output rather than on the document.

Two axis families, which the projection checks: a `ChartAxis` on x carries line,
scatter, histogram and strip series (they may be mixed); a `ChartCategoryAxis`
carries bar series. A series on the wrong family is left out and the frame still
draws.

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

# A state trace as colored strips: codes into a name table, or the names.
Chart("MAC states",
      [ChartStripSeries("host A", times, codes; states=["IDLE", "BACKOFF", "TRANSMIT"]),
       ChartStripSeries("channel", ctimes, ["idle", "busy", "idle"]; x_end=20.0)])
```

The projection is the two stages chained:

```julia
ChainingProjection(ChartToChartPlot(),
                   ChartPlotToGraphicsCanvas(measure=measure_truetype_text))
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

This is a deliberate exception to `PAR-FINEST-GRANULARITY`, on the same grounds
as `GraphicsPolyline.points`.

## Colored strips

A `ChartStripSeries` displays a series of enumerated values — usually the states
of a machine — over time. Segment *i* spans `[x[i], x[i+1])`, so a value holds
until the next sample replaces it, and a state trace reads as a band of colored
runs. This is OMNeT++'s "Display enums as colored strips" mode, which only its
matplotlib charts have.

`values` holds 1-based codes into the `states` name table; a column of strings or
symbols is pooled into codes and a table in order of first appearance. A code the
table does not reach still draws, and names itself with its own number. `x` must
ascend, non-strictly — a machine can pass through a state within one dispatch,
and a zero-width segment folds away.

The last segment runs to `x_end`, or to the edge of the view when the series has
none: a state persists until something ends it. On a chart where another series
reaches further, that is the other series' extent.

Strips occupy **rows**. Visible strips take integer y positions, the first in the
series list on top, and each band spans its row centre ± 0.4 in *data*
coordinates, so a y zoom scales the rows like anything else. A chart of nothing
but strips labels its y axis with the series labels instead of numbers and drops
the horizontal gridlines that would only underline the bands; one other series
visible and the numeric axis is back. Rows are positions over the *visible*
strips, so hiding or reordering strips under an explicit zoom window renumbers
them while the window keeps its coordinates — `0` refits. The row order follows
the series list, which is the legend's order unless `legend.sort` reorders it.

Colours follow the **state**, not the series, so the same state reads the same
across every strip: a code takes its entry from the chart's colour cycle, or from
the series' own `state_colors`. The cycle is indexed by the *code*, so two strips
with different tables give their first state the same colour — a series with a
vocabulary of its own wants `state_colors` to stay apart, which is what the
`chart_strip` example's channel series shows. Each segment names its state inside
itself when the name fits — no rotation, since the backends drop affine rotation,
so a name that does not fit is left out. `draw_edges` adds the faint segment
borders that are OMNeT++'s opt-in.

The **legend** lists the states, because that is what a strip's colours mean. A
strip's own entry keeps a neutral grey swatch — the band is many colours and any
one of them would misname the rest — and clicking it still hides or shows the
series. The state entries are a colour key and name no series, so clicking one
selects the legend, the way empty space inside the box already does. Series
entries come first and the states after them: strips sharing a table share their
entries, and interleaved that would read as though the states belonged to the
first strip alone.

Mixing strips with line, scatter or histogram series is legal but degraded: the y
axis stays numeric and the strips simply occupy their integer rows against it. A
log y axis under strips is degraded the same way. Neither is diagnosed.

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
make_chart_sample_reference(chart, 1, 5)   # ::Chart.series[1]::ChartLineSeries.sample(5)::Tuple
```

`ChartSampleReferenceStep` is a `:structural` step naming a position inside an
otherwise opaque leaf, exactly as `PointReferenceStep` names a pixel offset
inside a rendered element. It evaluates to what that sample *is*: the `(x, y)`
pair of a line or scatter point, the `(lower, upper, value)` of a histogram bin,
the `(lower, upper, state_name)` of a strip segment, the value of a bar. A strip
segment's extent is the one in the data, which does not move with the zoom, even
though the last one is *drawn* out to the edge of the view. The selection still
terminates at a real `Document`, the
series, which is what keeps `PAR-EVERY-DOCUMENT-HAS-SELECTION` satisfied without
a cell per sample.

Element indices are 1-based, as everywhere else in the repository.

## Selection

`collect_chart_parts(chart)` lists the selectable parts in reading order — title, x
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

Clicking a **data point** selects that sample, and the projection rings it.
Clicking a **strip segment** selects that sample too, and the projection outlines
it where it is drawn — the folded span if it folded. A selected sample still
counts as its series for everything coarser — navigation, the hover veil, the
legend highlight — so nothing that acts on a series stops working when a point
inside it is selected.

Inside a strip the segment is found by the time under the pointer, and by the raw
sample index rather than the coalesced run's, so the reference survives the zoom
that changes how runs fold. The hit stops at the drawn end: past an explicit
`x_end` the band is empty and the click means the series, as it does before the
first sample. On a chart mixing strips with points, a point within tolerance
wins — it is the smaller target.

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
| Alt+Up, Ctrl+Alt+Home | select the whole chart |
| Alt+Down | from the whole chart, select the first part |
| Alt+Left, Alt+Right | select the previous or the next part; the first and the last part keep the selection |
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
| pointer inside a strip | the readout names the state holding there |
| click a data point, or a strip segment | select that sample |
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
- **Run coalescing and strip folding.** A strip's equal adjacent values coalesce
  into runs before anything is drawn — a state trace re-records the state it is
  already in — and runs still narrower than a pixel fold into one span carrying
  whichever state holds it longest. A fast toggle therefore renders as a
  per-pixel dither of the states involved rather than as one neutral blur. This
  is the one place a chart is not an exact reproduction: a sub-pixel span has no
  single colour to be exact about. At a pixel and above every segment draws
  exactly.
- **Label thinning.** A dense category axis draws every k-th label, k derived
  from the measured label width against the per-category pixel width.
- **Marker suppression.** Markers draw only while there are fewer than
  `ChartStyle.marker_limit` visible points; past that they no longer read as
  individual points and the line already carries the shape.

A million-sample line, a million-point scatter, a ten-thousand-category bar
chart, a ten-thousand-bin histogram and a million-sample strip each stay under
four thousand graphics elements, and a zoomed-in window still renders every
sample it contains.

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
outline modes and overflow cells, the colour and marker cycles, and the strip
options `enum_as_strip` (a `ChartStripSeries` is the mode) and
`enum_strip_edges` (`draw_edges`).

Marker shapes: `:circle`, `:square`, `:diamond`, `:triangle_up`,
`:triangle_down`, `:triangle_left`, `:triangle_right`, `:pentagon`,
`:hexagon`, `:star`, `:plus`, `:cross`, `:dot`, `:hline`, `:vline`, `:none`.
The straight-edged ones are `GraphicsPolygon`s.

Not covered, and why:

- `Line.Style = DashDot` needs a four-element dash pattern; the graphics
  primitive carries a single on/off pair, so the styles offered are `:solid`,
  `:dotted` and `:dashed`.
- Rotated category labels need affine rotation, which the SDL and PDF backends
  drop; labels are thinned instead. In-strip state names are omitted rather than
  rotated for the same reason, where OMNeT++ labels any segment past ten pixels
  and turns the name vertical when it does not fit.
- OMNeT++ hides its per-value legend behind a click that swaps it for the series
  entry. Both are shown at once here — the states are the point of a strip, and a
  mode you have to discover is a poor place to keep them — which also leaves the
  legend click free to go on hiding a series.
- OMNeT++ gives each strip its own subplot and hides its y axis; strips here are
  rows in one plot, and the y axis carries their labels.

Deliberately more faithful than OMNeT++ in one place: its colormap bins are the
positional indices `0..n-1`, so a sparse enum spec like `"A=1,C=5"` clamps to the
last colour there. A code here indexes the cycle directly.

## Key Features

- Five chart types, natively rendered, in one document model with one projection.
- Every visual property is a document field, so it is selectable and editable.
- Interactive: zoom, pan, rubber band, crosshair, legend toggling, reordering.
- Cost bounded by pixels rather than by data, with exact decimation.
- Reactive at whole-column granularity: replace a column, the chart repaints.
- No third-party dependency, and no dependency on any simulator.
