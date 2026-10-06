# Fragment of `ProjectionAlgebraModule`.
#
# Fragment of the projection layer's reader defaults — the Primitive-operation
# branches of `read_intent` that dispatch on the *IoMap*.
#
# The plain backward map of a `Replace…RangeOperation` is not here: it goes
# through the `operation_reference` / `retarget_operation` seam (see
# `primitive/Primitive.jl`), which the kernel's catch-all
# `read_intent(p, iomap, operation)` calls. A
# `read_intent(::Projection, iomap, ::Replace…RangeOperation)` method would be
# ambiguous with the catch-all reader that concrete projections define, because
# one is more specific in the projection and the other in the operation.
#
# What remains here needs a concrete IoMap type — the `ProjectionTemplate`
# `TemplateIoMap` retype and the disambiguations the `RecursiveProjection` wrapper
# needs over it.
import ProjecturedKernel.ProjectionModule: read_intent, map_reference_backward, Projection
import ProjecturedKernel.IntentModule: Intent
import ProjecturedKernel.ProjectionModule: TemplateIoMap, AtomicWiring,
                                           find_template_value_retype, find_template_output_child
import ProjecturedKernel.OperationModule: ReplaceSelectionOperation, reroot_operation
import ProjecturedKernel.EventModule: KeyDown, KeyPress

# The value-edit retype for ProjectionTemplate's TemplateIoMap lives here (not
# in `kernel/projection/ProjectionTemplate.jl`) because it references
# `ReplaceStringRangeOperation` (a base/Primitive type) that the kernel
# cannot import.
function read_intent(p::Projection, iomap::TemplateIoMap, op::ReplaceStringRangeOperation)
    w = iomap.wiring
    # An opaque atomic leaf (no bound field — `JsonInsertion`, `JsonNull`,
    # …) has no editable text, so a character insert there is never a
    # valid text edit. Reject it (rather than mapping to a bogus
    # introduced-position op) so a non-gesture key is a clean NO-OP.
    w isa AtomicWiring && w.bound_field === nothing && return nothing
    # A bool takes no text edit: it changes only through the gestures of its domain,
    # so the key falls through to them, as a letter in a number does.
    w isa AtomicWiring && w.bound_type === Bool && return nothing
    # An edit inside an element goes to the element, as a key does: its own reader
    # transforms the edit, and may answer with an operation that replaces the
    # element. The answer takes the input steps to the element in front.
    found = find_template_output_child(iomap, op.reference)
    if found !== nothing
        child, reference, steps = found
        answer = read_intent(child.projection, child,
                             ReplaceStringRangeOperation(reference, op.replacement))
        return answer === nothing ? nothing : reroot_operation(answer, steps)
    end
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    # An edit that maps onto projection-introduced output — a delimiter the projection
    # printed (a JSON string's quotes, a bracket), with no document pre-image — is
    # deferred, so the raw key falls through to the structural gesture rather than
    # writing into the projection's own constant output. The atomic `_map_backward`
    # proj-wraps such a reference (at the head for a directly-projected scalar, or below
    # an `.elements[i]` step for a nested one), which `has_introduced_step` detects.
    has_introduced_step(new_ref) && return nothing
    # The leaf that holds the edited value retypes the edit.
    retype = find_template_value_retype(iomap, strip_reference_types(new_ref))
    if retype !== nothing
        # A number declines a key that can not be part of a number, so the key
        # makes no edit, and no undo step, that the number then ignores.
        if retype === ReplaceNumberRangeOperation
            has_only_number_characters(op.replacement) || return nothing
            # A text that the number can not show becomes the document that its
            # domain gives for it, so the text stays while the person types.
            return make_number_range_operation(get_iomap_input(iomap), new_ref, op.replacement)
        end
        return retype(new_ref, op.replacement)
    end
    return ReplaceStringRangeOperation(new_ref, op.replacement)
end

# Disambiguations for the transparent `RecursiveProjection` wrapper over
# `TemplateIoMap`. The recursive reader in `ProjectionTemplate.jl` (`Projection`) and
# the wrapper's 3-arg reader both match `(RecursiveProjection, TemplateIoMap, …)`,
# neither more specific — so one concrete-typed method per payload defers to the
# wrapper, which threads the read into its child projection. These live here (not
# in `kernel/projection/ProjectionTemplate.jl`) because they dispatch on
# `RecursiveProjection`, a base projection the kernel cannot name.
read_intent(rp::RecursiveProjection, iomap::TemplateIoMap,
            evt::Union{KeyPress, KeyDown}) =
    read_intent(rp, nothing, Intent(evt), iomap).operation

read_intent(rp::RecursiveProjection, iomap::TemplateIoMap, op::ReplacePathOperation) =
    read_intent(rp, nothing, Intent(op), iomap).operation

# Disambiguation for RecursiveProjection over TemplateIoMap.
read_intent(rp::RecursiveProjection, iomap::TemplateIoMap,
            op::ReplaceStringRangeOperation) =
    read_intent(rp, nothing, Intent(op), iomap).operation
