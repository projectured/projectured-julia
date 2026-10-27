"""
    ChartModule

The chart domain: a chart document, the plot it becomes, the projection that
draws the plot, and the reference step that names one sample inside it. This
file holds the step, because the rest of the slice is written in terms of it.

The `ChartSampleReferenceStep` step type — a reference step naming one sample
inside a chart series.

A series holds its data as whole column vectors precisely so that a million
samples do not become a million reactive cells, which leaves nothing for a
reference to descend *into*: there is no per-sample document to carry a
selection. So a sample is addressed the way a pixel offset inside a rendered
element already is, with a `:structural` step that names a position within an
otherwise opaque leaf — exactly what `PointReferenceStep` does for graphics
coordinates. The selection still terminates at a real `Document`, the series.

Registers its own `.sample(i)` entry with the kernel `@reference` /
`@reference_case` DSLs through the reference layer's `build_reference_step` /
`match_reference_step` seams. What a sample *evaluates* to depends on the kind
of series holding it, so the chart domain supplies `evaluate_reference_step`
rather than this file guessing.
"""
module ChartModule

using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..DisplayModule: make_workload_file

export ChartSampleReferenceStep
export ChartTheme, ScaledChartTheme
export ChartSeries, get_chart_series_family, get_chart_axis_family,
       get_selected_series_index, move_series, remove_series,
       collect_chart_parts, get_chart_part_index,
       get_chart_sample, make_chart_sample_reference, get_selected_sample
export ChartView, get_chart_view, is_point_in_chart_view
export ChartToChartPlot, ChartToChartPlotIoMap
export ChartPlotToGraphicsCanvas, ChartPlotToGraphicsCanvasIoMap, resolve_view,
       get_legend_item_rects, get_chart_part_reference, get_chart_series_reference
export ChartDocument, Chart, ChartNothing, ChartPlot, ChartAxis, ChartCategoryAxis, ChartLegend, ChartStyle, ChartLineSeries, ChartScatterSeries, ChartFunctionSeries, ChartBarSeries, ChartPieSeries, ChartHistogramSeries, ChartStripSeries, strip_state_name
export CHART_INTERVAL_STYLES
export FrameTimeSeriesToChart


include("ChartSampleReferenceStep.jl")
include("ChartDocument.jl")
include("ChartPlot.jl")
include("ChartToChartPlot.jl")
include("ChartTheme.jl")
include("ChartPlotToGraphics.jl")
include("FrameTimeSeriesToChart.jl")

# The rows that let a tab draw a chart, and the frame times of the statistics as
# a chart, and the names a model makes a chart with. The factory form, so every
# renderer builds its own projection instances.
function __init__()
    register_natural_graphics!(:frame_time_series, (; measure, appearance) -> Pair{Type,Any}[
        FrameTimeSeries => ChainingProjection(FrameTimeSeriesToChart(), ChartToChartPlot(),
                                              ChartPlotToGraphicsCanvas(measure = measure,
                                                  theme = get_scaled_theme!(appearance, ChartTheme))),
    ])
    register_natural_graphics!(:chart, (; measure, appearance) -> Pair{Type,Any}[
        Chart => ChainingProjection(ChartToChartPlot(),
                                    ChartPlotToGraphicsCanvas(measure = measure,
                                        theme = get_scaled_theme!(appearance, ChartTheme))),
    ])
    register_assistant_api!(ChartModule => (:Chart, :ChartLineSeries, :ChartScatterSeries,
                                            :ChartBarSeries, :ChartPieSeries, :ChartHistogramSeries,
                                            :ChartAxis, :ChartCategoryAxis, :ChartLegend);
        description = "A chart is `Chart(title, [ChartLineSeries(label, xs, ys)])`, with " *
                      "a series of each kind, and `open_pane!` draws it.")
end

# The file that a workload of the window opens (`run_file_workload`).
make_workload_file(::Type{Chart}) =
    (; name = "a.pred",
     text = print_pred_text(Chart("Queue delay", [ChartLineSeries("q1", collect(0.0:1.0:10.0),
                                                                  collect(10.0:-1.0:0.0))])),
     shown = r"Queue delay")

end # module
