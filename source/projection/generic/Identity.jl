"""
    IdentityProjectionModule

A trivial projection that returns the input as the output
without copying. Useful as a pass-through branch in predicate-dispatching
projections where no transformation is needed.
"""
module IdentityProjectionModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: SimpleIoMap
import ..IntentModule: CollectIntents
import ..DocumentModule: Document
import ..GestureBindingModule: read_gesture
export IdentityProjection

struct IdentityProjection <: Projection end

function print_document(projection::IdentityProjection, recursion, input, ctx)
    SimpleIoMap(projection, input, input)
end

function read_intent(::IdentityProjection, iomap, operation)
    # Asked what is available, answer for the input document: an identity
    # projection introduces nothing of its own, so its input's table is the whole of
    # what it offers. Without this the payload would pass through unchanged like
    # everything else, and a document behind an identity would go unlisted.
    if operation isa CollectIntents
        input = iomap.input
        return input isa Document ? read_gesture(input, operation) : nothing
    end
    operation
end

function map_reference_forward(::IdentityProjection, iomap, reference)
    reference
end

function map_reference_backward(::IdentityProjection, iomap, reference)
    reference
end

end # module
