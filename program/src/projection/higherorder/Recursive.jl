"""
    RecursiveProjectionModule

A higher-order projection that passes itself as the recursion argument
when calling its child. This lets node projections call back into the full
pipeline for each child subtree without hard-coding any specific inner
step, enabling self-referential tree traversal.
"""
module RecursiveProjectionModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
export RecursiveProjection

"""
    RecursiveProjection(child)

A compound projection that wraps a child projection and passes itself
as the `recursion` argument when calling `projection_print` on the child.
This enables the child projection (and any projections it delegates to)
to call `projection_print(recursion, sub_input, recursion)` to recurse
back through this same wrapper.

# Example

    rp = RecursiveProjection(
        TypeDispatchingProjection(
            JsonNull   => JsonNullToSyntaxLeaf(),
            JsonArray  => JsonArrayToSyntaxNode(),  # calls recursion for elements
            ...
        )
    )
    result = projection_print(rp, json_doc)
"""
struct RecursiveProjection <: Projection
    child::Any
end

function projection_print(rp::RecursiveProjection, input, recursion, reference)
    projection_print(rp.child, input, rp, reference)
end

# RecursiveProjection is a transparent wrapper — it returns the inner
# projection's IoMap directly, so input/output fields are already correct.

function projection_read(rp::RecursiveProjection, iomap, op)
    projection_read(rp.child, iomap, op)
end

function map_reference_forward(::RecursiveProjection, iomap, reference)
    return nothing
end

function map_reference_backward(::RecursiveProjection, iomap, reference)
    return nothing
end

end # module
