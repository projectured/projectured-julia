"""
    SwitchingProjectionModule

A higher-order projection that holds a list of projections and delegates
to the one selected by a reactive index cell. Writing the index cell
reactively switches the active branch through the *same* iomap: the inner
iomap is reconciled by index and the output re-derives, no re-print required.
"""
module SwitchingProjectionModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..IntentModule: Intent
import ..CellModule: Cell, ComputedCell
import ..IoMapModule: IoMap, var"@iomap", reconcile_child_iomap
export SwitchingProjection, SwitchingProjectionIoMap

# `inner_iomap` is reconciled by the (reactive) index and `output` forwards its
# output through a cell, so writing `ap.index` swaps the branch through the same
# iomap (AR-STABLE-IOMAP-IDENTITY); `iomap.index` reads the current index.
@iomap struct SwitchingProjectionIoMap
    projection::Any
    input::Any
    output::Any
    index::Any
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
    # Reconcile the active branch by the reactive index: writing `ap.index`
    # rebuilds `inner` and re-derives `output` through the same iomap; a
    # same-index input change reuses the cached inner (which reacts on its own).
    inner = reconcile_child_iomap(() -> ap.index[],
                i -> print_document(ap.projections[i], recursion, input, ctx))
    output = ComputedCell(() -> inner[].output)
    return SwitchingProjectionIoMap(ap, input, output, ap.index, inner)
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
