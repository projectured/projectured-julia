"""
    PlotModule

The plot slice: the arithmetic every plotted notation shares, and the vocabulary
it draws with. A chart and a sequence chart both scale an axis, map data to
pixels and hand colours out by position, so neither owns either half.

This file holds the arithmetic: axis scaling, tick selection, data↔pixel mapping,
and the decimation and folding that keep a chart's cost proportional to its
pixels rather than to its data.

Everything here is a pure function over plain numbers and vectors — no cells, no
document types, no dependency on the rest of the slice. That is deliberate, the
same split `GraphLayoutEngine` makes: the algorithms stay unit-testable headless
and a caller is free to memoize them in a reactive cell.

The scalability story lives here:

- [`get_visible_range`](@ref) binary-searches an ascending column for the indices
  overlapping the view window, so panning a huge series touches only what shows.
- [`decimate_minmax`](@ref) collapses every run of samples landing on one pixel
  column to at most four points (first, min, max, last). The result is
  pixel-identical to drawing all of them, so this is exact, not sampling.
- [`fold_scatter`](@ref) bins an overplotted cloud into a density grid.
- [`fold_bins`](@ref) merges bars or bins narrower than a pixel threshold.
- [`label_step`](@ref) thins tick labels that would otherwise collide.
"""
module PlotModule

using ..StyleModule

export default_color_cycle, default_symbol_cycle,
       get_series_color, get_series_symbol, build_marker_polygon
export AxisScale, to_pixel, to_data, get_axis_span,
       get_column_bounds, merge_bounds, pad_range,
       compute_nice_number, compute_nice_ticks, log_ticks, format_tick,
       get_visible_range, decimate_minmax, step_points, build_pins_segments,
       fold_scatter, fold_bins, strip_runs, fold_strips, label_step, find_nearest_sample,
       compute_bin_values, compute_histogram_values,
       compute_legend_layout, get_anchor_offset


include("PlotGeometry.jl")
include("PlotStyle.jl")

end # module
