"""
    IdentityProjectionModule

A trivial projection that returns the input as the output
without copying. Useful as a pass-through branch in predicate-dispatching
projections where no transformation is needed.
"""
module IdentityProjectionModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: SimpleIoMap
export IdentityProjection

struct IdentityProjection <: Projection end

function print_document(projection::IdentityProjection, recursion, input, ctx)
    SimpleIoMap(projection, input, input)
end

function read_intent(::IdentityProjection, iomap, operation)
    operation
end

function map_reference_forward(::IdentityProjection, iomap, reference)
    reference
end

function map_reference_backward(::IdentityProjection, iomap, reference)
    reference
end

end # module
