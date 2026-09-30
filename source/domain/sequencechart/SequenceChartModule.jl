"""
    SequenceChartModule

The sequence chart domain: the chart document, the plot it becomes, the
projection that draws the plot, the reference step that names one row, and the
arithmetic the rest of it rests on. This file holds the arithmetic, because
every other part is written in terms of it.

The arithmetic is: the timeline mapping that turns times
into a monotone coordinate, the conversions back and forth, tick selection for a
non-uniform axis, lane placement, arrow routing, and the decimation that keeps a
chart's cost proportional to its pixels rather than to its event count.

Everything here is a pure function over plain numbers and vectors — no cells, no
document types, no dependency on the rest of the slice, the same split
`PlotGeometry.jl` makes.

**The three-stage coordinate pipeline** is the idea the whole slice rests on:

```
time ──(timeline mapping)──▶ timeline coordinate ──(AxisScale over the window)──▶ flow pixel
```

The middle stage is what makes a sequence chart different from a plot. Event
times in a trace span orders of magnitude — microseconds between two protocol
steps, seconds until the next timeout — and a linear axis can show one or the
other but never both. So the mapping is pluggable
([`get_timeline_coordinates`](@ref)): proportional to time, to an ordinal, one unit
per event, or the nonlinear compression that keeps every gap visible while
preserving which gap is longer.

Everything downstream works in **flow** and **cross** coordinates rather than x
and y: flow is the direction time runs, cross is the direction lanes stack.
[`FlowFrame`](@ref) maps that pair to pixels, and it is the only place that
knows whether the chart is drawn horizontally or vertically.
"""
module SequenceChartModule

using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, map_reference_forward, map_reference_backward, read_intent

export FlowFrame, flow_point, flow_rect, frame_flow_span, frame_cross_span,
       get_timeline_coordinates, default_nonlinear_focus,
       time_to_coordinate, convert_coordinate_to_time,
       get_visible_event_range, get_visible_arrows,
       flow_ticks, get_honest_tick_label, tick_common_prefix,
       get_zero_time_spans, get_axis_cross_positions,
       get_arc_geometry, split_arrow, get_arrow_route,
       decimate_events, deduplicate_arrow_coverage,
       get_band_intervals, get_event_ordinal
export SequenceChartRowReferenceStep
export SequenceChartAxis, SequenceChartEvents, SequenceChartArrows,
       SequenceChartBandSeries, SequenceChartEventKind, SequenceChartArrowKind,
       SequenceChartTimeline, SequenceChartGutter, SequenceChartStyle, SequenceChart,
       get_event_count, get_arrow_count, get_axis_display_order, get_event_axis, get_event_kind,
       get_arrow_kind, get_arrow_source_axis, get_arrow_target_axis,
       get_event_label, get_arrow_label, get_band_state_name,
       insert_events, delete_events, delete_axis, move_axis,
       get_sequence_chart_parts, get_sequence_chart_part_index,
       get_event_reference, get_arrow_reference, get_band_reference, get_axis_reference,
       get_selected_event, get_selected_arrow, get_selected_axis_index,
       get_event_row, get_arrow_row, get_band_row,
       get_next_event_on_lane, get_arrow_from_event, get_arrow_into_event
export SequenceChartView, get_sequence_chart_view, view_contains
export SequenceChartToSequenceChartPlot, SequenceChartToSequenceChartPlotIoMap
export SequenceChartPlotToGraphicsCanvas, SequenceChartPlotToGraphicsCanvasIoMap,
       resolve_window, get_lane_cross_position,
       find_event_hit, find_arrow_hit, find_band_hit, find_lane_hit, lift_sequence_chart_reference
export SequenceChartDocument, SequenceChartPlot, arc_height


include("SequenceChartGeometry.jl")
include("SequenceChartRowReferenceStep.jl")
include("SequenceChartDocument.jl")
include("SequenceChartPlot.jl")
include("SequenceChartToSequenceChartPlot.jl")
include("SequenceChartPlotToGraphics.jl")

end # module
