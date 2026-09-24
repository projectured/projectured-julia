# Fragment of `ProjectionAlgebraModule`.
#
# Domain-independent projection that focuses on a specific sub-document by
# navigating into the input using a configurable reference path.
"""
    FocusingProjection(; part_type=Any, part=EmptyReference())

A generic projection that focuses on a specific sub-document by navigating
into the input along `part` (a `Reference`). Only sub-documents whose
type is a subtype of `part_type` may be targeted.

# Example

    fp = FocusingProjection(part_type=Vector, part=Reference(PositionReferenceStep(1)))
    iomap = print_document(fp, nothing, [[1, 2], [3, 4]], nothing)
    iomap.output  # [1, 2]
"""
@projection struct FocusingProjection
    part_type::Any = Any
    part::Reference = EmptyReference()
end

function print_document(p::FocusingProjection, recursion, input, ctx)
    # Stable iomap; `output` is a computed cell, so a `part` change (or a change to
    # the input under `part`) re-derives the focused sub-document reactively without
    # replacing the iomap (PAR-STABLE-IOMAP-IDENTITY) — which is what lets Focusing
    # sit in a chain and have downstream stages wire to this iomap. The cursor rides
    # the `map_reference_forward` composition, so the sub-document's own selection is
    # left untouched.
    SimpleIoMap(p, input, Cell(@computation evaluate_reference(input, p.part)))
end

function map_reference_forward(p::FocusingProjection, iomap, reference)
    _strip_prefix(strip_reference_types(reference), p.part)   # selections are canonical
end

function map_reference_backward(p::FocusingProjection, iomap, reference)
    _concat(p.part, reference)
end

"""
    ReplaceFocusPartOperation(projection, part)

Operation that replaces the focus `part` of a `FocusingProjection`. Writes the
projection's `part` cell, so its reactive `output` re-derives to the new focus and
the change propagates through the existing iomap without re-printing.
"""
struct ReplaceFocusPartOperation <: Operation
    projection::FocusingProjection
    part::Reference
end

function evaluate_operation(editor, op::ReplaceFocusPartOperation)
    op.projection.part = op.part
end

function read_intent(p::FocusingProjection, iomap::SimpleIoMap, event::ReplaceSelectionOperation)
    input_selection = map_reference_backward(p, iomap, event.path)
    input_selection === nothing && return nothing
    return ReplaceSelectionOperation(input_selection)
end

# Own gestures, reified as a `get_projection_gesture_bindings` table so the firing path (via
# `read_projection_gesture`) is the one a listing shows. Focus-out is
# gated by `applicable` (so its op may assume a non-empty part); focus-in
# self-declines in its operation (no selection, or no deeper part of the right
# type). ModifierKeys are matched exactly.
function get_projection_gesture_bindings(p::FocusingProjection, iomap)
    GestureBinding[
        GestureBinding(KeyDownPattern(:comma; modifiers = [:ctrl]),
                       (doc, event) -> ReplaceFocusPartOperation(p, _drop_last(p.part));
                       applicable = (doc, sel) -> !isempty(p.part),
                       description = "Focus out", domain = "focus"),
        GestureBinding(KeyDownPattern(:period; modifiers = [:ctrl]),
                       (doc, event) -> _focus_in(p, iomap); description = "Focus in",
                       domain = "focus"),
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

function _drop_last(path::ConcreteReference)
    tail = path.tail
    tail isa EmptyReference ? EmptyReference() : ConcreteReference(path.head, _drop_last(tail))
end

function _longest_prefix_of_type(document, sel::Reference, part_type)
    best = nothing
    path = EmptyReference()
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
