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
# `reroot_operation` is an *open* generic rather than a closed `if op isa …` chain
# because path-bearing operation types defined in higher packages must be able to
# add their own method — the kernel cannot enumerate them. The base methods for
# the cross-domain operations live here.
#
# INVARIANT: a new path-bearing operation type must add a `reroot_operation`
# method. A missing method falls through to the catch-all and is returned
# unchanged — the reference is not rerooted. Kept in sync with the default
# `read_intent`, which enumerates the same operations; see
# `documentation/package/kernel/operation.md`. An operation that HOLDS another
# needs no method of its own: it subtypes `WrappingOperation` and answers the two
# generics of the contract, and the method below serves it.
reroot_operation(::Nothing, steps::Tuple) = nothing
reroot_operation(op, steps::Tuple) = op          # catch-all: unchanged
reroot_operation(op::ReplaceSelectionOperation, steps::Tuple) =
    ReplaceSelectionOperation(reroot_reference(op.path, steps))
function reroot_operation(op::ReplaceReferencedValueOperation, steps::Tuple)
    # Self-contained (carries its own root): pass through. Document-rooted
    # (`document === nothing`): reroot the reference.
    op.document === nothing || return op
    ReplaceReferencedValueOperation(nothing, reroot_reference(op.reference, steps),
                                    op.value)
end
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
# no-op, the quit, the two zooms, the flip of the node that it carries, and the
# move of the selection at the root.
operation_travels_unchanged(::Union{DoNothingOperation, QuitEditorOperation,
                                    AdjustZoomOperation, AdjustFontZoomOperation,
                                    ToggleCollapseOperation,
                                    SelectNextInsertionOperation}) = true
