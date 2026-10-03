# Fragment of `OperationModule` — the seams that rewrite the reference of an operation.

"""
    reroot_reference(ref, steps::Tuple) -> Reference

Prepend each step in `steps` (outermost first) to `ref`, producing a longer
`ConcreteReference`. Used by container readers that need to add several steps at
once (e.g. `elements[i].child`).
"""
function reroot_reference(ref::Reference, steps::Tuple)
    result = ref
    for step in reverse(steps)
        result = ConcreteReference(step, result)
    end
    result
end

# Reference/operation *re-rooting* shared by container readers: a container that
# routes a gesture into one of its children gets back an operation whose reference
# is rooted in the *child's* domain; to forward it up, the container prepends the
# step(s) that lead from itself to that child (e.g. `elements[i]`, `children[i]`).
#
# An operation that carries a path registers once, with the pair
# `operation_reference` / `retarget_operation`: the catch-all below reroots the
# reference that it reports, and the default `read_intent` maps the same reference
# back through a projection. An operation that reports no reference is returned
# unchanged. A `ReplacePathOperation` registers through `get_operation_path` and
# `make_path_operation`, and an operation that HOLDS another subtypes
# `WrappingOperation` and answers the two generics of that contract; each family
# has its one method below. See `documentation/package/kernel/operation.md`.
reroot_operation(::Nothing, steps::Tuple) = nothing
function reroot_operation(op, steps::Tuple)
    reference = operation_reference(op)
    reference === nothing && return op
    retarget_operation(op, reroot_reference(reference, steps))
end
reroot_operation(op::ReplacePathOperation, steps::Tuple) =
    make_path_operation(op, reroot_reference(get_operation_path(op), steps))
reroot_operation(op::CompoundOperation, steps::Tuple) =
    CompoundOperation(Any[reroot_operation(o, steps) for o in op.operations])
# One method for every wrapper there will ever be: a `WrappingOperation` holds one
# operation, so rerooting it is rerooting what it holds. Without it a wrapper hits
# the catch-all above and carries an inner reference rooted at the wrong depth.
reroot_operation(op::WrappingOperation, steps::Tuple) =
    rewrap_operation(op, reroot_operation(get_wrapped_operation(op), steps))

operation_reference(op) = nothing
operation_reference(op::ReplaceSelectionOperation) = op.path
# A carried root is the place of the write, so only a document-rooted write
# reports its reference.
operation_reference(op::ReplaceReferencedValueOperation) =
    op.document === nothing ? op.reference : nothing

retarget_operation(op, reference) = op
retarget_operation(::ReplaceSelectionOperation, reference::Reference) =
    ReplaceSelectionOperation(reference)
retarget_operation(op::ReplaceReferencedValueOperation, reference::Reference) =
    op.document === nothing ?
        ReplaceReferencedValueOperation(nothing, reference, op.value) : op

operation_travels_unchanged(op) = false
# These name no place in a document, so each travels up a chain as it is: the
# no-op, the quit, the new print of the view, the flip of the node that it
# carries, the move of the selection at the root, and the timer of the editor.
operation_travels_unchanged(::Union{DoNothingOperation, QuitEditorOperation,
                                    InvalidateProjectionOperation,
                                    ToggleCollapseOperation,
                                    SelectNextInsertionOperation,
                                    SetTimerOperation}) = true
