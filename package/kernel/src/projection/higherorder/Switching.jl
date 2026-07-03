"""
    SwitchingProjectionModule

A higher-order projection that holds a list of projections and delegates
to the one selected by a reactive index cell. Changing the index cell
switches which branch is active on the next projection_print call.
"""
module SwitchingProjectionModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..ChangeModule: Change
import ..ReactiveModule: Cell
import ..IoMapApiModule: IoMap
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

The `index` is a `Cell{Int}` whose value is read on every `projection_print`
call, so the active branch can be changed at any time by writing to the cell:

    ap.index[] = 2   # switch to the second projection

# Example

    index = Cell(1)
    ap = SwitchingProjection(
        [JsonToSyntax(), XmlToSyntax()],
        index
    )
    result = projection_print(ap, json_doc)   # uses JsonToSyntax
    index[] = 2
    result = projection_print(ap, xml_doc)    # uses XmlToSyntax
"""
struct SwitchingProjection <: Projection
    projections::Vector{Any}
    index::Cell
    SwitchingProjection(projections::Vector{Any}, index::Cell) = new(projections, index)
end

SwitchingProjection(projections::Vector{Any}, index::Int=1) =
    SwitchingProjection(projections, Cell(index))

"""
    projection_print(ap::SwitchingProjection, recursion, input, ctx) -> SwitchingProjectionIoMap

Apply the projection at the current index, wrapping its IoMap so the reader
knows which branch was active.
"""
function projection_print(ap::SwitchingProjection, recursion, input, ctx)
    i = ap.index[]
    inner_iomap = projection_print(ap.projections[i], recursion, input, ctx)
    return SwitchingProjectionIoMap(ap, input, inner_iomap.output, i, inner_iomap)
end

"""
    projection_read(ap::SwitchingProjection, iomap::SwitchingProjectionIoMap, event)

Delegate to the same branch that was active when the IoMap was produced.
"""
projection_read(ap::SwitchingProjection, recursion, change::Change, iomap::SwitchingProjectionIoMap) =
    projection_read(ap.projections[iomap.index], recursion, change, iomap.inner_iomap)

projection_read(ap::SwitchingProjection, iomap::SwitchingProjectionIoMap, payload) =
    projection_read(ap, nothing, Change(payload), iomap).operation

function map_reference_forward(::SwitchingProjection, iomap, reference)
    return nothing
end

function map_reference_backward(::SwitchingProjection, iomap, reference)
    return nothing
end

end # module
