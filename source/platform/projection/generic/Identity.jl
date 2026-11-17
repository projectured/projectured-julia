# Fragment of `ProjectionAlgebraModule` — `IdentityProjection`, the projection
# that returns its input unchanged. It is the unit of the algebra: chaining it
# with any projection gives that projection back.

struct IdentityProjection <: Projection end

function print_document(projection::IdentityProjection, recursion, input, ctx)
    SimpleIoMap(projection, input, input)
end

# An identity projection introduces nothing of its own, so it needs no reader: the
# default `read_gesture` of a projection answers a gesture and the question of what
# is available with the table of the input document, and the default
# `map_operation_backward` maps each reference with the identity map below, so an
# operation passes through unchanged.

function map_reference_forward(::IdentityProjection, iomap, reference)
    reference
end

function map_reference_backward(::IdentityProjection, iomap, reference)
    reference
end
