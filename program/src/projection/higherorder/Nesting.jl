"""
    NestingProjectionModule

A higher-order projection that applies the first element to the input,
passing a new NestingProjection built from the remaining elements as the
recursion argument. This lets the first element project the outer structure
and delegate inner/nested content projection to the recursion.

When the elements list is empty, falls back to the stored recursion
(or the outer recursion if none was stored).

Mirrors the design of `nesting.lisp` in the Common Lisp codebase.
"""
module NestingProjectionModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..IoMapApiModule: IoMap
export NestingProjection, NestingProjectionIoMap

struct NestingProjectionIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

"""
    NestingProjection(elements...; recursion=nothing)

A compound projection that applies projections in a nesting (recursive)
fashion rather than sequentially. The first element handles the outer
structure and can call `projection_print(recursion, content, ...)` to
project nested content through the remaining elements.

# Example

    np = NestingProjection(outer_projection, inner_projection)
    result = projection_print(np, input, recursion, reference)
"""
struct NestingProjection <: Projection
    elements::Vector{Any}
    recursion::Any
end

NestingProjection(first_elem::Projection, rest...; recursion=nothing) =
    NestingProjection(Any[first_elem, rest...], recursion)

function projection_print(np::NestingProjection, input, recursion, reference)
    effective = np.recursion !== nothing ? np.recursion : recursion
    if !isempty(np.elements)
        inner = NestingProjection(np.elements[2:end], effective)
        iomap = projection_print(np.elements[1], input, inner, reference)
        NestingProjectionIoMap(np, input, iomap.output, iomap)
    else
        iomap = projection_print(effective, input, recursion, reference)
        NestingProjectionIoMap(np, input, iomap.output, iomap)
    end
end

function projection_read(np::NestingProjection, iomap::NestingProjectionIoMap, event)
    if !isempty(np.elements)
        projection_read(np.elements[1], iomap.child_iomap, event)
    else
        np.recursion === nothing && return nothing
        projection_read(np.recursion, iomap.child_iomap, event)
    end
end

function map_reference_forward(::NestingProjection, iomap, reference)
    return nothing
end

function map_reference_backward(::NestingProjection, iomap, reference)
    return nothing
end

end # module
