# Fragment of `ProjectionAlgebraModule`.
#
# A higher-order projection that applies the first element to the input,
# passing a new NestingProjection built from the remaining elements as the
# recursion argument. This lets the first element project the outer structure
# and delegate inner/nested content projection to the recursion.
#
# When the elements list is empty, falls back to the stored recursion
# (or the outer recursion if none was stored).
#
# Mirrors the design of `nesting.lisp` in the Common Lisp codebase.
# Transparent: `output` forwards the child iomap's output through a cell, so the
# IoMap keeps its identity while the nested projection re-derives
# (PAR-STABLE-IOMAP-IDENTITY); `iomap.child_iomap` reads the child.
@iomap struct NestingIoMap
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
        child = print_document(np.elements[1], inner, input, ctx)
        NestingIoMap(np, input, Cell(@computation child.output), child)
    else
        child = print_document(effective, recursion, input, ctx)
        NestingIoMap(np, input, Cell(@computation child.output), child)
    end
end

function read_intent(np::NestingProjection, recursion, change::Intent, iomap::NestingIoMap)
    if !isempty(np.elements)
        read_intent(np.elements[1], recursion, change, iomap.child_iomap)
    else
        np.recursion === nothing && return Intent(change.gesture, nothing)
        read_intent(np.recursion, recursion, change, iomap.child_iomap)
    end
end

read_intent(np::NestingProjection, iomap::NestingIoMap, payload) =
    read_intent(np, nothing, Intent(payload), iomap).operation

function map_reference_forward(np::NestingProjection, iomap::NestingIoMap, reference)
    if !isempty(np.elements)
        map_reference_forward(np.elements[1], iomap.child_iomap, reference)
    elseif np.recursion !== nothing
        map_reference_forward(np.recursion, iomap.child_iomap, reference)
    else
        nothing
    end
end

function map_reference_backward(np::NestingProjection, iomap::NestingIoMap, reference)
    if !isempty(np.elements)
        map_reference_backward(np.elements[1], iomap.child_iomap, reference)
    elseif np.recursion !== nothing
        map_reference_backward(np.recursion, iomap.child_iomap, reference)
    else
        nothing
    end
end
