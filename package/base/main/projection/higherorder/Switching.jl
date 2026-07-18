"""
    SwitchingProjectionModule

A higher-order projection that holds a list of projections and delegates
to the one selected by a reactive index cell. Changing the index cell
switches which branch is active on the next print_document call.
"""
module SwitchingProjectionModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..IntentModule: Intent
import ..CellModule: Cell
import ..IoMapModule: IoMap
export SwitchingProjection, SwitchingProjectionIoMap

struct SwitchingProjectionIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    index::Int
    inner_iomap::Any
end

"""
    SwitchingProjection(projections, index)

A compound higher-order projection that selects one projection from a list
by index and delegates all print and read operations to it.

The `index` is a `Cell{Int}` whose value is read on every `print_document`
call, so the active branch can be changed at any time by writing to the cell:

    ap.index[] = 2   # switch to the second projection

# Example

    index = Cell(1)
    ap = SwitchingProjection(
        [JsonToSyntax(), XmlToSyntax()],
        index
    )
    result = print_document(ap, json_doc)   # uses JsonToSyntax
    index[] = 2
    result = print_document(ap, xml_doc)    # uses XmlToSyntax
"""
struct SwitchingProjection <: Projection
    projections::Vector{Any}
    index::Cell
    SwitchingProjection(projections::Vector{Any}, index::Cell) = new(projections, index)
end

SwitchingProjection(projections::Vector{Any}, index::Int=1) =
    SwitchingProjection(projections, Cell(index))

"""
    print_document(ap::SwitchingProjection, recursion, input, ctx) -> SwitchingProjectionIoMap

Apply the projection at the current index, wrapping its IoMap so the reader
knows which branch was active.
"""
function print_document(ap::SwitchingProjection, recursion, input, ctx)
    i = ap.index[]
    inner_iomap = print_document(ap.projections[i], recursion, input, ctx)
    return SwitchingProjectionIoMap(ap, input, inner_iomap.output, i, inner_iomap)
end

"""
    read_intent(ap::SwitchingProjection, iomap::SwitchingProjectionIoMap, event)

Delegate to the same branch that was active when the IoMap was produced.
"""
read_intent(ap::SwitchingProjection, recursion, change::Intent, iomap::SwitchingProjectionIoMap) =
    read_intent(ap.projections[iomap.index], recursion, change, iomap.inner_iomap)

read_intent(ap::SwitchingProjection, iomap::SwitchingProjectionIoMap, payload) =
    read_intent(ap, nothing, Intent(payload), iomap).operation

function map_reference_forward(::SwitchingProjection, iomap, reference)
    return nothing
end

function map_reference_backward(::SwitchingProjection, iomap, reference)
    return nothing
end

end # module
