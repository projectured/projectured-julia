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

import ..ProjectionApiModule: print_document, print_child, read_intent, map_reference_forward, map_reference_backward, Projection
import ..IntentModule: Intent
import ..IoMapApiModule: IoMap
import ..GestureModule: GestureBinding
import ..ProjectionGestureBindingsModule: collect_gesture_bindings
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
structure and can call `print_child(recursion, content, ...)` to
project nested content through the remaining elements.

# Example

    np = NestingProjection(outer_projection, inner_projection)
    result = print_document(np, recursion, input, reference)
"""
struct NestingProjection <: Projection
    elements::Vector{Any}
    recursion::Any
end

NestingProjection(first_elem::Projection, rest...; recursion=nothing) =
    NestingProjection(Any[first_elem, rest...], recursion)

function print_document(np::NestingProjection, recursion, input, ctx)
    effective = np.recursion !== nothing ? np.recursion : recursion
    if !isempty(np.elements)
        inner = NestingProjection(np.elements[2:end], effective)
        iomap = print_document(np.elements[1], inner, input, ctx)
        NestingProjectionIoMap(np, input, iomap.output, iomap)
    else
        iomap = print_document(effective, recursion, input, ctx)
        NestingProjectionIoMap(np, input, iomap.output, iomap)
    end
end

function read_intent(np::NestingProjection, recursion, change::Intent, iomap::NestingProjectionIoMap)
    if !isempty(np.elements)
        read_intent(np.elements[1], recursion, change, iomap.child_iomap)
    else
        np.recursion === nothing && return Intent(change.gesture, nothing)
        read_intent(np.recursion, recursion, change, iomap.child_iomap)
    end
end

read_intent(np::NestingProjection, iomap::NestingProjectionIoMap, payload) =
    read_intent(np, nothing, Intent(payload), iomap).operation

# Gather gestures from the same place the reader delegates to: the first element
# (or the stored recursion when empty), over the nested child iomap. This lets a
# `collect_gesture_bindings` over a `NestingProjection(example_pipeline)` reach the example
# pipeline's reified gestures (Sequential/document tables below it).
function collect_gesture_bindings(np::NestingProjection, recursion, iomap::NestingProjectionIoMap)
    if !isempty(np.elements)
        return collect_gesture_bindings(np.elements[1], recursion, iomap.child_iomap)
    elseif np.recursion !== nothing
        return collect_gesture_bindings(np.recursion, recursion, iomap.child_iomap)
    else
        return GestureBinding[]
    end
end

function map_reference_forward(np::NestingProjection, iomap::NestingProjectionIoMap, reference)
    if !isempty(np.elements)
        map_reference_forward(np.elements[1], iomap.child_iomap, reference)
    elseif np.recursion !== nothing
        map_reference_forward(np.recursion, iomap.child_iomap, reference)
    else
        nothing
    end
end

function map_reference_backward(np::NestingProjection, iomap::NestingProjectionIoMap, reference)
    if !isempty(np.elements)
        map_reference_backward(np.elements[1], iomap.child_iomap, reference)
    elseif np.recursion !== nothing
        map_reference_backward(np.recursion, iomap.child_iomap, reference)
    else
        nothing
    end
end

end # module
