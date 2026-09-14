# Fragment of `ProjectionAlgebraModule` — `IdentityProjection`, the projection
# that returns its input unchanged. It is the unit of the algebra: chaining it
# with any projection gives that projection back.

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
