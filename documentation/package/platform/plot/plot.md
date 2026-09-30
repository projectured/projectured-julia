# Plot arithmetic

> **Kind:** design · **Status:** current · **Stands on:** [domain-inventory.md](../../design/domain-inventory.md), [style.md](../style/style.md)

`ProjecturedPlot` holds the arithmetic that the chart and the sequence chart share: axis scaling, tick selection, the mapping from a data value to a pixel, the decimation that bounds the cost of a drawing, and the colour and marker cycles. It is a framework, not a domain, so it defines no document type. This document says what it holds, why it is pure, and what to check when you change it.

## How it works

Every function of `PlotModule` is pure. It takes numbers, vectors and colours and returns numbers, vectors and colours. It reads no cell and makes no document.

| File | What it holds |
| --- | --- |
| `source/plot/PlotGeometry.jl` | the axis mapping, the ticks, the data bounds, the decimation and folding, the legend geometry, and the values of bars and histograms |
| `source/plot/PlotStyle.jl` | the default colour and marker cycles, and the polygons of the markers |

The parts that are not obvious from their names:

- **`AxisScale(lo, hi, p0, p1; log = false)`** maps between a data coordinate and a pixel, affine or log-affine. `to_pixel` and `to_data` are the two directions. A chart builds a new scale from its data window on each zoom, so ticks and decimation follow the window.
- **`get_visible_range`** finds, with a binary search, the indices of an ascending column that fall into the window. So a pan over a long series reads only what shows.
- **`decimate_minmax`** keeps at most four samples for each pixel column: the first, the lowest, the highest and the last. The polyline through them is the same, pixel for pixel, as the polyline through all samples. So the output has at most four points for each pixel of width, and the picture is exact.
- **`fold_scatter`**, **`fold_bins`**, **`strip_runs`** and **`fold_strips`** fold what is narrower than a pixel: a dense cloud into a density grid, thin bars into an envelope, and a state trace into runs and then into spans. [chart.md](../chart/chart.md#scale) says what each one draws.
- **`label_step`** thins the tick labels that would collide, and **`find_nearest_sample`** snaps a crosshair to a sample.
- **`get_series_color(color, index, cycle)`** returns the colour of a series, or the entry of the cycle at the position of the series when `color` is `nothing`. **`get_series_symbol(symbol, index, cycle)`** does the same for a marker when `symbol` is `:cycle`. So an insert into the list of series changes the colours of the series after it.

## How it fits

`ProjecturedPlot` depends only on `ProjecturedStyle`, for `StyleColor` and the Solarized colours. `ProjecturedChart` and `ProjecturedSequenceChart` depend on it:

- The chart uses all of it: the scales, the ticks, every decimation and fold, the legend layout and the cycles.
- The sequence chart uses `AxisScale`, `to_pixel`, `to_data`, `compute_nice_ticks`, `format_tick`, `default_color_cycle` and `get_series_color`. It has its own decimation for events and arrows in `SequenceChartGeometry.jl`.

The package registers nothing.

## Design decisions

- **A framework below two domains.** The chart and the sequence chart both need the arithmetic, so neither of them owns it. [domain-inventory.md](../../design/domain-inventory.md#what-is-not-a-domain-package) states the rule: two domains that need the same thing make a framework.
- **Pure functions, no cells.** The functions stay testable without an editor, and a caller keeps a result in a computed cell of its own. `layout_graph` of [graph.md](../graph/graph.md) has the same split.
- **The decimation is exact.** `decimate_minmax` draws the same pixels as the full series. A chart is then correct at every zoom, and the cost depends on the width of the plot and not on the length of the data. See [plan/done/chart-domain.md](../../../plan/done/chart-domain.md).

## Usage

```julia
scale = AxisScale(0.0, 10.0, 40, 640)        # data 0..10 onto pixels 40..640
to_pixel(scale, 2.5)                         # 190.0
i0, i1 = get_visible_range(x, 2.0, 4.0)      # the indices of an ascending x inside the window
points = decimate_minmax(x, y, xs, ys, i0, i1)
```

- Examples: none of its own. Every chart and sequence chart example uses it.
- Test: `test_plot_geometry()` in `test/substrate/projection/PlotGeometryTest.jl`, which `test_substrate()` runs. `test_sequencechart_geometry()` covers the same arithmetic through the sequence chart.

## Limits

- The package holds no state, so it caches nothing. A caller that calls it outside a cell computes the result again on each call.
- A change to `decimate_minmax` or to `get_visible_range` changes the cost of every large chart. Run `test_chart_scale()` and `test_sequencechart_scale()` after one.
