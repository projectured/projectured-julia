# Plot

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

The plot arithmetic every plotted notation shares: axis scaling, tick
selection, the mapping from a data value to a pixel, and the colour and
marker cycles a series draws with. It is a framework two domains share
rather than a domain of its own — see
[domain-inventory.md](../../design/domain-inventory.md#what-is-not-a-domain-package)
— so nothing under `source/plot/` defines a document type.

## What is in the slice

| File | What it holds |
| --- | --- |
| `source/plot/PlotModule.jl` | the module, and what it exports |
| `source/plot/PlotGeometry.jl` | `AxisScale`, tick selection, data bounds, and the decimation and folding that keep a chart's drawing cost proportional to its pixels |
| `source/plot/PlotStyle.jl` | the default colour and marker cycles, and the legend layout |

## The public names

- `AxisScale(lo, hi, p0, p1; log=false)`, `to_pixel`, `to_data`,
  `get_axis_span` — the affine, or log-affine, map between a data coordinate
  and a pixel.
- `get_column_bounds`, `merge_bounds`, `pad_range`, `compute_nice_number`,
  `compute_nice_ticks`, `log_ticks`, `format_tick` — the extent of a column
  and where to put its tick marks.
- `get_visible_range` — binary-searches an ascending column for the indices
  inside the current view, so panning a large series touches only what
  shows.
- `decimate_minmax` — collapses every run of samples landing on one pixel
  column to at most four points (first, min, max, last). The result is
  pixel-identical to drawing every sample, not an approximation.
- `fold_scatter`, `fold_bins`, `strip_runs`, `fold_strips`, `label_step`,
  `find_nearest_sample`, `step_points`, `build_pins_segments` — binning an
  overplotted cloud, merging bars narrower than a pixel, and thinning
  labels that would otherwise collide.
- `compute_bin_values`, `compute_histogram_values` — the values a bar or
  histogram series draws from raw data.
- `default_color_cycle`, `default_symbol_cycle`, `get_series_color`,
  `get_series_symbol`, `build_marker_polygon` — a series that leaves its
  colour or symbol unset gets one by its position in the series list.
- `compute_legend_layout`, `get_anchor_offset` — where a legend sits relative
  to the plot area.

## How it fits

Every function is pure, over plain numbers, vectors and colours — no cell, no
document type, no dependency beyond `ProjecturedStyle` for the colour
palette. [chart.md](../chart/chart.md) and
[sequencechart.md](../sequencechart/sequencechart.md) are the two domains
that import `PlotModule`: a chart and a sequence chart both scale an axis,
map data to pixels and hand colours out by series position, so the
arithmetic sits below both instead of one owning it. A caller that wants the
result cached wraps a call in a reactive cell itself; nothing here holds
state to invalidate.

## What to check when a change touches this slice

There is no `test/plot/` folder; the direct test is
`test/substrate/projection/PlotGeometryTest.jl`, and
`test/sequencechart/projection/SequenceChartGeometryTest.jl` exercises the
same arithmetic through the sequence chart. `decimate_minmax` and
`get_visible_range` are the two functions a large-series performance
regression traces back to first, since they are what keeps a chart's redraw
cost independent of how many samples a series holds.
