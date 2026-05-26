"""
    InvariablyProjectionModule

A higher-order projection that always returns a fixed output regardless
of the input. Useful for injecting constant documents into a projection
pipeline.
"""
module InvariablyProjectionModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: SimpleIoMap
export InvariablyProjection

struct InvariablyProjection <: Projection
    output::Any
end

function projection_print(p::InvariablyProjection, input, recursion, reference)
    SimpleIoMap(p, input, p.output)
end

function projection_read(::InvariablyProjection, iomap, op)
    nothing
end

function map_reference_forward(::InvariablyProjection, iomap, reference)
    nothing
end

function map_reference_backward(::InvariablyProjection, iomap, reference)
    nothing
end

end # module
