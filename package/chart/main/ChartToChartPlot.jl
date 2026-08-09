"""
    ChartToChartPlotModule

Chart → ChartPlot: the first stage of the chart pipeline, and a thin one. It
wraps the semantic chart in the presentation document that carries the view
window, the pointer, the hover and any in-progress drag, so the renderer
downstream has one place to read all of it and the chart itself stays pure
content.

The `ChartPlot` is built once per projection setup and keeps its identity, so
zooming survives a data change: replacing a column invalidates the geometry
cells beneath it without disturbing the window someone had scrolled to.

Selection peels exactly the one step this stage owns — `chart` — and hands the
rest through unchanged, so a selection into a series or an axis round-trips
through the whole pipeline (tutorial School A).
"""
module ChartToChartPlotModule

import ..CellModule: Cell, ComputedCell
import ..ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..ChartModule: Chart, ChartDocument, ChartNothing, ChartInsertion
import ..ChartPlotModule: ChartPlot
import ..IoMapModule: IoMap, var"@iomap"
import ..ReferenceModule: ConcreteReference, FieldReferenceStep, EmptyReference,
                          get_reference_node_type
import ..ReferenceModule: var"@reference", var"@reference_step"
import ..ReferenceModule: var"@reference_case"

export ChartToChartPlot, ChartToChartPlotIoMap

"""
    ChartToChartPlot()

The chart → plot stage. Stateless; all the state it produces lives on the
`ChartPlot` it emits.
"""
struct ChartToChartPlot <: Projection end

@iomap struct ChartToChartPlotIoMap
    projection::Any
    input::Any
    output::Any
end

# Every chart-domain root wraps the same way — a `ChartNothing` placeholder is
# still something the renderer has to draw (as an empty chart), so it gets a
# plot too rather than being special-cased into a second pipeline.
function print_document(p::ChartToChartPlot, recursion,
                        chart::Union{Chart, ChartNothing, ChartInsertion}, ctx)
    iomap_cell = Cell(nothing)
    plot = ChartPlot(
        Cell(chart),
        Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing),
        ComputedCell(() -> let im = iomap_cell[]
            im === nothing ? nothing : map_reference_forward(p, im, chart.selection)
        end))
    iomap = ChartToChartPlotIoMap(p, chart, plot)
    iomap_cell[] = iomap
    iomap
end

# anything... ↔ chart.anything...
#
# The `chart` step carries the node type of whatever root this actually is —
# spelling `::Chart` literally would leave the step under-typed for a
# `ChartNothing` root, and every step of a reference has to name the type of the
# node it reaches or evaluating the path later fails. The type comes from
# `get_reference_node_type`, not `typeof`: a `@document` builds a
# kind-parameterized struct, and the reference vocabulary is written in the bare
# wrapper names.
function map_reference_forward(::ChartToChartPlot, iomap, reference)
    # No selection maps to no selection: the tail-binding pattern below would
    # otherwise match `nothing` and try to splice it into a path.
    reference === nothing && return nothing
    ct = get_reference_node_type(iomap.input)
    @reference_case reference begin
        ∅ => @reference ::ChartPlot
        rest... => (@reference ::ChartPlot.chart::ct.^(rest))
    end
end

function map_reference_backward(::ChartToChartPlot, iomap, reference)
    reference === nothing && return nothing
    @reference_case reference begin
        ∅ => @reference ::Chart
        ::ChartPlot.chart.rest... => (@reference ^(rest))
        __ => nothing
    end
end

end # module
