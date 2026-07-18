# Fragment of `OperationModule` — the open `reroot_operation` seam.
# Reference/operation *re-rooting* helpers shared by container projections:
# a container that routes an event into one of its children gets back an
# operation whose reference is rooted in the *child's* output domain; to
# forward that operation up, the container prepends the step(s) that lead
# from itself to that child (e.g. `elements[i]`, `children[i]`). The same
# lift powers the recursive gesture reader — see
# `package/kernel/doc/projection-system.md`.
#
# `reroot_operation` is an *open* generic rather than a closed `if op isa …`
# chain, because `ReplaceStringRangeOperation` / `ReplaceNumberRangeOperation`
# are defined in `document/Primitive.jl`, which stays in base alongside
# Primitive itself — the kernel cannot hardcode a dependency on them. The
# base methods (Nothing, catch-all, ReplaceSelectionOperation,
# ReplaceReferencedValueOperation, CompoundOperation) live here; the
# Primitive-op methods live in `document/Primitive.jl`.
#
# INVARIANT: a new path-bearing operation type must add a `reroot_operation`
# method. Missing methods fall through to the catch-all and are returned
# unchanged — the reference is not rerooted. Kept in sync with the default
# `ProjectionModule.read_intent`; see package/kernel/doc/operation.md.

"""
    reroot_reference(ref, steps::Tuple) -> Reference

Prepend each step in `steps` (outermost first) to `ref`, producing a longer
`ConcreteReference`. Used by container readers that need to add several
steps at once (e.g. a split pane's `elements[i].child`).
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

Prepend `steps` to the reference inside a path-bearing operation. Open
generic (R2): new path-bearing operation types add methods for themselves.
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
