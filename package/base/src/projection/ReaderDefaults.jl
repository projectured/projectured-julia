"""
    ReaderDefaultsModule

R6 fragment of the projection layer's reader defaults — the
Primitive-operation branches split out of `kernel/common/Projection.jl` at
P8. `read_intent` is an open generic; the kernel default handles the
Primitive-free operation types (ReplaceSelection, ReplaceReferencedValue,
Compound, ToggleCollapse, SelectNextInsertion, etc.) and this module adds
the two Primitive-op methods beside the types they interpret. Multiple
dispatch: these more-specific `read_intent(::Projection, iomap, ::Replace…RangeOperation)`
methods take precedence over the kernel's catch-all `read_intent(p, iomap, operation)`
that was previously an if-elseif chain.
"""
module ReaderDefaultsModule

import ProjecturedKernel.ProjectionApiModule: read_intent, map_reference_backward, Projection
import ..PrimitiveModule: ReplaceStringRangeOperation, ReplaceNumberRangeOperation

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

end # module
