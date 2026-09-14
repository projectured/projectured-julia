"""
    DraggingModule

`DraggingState` — a transparent wrapper marking a sub-tree as a drag-and-drop
reorder region. Actual gesture interpretation lives in `DraggingProjection`.
"""
module DraggingModule

using ..CellModule
using ..DocumentModule
using ..ReferenceModule
export DraggingDocument
using ..ProjectionModule
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
using ..IntentModule
using ..IoMapModule
using ..CollectionModule
using ..OperationModule
import ..OperationModule: evaluate_operation
using ..EventModule
export DraggingProjection, DraggingIoMap, MoveRangeOperation
export make_dragging_document, make_dragging_projection
export DraggingState




abstract type DraggingDocument <: Document end

"""
Transparent wrapper around `content`; `threshold` is the pixel distance a
press must travel before it becomes a drag (below it, the press falls through
as a normal click).
"""
@document struct DraggingState <: DraggingDocument
    content::Document
    threshold::Int = 5
end


include("Dragging.jl")
include("DraggingWrapper.jl")

end # module
