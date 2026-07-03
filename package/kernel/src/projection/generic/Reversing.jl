"""
    ReversingProjectionModule

Domain-independent projection that reverses the order of elements in a
collection document.
"""
module ReversingProjectionModule

import ..ProjectionApiModule: projection_print, projection_printer_recurse, map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReactiveModule: Cell
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, append_reference
import ..ReferenceCaseModule: var"@reference_case"
import ..PrinterContextModule: child_context
import ..IdentityProjectionModule: IdentityProjection
export ReversingProjection

"""
    ReversingProjection()

A generic projection that reverses the order of elements in the input collection.

# Example

    rev = ReversingProjection()
    result = projection_print(rev, [1, 2, 3])  # [3, 2, 1]
"""
struct ReversingProjection <: Projection end

function projection_print(p::ReversingProjection, recursion, input, ctx)
    recursion = something(recursion, IdentityProjection())
    child_iomaps = Cell(() -> [
        projection_printer_recurse(recursion, input[i],
            child_context(ctx, ElementReference(i)))
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
            ConcreteReferencePath(ElementReference(n + 1 - i), mapped_tail)
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
            ConcreteReferencePath(ElementReference(n + 1 - i), mapped_tail)
        end
        _ => @invoke map_reference_backward(p::Projection, iomap, reference)
    end
end

end # module
