"""
    ReversingProjectionModule

Domain-independent projection that reverses the order of elements in a
collection document.
"""
module ReversingProjectionModule

import ..ProjectionApiModule: print_document, print_child, map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..CellModule: Cell
import ..ReferenceModule: ConcreteReference, ElementReferenceStep, PositionReferenceStep, extend_reference, get_reference_node_type
import ..ReferenceModule: var"@reference_case"
import ..PrinterContextModule: make_child_context
import ..IdentityProjectionModule: IdentityProjection
export ReversingProjection

"""
    ReversingProjection()

A generic projection that reverses the order of elements in the input collection.

# Example

    rev = ReversingProjection()
    result = print_document(rev, [1, 2, 3])  # [3, 2, 1]
"""
struct ReversingProjection <: Projection end

function print_document(p::ReversingProjection, recursion, input, ctx)
    recursion = something(recursion, IdentityProjection())
    child_iomaps = Cell(() -> [
        print_child(recursion, input[i],
            make_child_context(ctx, ElementReferenceStep(i)))
        for i in 1:length(input)
    ])
    ChildrenIoMap(p, input, reverse(input), child_iomaps)
end

function map_reference_forward(p::ReversingProjection, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        [i].rest... => begin
            n = length(iomap.input)
            (i < 1 || i > n) && return nothing
            elem_iomap = iomap.child_iomaps[][i]
            mapped_tail = map_reference_forward(elem_iomap.projection, elem_iomap, rest)
            mapped_tail === nothing && return nothing
            # The rebuilt element step descends from the reversed output
            # collection; type its node against it. `mapped_tail` already
            # carries the child's own types.
            ConcreteReference(get_reference_node_type(iomap.output),
                                  ElementReferenceStep(n + 1 - i), mapped_tail)
        end
        _ => @invoke map_reference_forward(p::Projection, iomap, reference)
    end
end

function map_reference_backward(p::ReversingProjection, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        [i].rest... => begin
            n = length(iomap.output)
            (i < 1 || i > n) && return nothing
            elem_iomap = iomap.child_iomaps[][n + 1 - i]
            mapped_tail = map_reference_backward(elem_iomap.projection, elem_iomap, rest)
            mapped_tail === nothing && return nothing
            # Backward: the rebuilt step descends from the input collection.
            ConcreteReference(get_reference_node_type(iomap.input),
                                  ElementReferenceStep(n + 1 - i), mapped_tail)
        end
        _ => @invoke map_reference_backward(p::Projection, iomap, reference)
    end
end

end # module
