"""
    ConstantProjectionModule

A projection that always returns a fixed output regardless
of the input. Useful for injecting constant documents into a projection
pipeline.
"""
module ConstantProjectionModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: SimpleIoMap
export ConstantProjection

struct ConstantProjection <: Projection
    output::Any
end

function projection_print(p::ConstantProjection, recursion, input, ctx)
    SimpleIoMap(p, input, p.output)
end

function projection_read(::ConstantProjection, iomap, op)
    nothing
end

function map_reference_forward(::ConstantProjection, iomap, reference)
    nothing
end

function map_reference_backward(::ConstantProjection, iomap, reference)
    nothing
end

end # module
