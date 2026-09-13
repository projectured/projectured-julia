"""
    DraggingModule

`DraggingState` — a transparent wrapper marking a sub-tree as a drag-and-drop
reorder region. Actual gesture interpretation lives in `DraggingProjection`.
"""
module DraggingModule

import ..CellModule: Cell, ComputedCell
import ..DocumentModule: Document, @document
import ..ReferenceModule: Reference
export DraggingDocument
import ..ProjectionApiModule: print_document, print_child, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..IntentModule: Intent
import ..IoMapModule: IoMap, var"@iomap", reconcile_child_iomap
import ..CollectionModule: CellVector, ComputedCellVector, get_cell_at
import ..ReferenceModule: Reference, EmptyReference, ConcreteReference,
                          RangeReferenceStep, FieldReferenceStep, is_element_reference_step, evaluate_reference,
                          head, tail
import ..OperationModule: ReplaceSelectionOperation
import ..OperationModule: Operation, evaluate_operation
import ..OperationModule: reroot_operation
import ..EventModule: MouseDown, MouseUp, MouseMove, MousePress
import ..EventModule: ModifierKeys
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
