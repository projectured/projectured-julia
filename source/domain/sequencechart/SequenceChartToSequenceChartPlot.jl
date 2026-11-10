# Fragment of `SequenceChartModule`.
#
# SequenceChart → SequenceChartPlot: the first stage of the sequence chart
# pipeline, and a thin one. It wraps the semantic chart in the presentation
# document carrying the view window, the pointer and the hover, so the
# renderer downstream has one place to read all of it and the chart itself
# stays pure content.
#
# The `SequenceChartPlot` is built once per projection setup and keeps its
# identity, so the window survives a data change: appending events invalidates the
# geometry beneath it without disturbing where the reader had scrolled to. The
# buttons and the bars of the plot are built with it, for the same reason.
#
# Selection peels exactly the one step this stage owns — `chart` — and hands the
# rest through unchanged, so a selection naming an event or a lane round-trips
# through the whole pipeline.
"""
    SequenceChartToSequenceChartPlot()

The chart → plot stage. Stateless; all the state it produces lives on the
`SequenceChartPlot` it emits.
"""
struct SequenceChartToSequenceChartPlot <: Projection end

@iomap struct SequenceChartToSequenceChartPlotIoMap
    projection::Any
    input::Any
    output::Any
end

# Every sequence-chart root wraps the same way — a `SequenceChartNothing`
# placeholder is still something the renderer has to draw (as an empty chart),
# so it gets a plot too rather than being special-cased into a second pipeline.
function print_document(p::SequenceChartToSequenceChartPlot, recursion,
                        chart::Union{SequenceChart, SequenceChartNothing, SequenceChartInsertion},
                        ctx)
    iomap_cell = Cell(nothing)
    toolbar_cell, time_cell, lane_cell = Cell(nothing), Cell(nothing), Cell(nothing)
    plot = SequenceChartPlot(
        Cell(chart),
        Cell(nothing), Cell(false), Cell(0),
        Cell(nothing),
        Cell(nothing), Cell(nothing),
        toolbar_cell, time_cell, lane_cell,
        Cell(@computation let im = iomap_cell[]
            im === nothing ? nothing : map_reference_forward(p, im, chart.selection)
        end),
        Cell(@computation map_mouse_target_forward(chart, path -> let im = iomap_cell[]
            im === nothing ? nothing : map_reference_forward(p, im, path)
        end)))
    # The buttons and the bars belong to this plot, and each of their parts holds
    # the part of the mouse target of the plot below it, so the part under the
    # pointer lights.
    for (cell, field, part) in ((toolbar_cell, "toolbar", make_sequence_chart_buttons(plot)),
                                (time_cell, "time_scroll_bar", make_sequence_chart_scroll_bar(plot, :time)),
                                (lane_cell, "lane_scroll_bar", make_sequence_chart_scroll_bar(plot, :lanes)))
        cell[] = part
        follow_output_mouse_target!(part, () -> find_drawn_child_path(get_mouse_target(plot),
                                                                      (FieldReferenceStep(field),)))
    end
    iomap = SequenceChartToSequenceChartPlotIoMap(p, chart, plot)
    iomap_cell[] = iomap
    iomap
end

# The fields of a plot that hold the parts that only the plot has: the buttons and
# the bars.
const _PLOT_PART_FIELDS = ("toolbar", "time_scroll_bar", "lane_scroll_bar")

# Whether `path`, a path in a plot, goes into the buttons or a bar.
_is_plot_part_path(path) =
    any(field -> find_drawn_child_path(path, (FieldReferenceStep(field),)) !== nothing, _PLOT_PART_FIELDS)

# anything... ↔ chart.anything...
#
# The `chart` step carries the node type of whatever root this actually is —
# spelling `::SequenceChart` literally would leave the step under-typed for a
# `SequenceChartNothing` root, and every step of a reference has to name the type
# of the node it reaches or evaluating the path later fails. The type comes from
# `get_reference_node_type`, not `typeof`: a `@document` builds a
# kind-parameterized struct, and the reference vocabulary is written in the bare
# wrapper names.
function map_reference_forward(p::SequenceChartToSequenceChartPlot, iomap, reference)
    # No selection maps to no selection: the tail-binding pattern below would
    # otherwise match `nothing` and try to splice it into a path.
    reference === nothing && return nothing
    # A part that only the plot holds, a button or a bar, comes back from the chart
    # as an introduced reference.
    introduced = find_introduced_path(p, reference)
    introduced === nothing || return introduced
    ct = get_reference_node_type(iomap.input)
    @reference_case reference begin
        ∅ => @reference ::SequenceChartPlot
        rest... => (@reference ::SequenceChartPlot.chart::ct.^(rest))
    end
end

function map_reference_backward(p::SequenceChartToSequenceChartPlot, iomap, reference)
    reference === nothing && return nothing
    # A button and a bar have no place in the chart: the chart names them by an
    # introduced reference, which the forward map gives back.
    _is_plot_part_path(reference) && return make_introduced_reference(p, iomap, reference)
    @reference_case reference begin
        ∅ => @reference ::SequenceChart
        ::SequenceChartPlot.chart.rest... => (@reference ^(rest))
        __ => nothing
    end
end
