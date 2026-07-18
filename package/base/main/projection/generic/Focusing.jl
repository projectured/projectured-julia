"""
    FocusingProjectionModule

Domain-independent projection that focuses on a specific sub-document by
navigating into the input using a configurable reference path.
"""
module FocusingProjectionModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..OperationModule: Operation, evaluate_operation
import ..OperationModule: ReplaceSelectionOperation
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, EmptyReferencePath, evaluate_reference, extend_reference, strip_reference_types
import ..IoMapModule: SimpleIoMap
import ..CellModule: set_cell_function!
import ..GestureBindingModule: GestureBinding
import ..EventPatternModule: KeyDownPattern
import ..ProjectionGestureBindingsModule: get_projection_gesture_bindings, read_projection_gesture

export FocusingProjection, ReplaceFocusPartOperation

"""
    FocusingProjection(; part_type=Any, part=EmptyReferencePath())

A generic projection that focuses on a specific sub-document by navigating
into the input along `part` (a `ReferencePath`). Only sub-documents whose
type is a subtype of `part_type` may be targeted.

# Example

    fp = FocusingProjection(part_type=Vector, part=ReferencePath(PositionReferenceStep(1)))
    iomap = print_document(fp, nothing, [[1, 2], [3, 4]], nothing)
    iomap.output  # [1, 2]
"""
mutable struct FocusingProjection <: Projection
    part_type::Any
    part::ReferencePath
    part_evaluator::Function
end

FocusingProjection(; part_type=Any, part::ReferencePath=EmptyReferencePath()) =
    FocusingProjection(part_type, part, document -> evaluate_reference(document, part))

function print_document(p::FocusingProjection, recursion, input, ctx)
    output = p.part_evaluator(input)
    iomap = SimpleIoMap(p, input, output)
    # Forward-project the input selection onto the output sub-document so that
    # downstream projections can render a cursor after set_selection! on the
    # input. Lazy: re-derived whenever input.selection changes. Mirrors the
    # SearchingProjection pattern.
    if hasproperty(output, :selection)
        set_cell_function!(getfield(output, :selection), () -> begin
            sel = hasfield(typeof(input), :selection) ? input.selection : nothing
            sel === nothing && return nothing
            map_reference_forward(p, iomap, sel)
        end)
    end
    iomap
end

function map_reference_forward(p::FocusingProjection, iomap, reference)
    _strip_prefix(p.part, strip_reference_types(reference))   # selections are canonical
end

function map_reference_backward(p::FocusingProjection, iomap, reference)
    _concat_path(p.part, reference)
end

"""
    ReplaceFocusPartOperation(projection, part)

Operation that replaces the focus `part` of a `FocusingProjection`.
When evaluated, updates both `projection.part` and `projection.part_evaluator`
so that subsequent `print_document` calls navigate to the new `part`.
"""
struct ReplaceFocusPartOperation <: Operation
    projection::FocusingProjection
    part::ReferencePath
end

function evaluate_operation(editor, op::ReplaceFocusPartOperation)
    op.projection.part = op.part
    op.projection.part_evaluator = document -> evaluate_reference(document, op.part)
end

function read_intent(p::FocusingProjection, iomap::SimpleIoMap, event::ReplaceSelectionOperation)
    input_selection = map_reference_backward(p, iomap, event.path)
    input_selection === nothing && return nothing
    return ReplaceSelectionOperation(input_selection)
end

# Own gestures, reified as a `get_projection_gesture_bindings` table so the firing path (via
# `read_projection_gesture`) is the one `collect_gesture_bindings` shows. Focus-out is
# gated by `applicable` (so its op may assume a non-empty part); focus-in
# self-declines in its operation (no selection, or no deeper part of the right
# type). ModifierKeys are matched exactly.
function get_projection_gesture_bindings(p::FocusingProjection, iomap)
    GestureBinding[
        GestureBinding(KeyDownPattern(:comma, [:ctrl], nothing),
            (doc, event) -> ReplaceFocusPartOperation(p, _drop_last(p.part)),
            (doc, sel) -> !isempty(p.part), "Focus out", "focus"),
        GestureBinding(KeyDownPattern(:period, [:ctrl], nothing),
            (doc, event) -> _focus_in(p, iomap),
            (doc, sel) -> true, "Focus in", "focus"),
    ]
end

# Focus in: descend the focus to the longest prefix of the input's selection whose
# target is of `part_type`. Declines (nothing) with no selection or no such prefix.
function _focus_in(p::FocusingProjection, iomap)
    hasproperty(iomap.input, :selection) || return nothing
    sel = iomap.input.selection
    (sel === nothing || isempty(sel)) && return nothing
    new_part = _longest_prefix_of_type(iomap.input, sel, p.part_type)
    new_part === nothing ? nothing : ReplaceFocusPartOperation(p, new_part)
end

read_intent(p::FocusingProjection, iomap::SimpleIoMap, event) =
    read_projection_gesture(p, iomap, event)

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
        path = extend_reference(path, step)
        # `missing` (not `nothing`): a path that resolves to an empty field *is* a
        # resolution, and must not end the walk.
        node = try_evaluate_reference(document, path, missing)
        node === missing && break
        node isa part_type && (best = path)
    end
    best
end

end # module
