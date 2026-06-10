"""
    AlternativeProjectionModule

A higher-order projection that holds a list of projections and delegates
to the one selected by a reactive index cell. Changing the index cell
switches which branch is active on the next projection_print call.
"""
module AlternativeProjectionModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection, Change, as_change
import ..ReactiveModule: Cell
import ..IoMapApiModule: IoMap
export AlternativeProjection, AlternativeProjectionIoMap

struct AlternativeProjectionIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    index::Int
    inner_iomap::Any
end

"""
    AlternativeProjection(projections, index)

A compound higher-order projection that selects one projection from a list
by index and delegates all print and read operations to it.

The `index` is a `Cell{Int}` whose value is read on every `projection_print`
call, so the active branch can be changed at any time by writing to the cell:

    ap.index[] = 2   # switch to the second projection

# Example

    index = Cell(1)
    ap = AlternativeProjection(
        [JsonToSyntax(), XmlToSyntax()],
        index
    )
    result = projection_print(ap, json_doc)   # uses JsonToSyntax
    index[] = 2
    result = projection_print(ap, xml_doc)    # uses XmlToSyntax
"""
struct AlternativeProjection <: Projection
    projections::Vector{Any}
    index::Cell
    AlternativeProjection(projections::Vector{Any}, index::Cell) = new(projections, index)
end

AlternativeProjection(projections::Vector{Any}, index::Int=1) =
    AlternativeProjection(projections, Cell(index))

"""
    projection_print(ap::AlternativeProjection, recursion, input, ctx) -> AlternativeProjectionIoMap

Apply the projection at the current index, wrapping its IoMap so the reader
knows which branch was active.
"""
function projection_print(ap::AlternativeProjection, recursion, input, ctx)
    i = ap.index[]
    inner_iomap = projection_print(ap.projections[i], recursion, input, ctx)
    return AlternativeProjectionIoMap(ap, input, inner_iomap.output, i, inner_iomap)
end

"""
    projection_read(ap::AlternativeProjection, iomap::AlternativeProjectionIoMap, event)

Delegate to the same branch that was active when the IoMap was produced.
"""
projection_read(ap::AlternativeProjection, recursion, change::Change, iomap::AlternativeProjectionIoMap) =
    projection_read(ap.projections[iomap.index], recursion, change, iomap.inner_iomap)

projection_read(ap::AlternativeProjection, iomap::AlternativeProjectionIoMap, payload) =
    projection_read(ap, nothing, as_change(payload), iomap).operation

function map_reference_forward(::AlternativeProjection, iomap, reference)
    return nothing
end

function map_reference_backward(::AlternativeProjection, iomap, reference)
    return nothing
end

end # module
