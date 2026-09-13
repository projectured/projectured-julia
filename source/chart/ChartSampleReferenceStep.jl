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

export ChartSampleReferenceStep
import ..StyleModule: StyleColor
import ..PlotModule: default_color_cycle, default_symbol_cycle, get_series_color
import ..PlotModule: compute_bin_values
import ..ReferenceModule
import ..ReferenceModule: Reference, ConcreteReference, FieldReferenceStep,
                          ElementReferenceStep, EmptyReference,
                          annotate_reference_types, concat_references,
                          get_reference_node_type
import ..ReferenceModule: var"@reference_case"
import ..ReferenceModule: var"@reference"
import ..OperationModule: CompoundOperation, ReplaceSelectionOperation,
                          insert_elements, delete_elements
export ChartSeries, get_chart_series_family, get_chart_axis_family,
       get_selected_series_index, move_series, remove_series,
       collect_chart_parts, get_chart_part_index,
       get_chart_sample, make_chart_sample_reference, get_selected_sample
import ..DocumentModule: @document
import ..ReferenceModule: Reference
export ChartView, get_chart_view, is_point_in_chart_view
import ..CellModule: Cell, ComputedCell
import ..ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: IoMap, var"@iomap"
import ..ReferenceModule: ConcreteReference, FieldReferenceStep, EmptyReference,
                          get_reference_node_type
import ..ReferenceModule: var"@reference", var"@reference_step"
export ChartToChartPlot, ChartToChartPlotIoMap
import ..CollectionModule: CellVector, ComputedCellVector
import ..PlotModule: get_series_color, get_series_symbol, build_marker_polygon
import ..PlotModule: AxisScale, to_pixel, to_data,
                              get_column_bounds, merge_bounds, pad_range,
                              compute_nice_ticks, log_ticks, format_tick,
                              get_visible_range, decimate_minmax, step_points, build_pins_segments,
                              fold_scatter, fold_bins, strip_runs, fold_strips,
                              label_step, compute_histogram_values,
                              find_nearest_sample,
                              compute_legend_layout, get_anchor_offset
import ..GraphicsModule: GraphicsCanvas, GraphicsRect, GraphicsLine, GraphicsText,
                         GraphicsCircle, GraphicsPolyline, GraphicsPolygon,
                         GraphicsViewport, layout_none
import ..StyleModule: StyleColor,
                      color_solarized_background_lighter, color_solarized_background_light,
                      color_solarized_content_dark, color_solarized_content_darker,
                      color_solarized_blue
import ..StyleModule: StyleFont, font_ubuntu_regular_14, font_ubuntu_bold_16
import ..EventModule: MousePress, MouseMove, MouseLeave, MouseDown, MouseUp,
                      MouseScroll, KeyDown, KeyPress
import ..OperationModule: Operation, ReplaceSelectionOperation,
                          ReplaceReferencedValueOperation, CompoundOperation
import ..ReferenceModule: get_reference_node_type, EmptyReference
export ChartPlotToGraphicsCanvas, ChartPlotToGraphicsCanvasIoMap, resolve_view,
       get_legend_item_rects, get_chart_part_reference, get_chart_series_reference
export ChartDocument, Chart, ChartNothing, ChartPlot, ChartAxis, ChartCategoryAxis, ChartLegend, ChartStyle, ChartLineSeries, ChartScatterSeries, ChartBarSeries, ChartHistogramSeries, ChartStripSeries, strip_state_name


using ..CellModule
using ..CellStructModule
using ..ReferenceModule


"""
    ChartSampleReferenceStep(index)

References the `index`-th sample of a chart series — a point of a line or
scatter series, a bin of a histogram, a bar of a bar series. 1-based, like every
other index in the reference vocabulary.
"""
@cell_struct struct ChartSampleReferenceStep <: ReferenceStep
    index::Int
end

ReferenceModule.get_reference_step_kind(::ChartSampleReferenceStep) = :structural

Base.:(==)(a::ChartSampleReferenceStep, b::ChartSampleReferenceStep) = a.index == b.index

Base.show(io::IO, s::ChartSampleReferenceStep) = print(io, "sample(", s.index, ")")

# ── DSL registrations ──────────────────────────────────────────────────────

ReferenceModule.build_reference_step(::Val{:sample}, iex) =
    :($(GlobalRef(ChartModule, :ChartSampleReferenceStep))(Int($iex)))

function ReferenceModule.match_reference_step(::Val{:sample}, hex, argpats, rest_success, bound,
                                              gen_value_match, gen_path_match)
    inner, bound1 = gen_value_match(:($hex.index), argpats[1], rest_success, bound)
    ex = quote
        if $hex isa $(GlobalRef(ChartModule, :ChartSampleReferenceStep))
            $inner
        else
            _nomatch
        end
    end
    return ex, bound1
end


include("ChartDocument.jl")
include("ChartPlot.jl")
include("ChartToChartPlot.jl")
include("ChartPlotToGraphics.jl")

end # module
