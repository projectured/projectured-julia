"""
    DraggingModule

`DraggingState` — a transparent wrapper marking a sub-tree as a drag-and-drop
reorder region. Actual gesture interpretation lives in `DraggingProjection`.
"""
module DraggingModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..EventModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..ProjectionModule
using ..ReferenceModule

# Imported to extend: this module adds a method to each of these.
import ..OperationModule: evaluate_operation, make_inverse_operation
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export DraggingDocument
export DraggingProjection, DraggingIoMap, MoveRangeOperation
export make_dragging_document, make_dragging_projection
export DraggingState


include("DraggingDocument.jl")
include("Dragging.jl")
include("DraggingWrapper.jl")

end # module
