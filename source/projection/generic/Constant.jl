# ──────────────────────────────────────────────────────────────────────────
# Folded in from generic/Constant.jl.
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

function read_intent(::ConstantProjection, iomap, op)
    nothing
end

function map_reference_forward(::ConstantProjection, iomap, reference)
    nothing
end

function map_reference_backward(::ConstantProjection, iomap, reference)
    nothing
end
