"""
    PreservingProjectionModule

A trivial higher-order projection that returns the input as the output
without copying. Useful as a pass-through branch in predicate-dispatching
projections where no transformation is needed.
"""
module PreservingProjectionModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: SimpleIoMap
export PreservingProjection

struct PreservingProjection <: Projection end

function projection_print(projection::PreservingProjection, input, recursion, reference)
    SimpleIoMap(projection, input, input)
end

function projection_read(::PreservingProjection, iomap, operation)
    operation
end

function map_reference_forward(::PreservingProjection, iomap, reference)
    reference
end

function map_reference_backward(::PreservingProjection, iomap, reference)
    reference
end

end # module
