# Fragment of `ProjectionAlgebraModule`.
#
# A projection that always returns a fixed output regardless
# of the input. Useful for injecting constant documents into a projection
# pipeline.
struct ConstantProjection <: Projection
    output::Any
end

function print_document(p::ConstantProjection, recursion, input, ctx)
    SimpleIoMap(p, input, p.output)
end

# The output does not come from the input, so no gesture on it is a gesture on
# the input and no operation on it maps back. The defaults would ask the table of
# the input and keep an operation that names no reference, so the projection
# answers nothing for both.
read_gesture(::ConstantProjection, iomap::SimpleIoMap, gesture; answer = nothing) = nothing
map_operation_backward(::ConstantProjection, iomap::SimpleIoMap, operation) = nothing

function map_reference_forward(::ConstantProjection, iomap, reference)
    nothing
end

function map_reference_backward(::ConstantProjection, iomap, reference)
    nothing
end
