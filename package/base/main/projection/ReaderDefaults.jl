"""
    ReaderDefaultsModule

Fragment of the projection layer's reader defaults — the Primitive-operation
branches of `read_intent`. `read_intent` is an open generic; the kernel
default handles the Primitive-free operation types (ReplaceSelection,
ReplaceReferencedValue, Compound, ToggleCollapse, SelectNextInsertion, etc.)
and this module adds the two Primitive-op methods beside the types they
interpret. Multiple dispatch: these more-specific
`read_intent(::Projection, iomap, ::Replace…RangeOperation)` methods take
precedence over the kernel's catch-all `read_intent(p, iomap, operation)`.
"""
module ReaderDefaultsModule

import ProjecturedKernel.ProjectionApiModule: read_intent, map_reference_backward, Projection
import ProjecturedKernel.IntentModule: Intent
import ProjecturedKernel.ProjectionTemplateModule: RuleIoMap, AtomicWiring
import ProjecturedKernel.OperationModule: ReplaceSelectionOperation
import ProjecturedKernel.EventModule: KeyDown, KeyPress
import ProjecturedKernel.ProjectionReferenceModule: ProjectionReference
import ProjecturedKernel.ReferenceModule: ConcreteReferencePath
import ..RecursiveProjectionModule: RecursiveProjection
import ..PrimitiveModule: ReplaceStringRangeOperation, ReplaceNumberRangeOperation

# Does the (input-domain) reference pass through any projection-introduced output?
# A `ProjectionReference` step *anywhere* means that part of the path has no document
# pre-image, so an edit targeting it cannot be applied and the op-reader defers it —
# the raw key then falls through to the structural gesture. Head-only
# `is_introduced_reference` is not enough: a scalar nested in a container maps to
# `.elements[i] → ProjectionReference(.open)`, with the introduced step below the head.
_targets_introduced_output(p::ConcreteReferencePath) =
    p.head isa ProjectionReference || _targets_introduced_output(p.tail)
_targets_introduced_output(::Any) = false

function read_intent(projection::Projection, iomap, operation::ReplaceStringRangeOperation)
    input_ref = map_reference_backward(projection, iomap, operation.reference)
    input_ref === nothing && return nothing
    return ReplaceStringRangeOperation(input_ref, operation.replacement)
end

function read_intent(projection::Projection, iomap, operation::ReplaceNumberRangeOperation)
    input_ref = map_reference_backward(projection, iomap, operation.reference)
    input_ref === nothing && return nothing
    return ReplaceNumberRangeOperation(input_ref, operation.replacement)
end

# The value-edit retype for ProjectionTemplate's RuleIoMap lives here (not
# in `kernel/projection/ProjectionTemplate.jl`) because it references
# `ReplaceStringRangeOperation` (a base/Primitive type) that the kernel
# cannot import.
function read_intent(p::Projection, iomap::RuleIoMap, op::ReplaceStringRangeOperation)
    w = iomap.wiring
    # An opaque atomic leaf (no bound field — `JsonInsertion`, `JsonNull`,
    # …) has no editable text, so a character insert there is never a
    # valid text edit. Reject it (rather than mapping to a bogus
    # introduced-position op) so a non-gesture key is a clean NO-OP.
    w isa AtomicWiring && w.bound_field === nothing && return nothing
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    # An edit that maps onto projection-introduced output — a delimiter the projection
    # printed (a JSON string's quotes, a bracket), with no document pre-image — is
    # deferred, so the raw key falls through to the structural gesture rather than
    # writing into the projection's own constant output. `_atomic_backward` proj-wraps
    # such a reference (at the head for a directly-projected scalar, or below an
    # `.elements[i]` step for a nested one), which `_targets_introduced_output` detects.
    _targets_introduced_output(new_ref) && return nothing
    if w isa AtomicWiring && w.retype !== nothing
        return w.retype(new_ref, op.replacement)
    end
    return ReplaceStringRangeOperation(new_ref, op.replacement)
end

# Disambiguations for the transparent `RecursiveProjection` wrapper over
# `RuleIoMap`. The recursive reader in `ProjectionTemplate.jl` (`Projection`) and
# the wrapper's 3-arg reader both match `(RecursiveProjection, RuleIoMap, …)`,
# neither more specific — so one concrete-typed method per payload defers to the
# wrapper, which threads the read into its child projection. These live here (not
# in `kernel/projection/ProjectionTemplate.jl`) because they dispatch on
# `RecursiveProjection`, a base projection the kernel cannot name.
read_intent(rp::RecursiveProjection, iomap::RuleIoMap, evt::Union{KeyPress, KeyDown}) =
    read_intent(rp, nothing, Intent(evt), iomap).operation

read_intent(rp::RecursiveProjection, iomap::RuleIoMap, op::ReplaceSelectionOperation) =
    read_intent(rp, nothing, Intent(op), iomap).operation

# Disambiguation for RecursiveProjection over RuleIoMap.
read_intent(rp::RecursiveProjection, iomap::RuleIoMap, op::ReplaceStringRangeOperation) =
    read_intent(rp, nothing, Intent(op), iomap).operation

end # module
