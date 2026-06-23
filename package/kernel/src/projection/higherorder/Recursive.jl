"""
    RecursiveProjectionModule

A higher-order projection that passes itself as the recursion argument
when calling its child. This lets node projections call back into the full
pipeline for each child subtree without hard-coding any specific inner
step, enabling self-referential tree traversal.
"""
module RecursiveProjectionModule

import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read, map_reference_forward, map_reference_backward, Projection, Change, as_change
import ..GestureBindingModule: collect_gestures
export RecursiveProjection

"""
    RecursiveProjection(child)

A compound projection that wraps a child projection and passes itself
as the `recursion` argument when calling `projection_print` on the child.
This enables the child projection (and any projections it delegates to)
to call `projection_printer_recurse(recursion, sub_input)` to recurse
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

function projection_print(rp::RecursiveProjection, recursion, input, ctx)
    projection_print(rp.child, rp, input, ctx)
end

# RecursiveProjection is a transparent wrapper — it returns the inner
# projection's IoMap directly, so input/output fields are already correct.

# Pass self as the recursion so a node reader inside the child re-enters this
# wrapper (symmetric with the printer, which passes `rp` as recursion too).
projection_read(rp::RecursiveProjection, recursion, change::Change, iomap) =
    projection_read(rp.child, rp, change, iomap)

projection_read(rp::RecursiveProjection, iomap, payload) =
    projection_read(rp, nothing, as_change(payload), iomap).operation

# Gather like the reader recurses: pass self as the recursion so the child's
# gathering re-enters this wrapper.
collect_gestures(rp::RecursiveProjection, recursion, iomap) =
    collect_gestures(rp.child, rp, iomap)

function map_reference_forward(::RecursiveProjection, iomap, reference)
    return nothing
end

function map_reference_backward(::RecursiveProjection, iomap, reference)
    return nothing
end

end # module
