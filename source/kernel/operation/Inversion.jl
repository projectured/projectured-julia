# Fragment of `OperationModule` — the way back: the inverses and the slot seam.

# The default: an operation nobody taught to invert has no way back. A caller
# that records a history marks the point and refuses to undo past it.
make_inverse_operation(document, operation) = nothing

# An inverse needs the state the change starts from, so it is taken BEFORE the
# change is applied. That is also why a container operation is not inverted in one
# piece: the inverse of the second member of a `CompoundOperation` depends on what
# the first member did. `evaluate_invertible_operation!` interleaves the two, and
# is open so a container type of a higher package adds its own method.
function evaluate_invertible_operation!(editor, operation)
    inverse = make_inverse_operation(editor.document, operation)
    evaluate_operation(editor, operation)
    inverse
end

# Each member is inverted against the state that member sees, and the inverses
# run in the opposite order. A member with no way back makes the whole step one
# with no way back; the members that already ran stay applied, so the document is
# right and only the way back is gone.
function evaluate_invertible_operation!(editor, op::CompoundOperation)
    inverses = Any[]
    lost = false
    for member in op.operations
        inverse = evaluate_invertible_operation!(editor, member)
        inverse === nothing ? (lost = true) : pushfirst!(inverses, inverse)
    end
    lost ? nothing : CompoundOperation(inverses)
end

get_slot_at(container, index::Integer) = container[index]

# ── The inverses of this layer's operations ─────────────────────────────────
#
# The operations of a higher package declare their own inverses beside their own
# declarations, exactly as they declare `reroot_operation` there. The methods here
# cover the operations this layer owns.

make_inverse_operation(document, operation::DoNothingOperation) = operation

# An operation that changes no document: the way back is to do nothing.
make_inverse_operation(document, ::QuitEditorOperation) = DoNothingOperation()
make_inverse_operation(document, ::InvalidateProjectionOperation) = DoNothingOperation()
make_inverse_operation(document, ::SetTimerOperation) = DoNothingOperation()

# A wrapper's way back is the way back of what it holds, unless the wrapper says
# otherwise. A wrapper that keeps state of its own — a buffer that records — adds
# its own method, because putting its state back is part of the way back.
make_inverse_operation(document, op::WrappingOperation) =
    make_inverse_operation(document, get_wrapped_operation(op))

# Flipping the same node again is the way back. A `nothing` target was never
# resolved, so there is no node to flip.
make_inverse_operation(document, op::ToggleCollapseOperation) =
    op.target === nothing ? nothing : op

# Both move the selection, so both are taken back by putting the selection where
# it is now. A document with no live selection has nothing to restore.
make_inverse_operation(document, ::Union{ReplaceSelectionOperation,
                                         SelectNextInsertionOperation}) =
    _make_selection_inverse(document)

# The pointer is where the person put it, and taking an edit back does not move
# it, so the way back from a move of the mouse target is to do nothing.
make_inverse_operation(document, ::ReplaceMouseTargetOperation) = DoNothingOperation()

# The selection chain is live, so the path is copied rather than held: see
# `copy_reference`.
function _make_selection_inverse(document)
    path = get_selection(document)
    path === nothing && return DoNothingOperation()
    ReplaceSelectionOperation(copy_reference(path))
end

# ── The inverse of the generic write ────────────────────────────────────────

function make_inverse_operation(document, op::ReplaceReferencedValueOperation)
    reference = strip_reference_types(op.reference)
    root = op.document === nothing ? document : op.document
    if reference isa EmptyReference
        # A carried cell holds its root: put back what it holds now.
        op.document isa AbstractCell &&
            return ReplaceReferencedValueOperation(op.document, EmptyReference(),
                                                   op.document[])
        # A whole-root swap, and only a document-rooted one has a root to swap:
        # put the root that is there now back.
        op.document === nothing || return nothing
        return ReplaceReferencedValueOperation(nothing, EmptyReference(), root)
    end
    parent_path, terminal = _split_terminal_step(reference)
    top = unwrap_cell(root)
    parent = parent_path isa EmptyReference ? top :
             try_evaluate_reference(top, parent_path)
    parent === nothing && return nothing
    inverse = _make_slot_inverse(op, parent, terminal, op.value)
    (inverse !== nothing && _is_plain_slot(parent, terminal)) || return inverse
    _anchor_plain_inverse(root, reference, inverse)
end

# The way back of a write into a slot of a plain value carries the holder of the
# nearest cell above it, and not the parent. A copy replaces an immutable
# parent, so that parent is gone when the way back runs; and only a write that
# goes through the cell tells the readers of a mutable one. With no cell above,
# the way back names the parent.
function _anchor_plain_inverse(root, reference::ConcreteReference, inverse)
    anchor = _find_cell_anchor(root, reference)
    anchor === nothing && return inverse
    steps = get_reference_steps(anchor.reference)
    ReplaceReferencedValueOperation(anchor.holder,
        Reference(steps[1:end-1]..., get_reference_steps(inverse.reference)...),
        inverse.value)
end

# Every one of these answers an operation that CARRIES THE OBJECT it writes into,
# rather than a path to it. The object is in hand — the inverse had to resolve it
# to read the old value — and a carried root is what makes an entry survive the
# document moving in the tree: a path from the editor's root goes stale when a tab
# is dragged or a pane is split, and an object does not.
#
# It is also more truthful. A history is taken back newest first, so by the time
# this entry is applied every later entry has been applied, and those restored the
# very objects this one names.

# A field write: put back what the field holds now.
_make_slot_inverse(op::ReplaceReferencedValueOperation, parent,
                   step::AFieldReferenceStep, value) =
    hasfield(typeof(parent), Symbol(step.name)) ?
        ReplaceReferencedValueOperation(parent, Reference(step),
                                        getproperty(parent, Symbol(step.name))) :
        nothing

# An element overwrite. A collection can write a value into the slot that is
# there, and then a kept slot holds the new value when the way back runs, so the
# way back holds the value that is there now. A cell replaces the slot, so the
# way back of a cell holds the slot that is there now.
function _make_slot_inverse(op::ReplaceReferencedValueOperation, parent,
                            step::ARangeReferenceStep, value)
    index = step.start + 1
    (index < 1 || index > length(parent)) && return nothing
    old = value isa AbstractCell ? get_slot_at(parent, index) : parent[index]
    ReplaceReferencedValueOperation(parent, Reference(step), old)
end

# A splice: the write replaces `[start, stop)` with `n` items, so the way back
# replaces `[start, start + n)` with the slots that are there now. A zero-width
# range with items is an insert, and its inverse is a delete; an empty item
# vector is a delete, and its inverse is an insert. One rule covers all three.
function _make_slot_inverse(op::ReplaceReferencedValueOperation, parent,
                            step::ARangeReferenceStep, value::AbstractVector)
    (step.start < 0 || step.stop > length(parent) || step.stop < step.start) &&
        return nothing
    old = Any[get_slot_at(parent, index) for index in (step.start + 1):step.stop]
    ReplaceReferencedValueOperation(parent,
        Reference(RangeReferenceStep(step.start, step.start + length(value))), old)
end
