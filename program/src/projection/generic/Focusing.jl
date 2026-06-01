"""
    FocusingProjectionModule

Domain-independent projection that focuses on a specific sub-document by
navigating into the input using a configurable reference path.
"""
module FocusingProjectionModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..OperationApiModule: Operation, evaluate_operation
import ..OperationModule: ReplaceSelectionOperation
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, EmptyReferencePath, evaluate_reference, append_reference
import ..IoMapModule: SimpleIoMap
import ..KeyboardModule: KeyDown, is_ctrl

export FocusingProjection, ReplaceFocusPartOperation

"""
    FocusingProjection(; part_type=Any, part=EmptyReferencePath())

A generic projection that focuses on a specific sub-document by navigating
into the input along `part` (a `ReferencePath`). Only sub-documents whose
type is a subtype of `part_type` may be targeted.

# Example

    fp = FocusingProjection(part_type=Vector, part=ReferencePath(PositionReference(1)))
    iomap = projection_print(fp, [[1, 2], [3, 4]], nothing, nothing)
    iomap.output  # [1, 2]
"""
mutable struct FocusingProjection <: Projection
    part_type::Any
    part::ReferencePath
    part_evaluator::Function
end

FocusingProjection(; part_type=Any, part::ReferencePath=EmptyReferencePath()) =
    FocusingProjection(part_type, part, document -> evaluate_reference(document, part))

function projection_print(p::FocusingProjection, input, recursion, ctx)
    output = p.part_evaluator(input)
    SimpleIoMap(p, input, output)
end

function map_reference_forward(p::FocusingProjection, iomap, reference)
    _strip_prefix(p.part, reference)
end

function map_reference_backward(p::FocusingProjection, iomap, reference)
    _concat_path(p.part, reference)
end

"""
    ReplaceFocusPartOperation(projection, part)

Operation that replaces the focus `part` of a `FocusingProjection`.
When evaluated, updates both `projection.part` and `projection.part_evaluator`
so that subsequent `projection_print` calls navigate to the new `part`.
"""
struct ReplaceFocusPartOperation <: Operation
    projection::FocusingProjection
    part::ReferencePath
end

function evaluate_operation(op::ReplaceFocusPartOperation, document)
    op.projection.part = op.part
    op.projection.part_evaluator = document -> evaluate_reference(document, op.part)
end

function projection_read(p::FocusingProjection, iomap::SimpleIoMap, event)
    if event isa ReplaceSelectionOperation
        input_selection = map_reference_backward(p, iomap, event.path)
        input_selection === nothing && return nothing
        return ReplaceSelectionOperation(input_selection)
    elseif event isa KeyDown && is_ctrl(event)
        if event.key == :comma
            isempty(p.part) && return nothing
            return ReplaceFocusPartOperation(p, _drop_last(p.part))
        elseif event.key == :period
            hasproperty(iomap.input, :selection) || return nothing
            sel = iomap.input.selection
            (sel === nothing || isempty(sel)) && return nothing
            new_part = _longest_prefix_of_type(iomap.input, sel, p.part_type)
            new_part === nothing && return nothing
            return ReplaceFocusPartOperation(p, new_part)
        end
    end
    return nothing
end

function _concat_path(prefix::EmptyReferencePath, suffix::ReferencePath)
    suffix
end

function _concat_path(prefix::ConcreteReferencePath, suffix::ReferencePath)
    ConcreteReferencePath(prefix.head, _concat_path(prefix.tail, suffix))
end

function _strip_prefix(::EmptyReferencePath, path::ReferencePath)
    path
end

function _strip_prefix(::ConcreteReferencePath, ::EmptyReferencePath)
    nothing
end

function _strip_prefix(prefix::ConcreteReferencePath, path::ConcreteReferencePath)
    prefix.head == path.head || return nothing
    _strip_prefix(prefix.tail, path.tail)
end

function _drop_last(path::ConcreteReferencePath)
    tail = path.tail
    tail isa EmptyReferencePath ? EmptyReferencePath() : ConcreteReferencePath(path.head, _drop_last(tail))
end

function _longest_prefix_of_type(document, sel::ReferencePath, part_type)
    best = nothing
    path = EmptyReferencePath()
    for step in sel
        path = append_reference(path, step)
        node = try evaluate_reference(document, path) catch; break end
        node isa part_type && (best = path)
    end
    best
end

end # module
