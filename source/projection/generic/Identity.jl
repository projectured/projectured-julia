# Fragment of `ProjectionAlgebraModule` — `IdentityProjection`, the projection
# that returns its input unchanged. It is the unit of the algebra: chaining it
# with any projection gives that projection back.

struct IdentityProjection <: Projection end

function print_document(projection::IdentityProjection, recursion, input, ctx)
    SimpleIoMap(projection, input, input)
end

function read_intent(::IdentityProjection, iomap, operation)
    # An identity projection introduces nothing of its own, so a gesture and the
    # question of what is available are answered for the input document, as the
    # default leaf reader of the kernel answers them. An operation passes through
    # unchanged. Any other payload is not an answer: a pass-through that returned
    # a raw gesture would give the event back as the operation of the whole read.
    if operation isa Union{KeyPress, KeyDown, MousePress, CollectIntents}
        input = iomap.input
        return input isa Document ? read_gesture(input, operation) : nothing
    end
    operation isa Operation ? operation : nothing
end

function map_reference_forward(::IdentityProjection, iomap, reference)
    reference
end

function map_reference_backward(::IdentityProjection, iomap, reference)
    reference
end
