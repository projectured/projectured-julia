"""
    SequenceChartToSequenceChartPlotModule

SequenceChart → SequenceChartPlot: the first stage of the sequence chart
pipeline, and a thin one. It wraps the semantic chart in the presentation
document carrying the view window, the pointer, the hover and any drag in
progress, so the renderer downstream has one place to read all of it and the
chart itself stays pure content.

The `SequenceChartPlot` is built once per projection setup and keeps its
identity, so the window survives a data change: appending events invalidates the
geometry beneath it without disturbing where the reader had scrolled to.

Selection peels exactly the one step this stage owns — `chart` — and hands the
rest through unchanged, so a selection naming an event or a lane round-trips
through the whole pipeline.
"""
module SequenceChartToSequenceChartPlotModule

import ..CellModule: Cell, ComputedCell
import ..ProjectionApiModule: print_document, map_reference_forward,
                              map_reference_backward, Projection
import ..SequenceChartModule: SequenceChart, SequenceChartNothing, SequenceChartInsertion
import ..SequenceChartPlotModule: SequenceChartPlot
import ..IoMapModule: IoMap, var"@iomap"
import ..ReferenceModule: get_reference_node_type
import ..ReferenceModule: var"@reference"
import ..ReferenceModule: var"@reference_case"

export SequenceChartToSequenceChartPlot, SequenceChartToSequenceChartPlotIoMap

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
    plot = SequenceChartPlot(
        Cell(chart),
        Cell(nothing), Cell(false), Cell(0),
        Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing),
        ComputedCell(() -> let im = iomap_cell[]
            im === nothing ? nothing : map_reference_forward(p, im, chart.selection)
        end))
    iomap = SequenceChartToSequenceChartPlotIoMap(p, chart, plot)
    iomap_cell[] = iomap
    iomap
end

# anything... ↔ chart.anything...
#
# The `chart` step carries the node type of whatever root this actually is —
# spelling `::SequenceChart` literally would leave the step under-typed for a
# `SequenceChartNothing` root, and every step of a reference has to name the type
# of the node it reaches or evaluating the path later fails. The type comes from
# `get_reference_node_type`, not `typeof`: a `@document` builds a
# kind-parameterized struct, and the reference vocabulary is written in the bare
# wrapper names.
function map_reference_forward(::SequenceChartToSequenceChartPlot, iomap, reference)
    # No selection maps to no selection: the tail-binding pattern below would
    # otherwise match `nothing` and try to splice it into a path.
    reference === nothing && return nothing
    ct = get_reference_node_type(iomap.input)
    @reference_case reference begin
        ∅ => @reference ::SequenceChartPlot
        rest... => (@reference ::SequenceChartPlot.chart::ct.^(rest))
    end
end

function map_reference_backward(::SequenceChartToSequenceChartPlot, iomap, reference)
    reference === nothing && return nothing
    @reference_case reference begin
        ∅ => @reference ::SequenceChart
        ::SequenceChartPlot.chart.rest... => (@reference ^(rest))
        __ => nothing
    end
end

end # module
