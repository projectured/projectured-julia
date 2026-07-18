# Fragment of `OperationModule` — the open `reroot_operation` seam.
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
# `package/kernel/doc/operation.md`.

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

"""
    reroot_operation(op, steps::Tuple) -> op

Prepend `steps` to the reference inside a path-bearing operation. Open generic:
new path-bearing operation types add methods for themselves.
"""
function reroot_operation end

reroot_operation(::Nothing, steps::Tuple) = nothing
reroot_operation(op, steps::Tuple) = op          # catch-all: unchanged
reroot_operation(op::ReplaceSelectionOperation, steps::Tuple) =
    ReplaceSelectionOperation(reroot_reference(op.path, steps))
function reroot_operation(op::ReplaceReferencedValueOperation, steps::Tuple)
    # Self-contained (carries its own root): pass through. Document-rooted
    # (`document === nothing`): reroot the reference.
    op.document === nothing || return op
    ReplaceReferencedValueOperation(nothing, reroot_reference(op.reference, steps), op.value)
end
reroot_operation(op::CompoundOperation, steps::Tuple) =
    CompoundOperation(Any[reroot_operation(o, steps) for o in op.operations])
