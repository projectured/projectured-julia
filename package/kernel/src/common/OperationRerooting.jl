"""
    OperationRerootingModule

Generic reference/operation **re-rooting** helpers shared by container
projections. A container that routes an event into one of its children gets
back an operation whose reference is rooted in the *child's* output domain; to
forward that operation up, the container must prepend the step(s) that lead
from itself to that child (e.g. `elements[i]` for a `WidgetComposite`,
`children[i]` for a layout).

These helpers depend only on `Reference` paths and the path-bearing `Operation`
types — no widget or layout knowledge — so both `WidgetToGraphics` and
`LayoutToGraphics` (and any future container) reuse them instead of duplicating
the prepend logic. The same lift powers the **recursive gesture reader** in
`ProjectionTemplate.jl`: a structural projection delegates a raw authoring gesture
to the selected child's projection and lifts the returned operation by prepending
the input step that reaches the child — see the "Recursive gesture reading"
section of `documentation/projection-system.md`.
"""
module OperationRerootingModule

import ..ReferenceModule: ReferencePath, ConcreteReferencePath
import ..OperationModule: ReplaceSelectionOperation, ReplaceReferencedValue, CompoundOperation
import ..PrimitiveModule: StringReplaceRangeOperation, NumberReplaceRangeOperation

export prepend_steps_to_ref, prepend_steps_to_op

"""
    prepend_steps_to_ref(ref, steps::Tuple) -> ReferencePath

Prepend each step in `steps` (outermost first) to `ref`, producing a longer
`ConcreteReferencePath`. Used by container readers that need to add several
steps at once (e.g. a split pane's `elements[i].child`).
"""
function prepend_steps_to_ref(ref::ReferencePath, steps::Tuple)
    result = ref
    for step in reverse(steps)
        result = ConcreteReferencePath(step, result)
    end
    result
end

"""
    prepend_steps_to_op(op, steps::Tuple) -> op

Prepend `steps` to the reference inside a path-bearing operation
(`ReplaceSelectionOperation` / `StringReplaceRangeOperation` /
`NumberReplaceRangeOperation` / …). `nothing` passes through as `nothing`.

`ReplaceReferencedValue` is rerooted only when it is **`editor.document`-rooted**
(`document === nothing`); a self-contained one (carrying its own root object) is
returned unchanged, as is any operation type not listed here.
"""
function prepend_steps_to_op(op, steps::Tuple)
    # INVARIANT: the reference-carrying operation types matched here must stay in
    # sync with the default `ProjectionModule.projection_read`. A path-bearing
    # operation missing from this list falls through to the `else` and is returned
    # unchanged — its reference never gets rerooted. See documentation/operations.md.
    op === nothing && return nothing
    if op isa ReplaceReferencedValue
        # Self-contained (carries its own root): pass through. Document-rooted:
        # reroot the reference, exactly as the dedicated path-bearing ops below.
        op.document === nothing || return op
        ReplaceReferencedValue(nothing, prepend_steps_to_ref(op.reference, steps), op.value)
    elseif op isa ReplaceSelectionOperation
        ReplaceSelectionOperation(prepend_steps_to_ref(op.path, steps))
    elseif op isa StringReplaceRangeOperation
        StringReplaceRangeOperation(prepend_steps_to_ref(op.reference, steps), op.replacement)
    elseif op isa NumberReplaceRangeOperation
        NumberReplaceRangeOperation(prepend_steps_to_ref(op.reference, steps), op.replacement)
    elseif op isa CompoundOperation
        CompoundOperation(Any[prepend_steps_to_op(o, steps) for o in op.operations])
    else
        op
    end
end

end # module
