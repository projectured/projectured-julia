"""
    FilteringProjectionModule

Domain-independent projection that restricts a collection document to the
subset of elements matching a given predicate.
"""
module FilteringProjectionModule

import ..ProjectionApiModule: projection_print, map_reference_forward, map_reference_backward, Projection
import ..IoMapApiModule: IoMap
import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, append_reference
import ..ReferenceCaseModule: var"@reference_case"
export FilteringProjection, FilteringProjectionIoMap

struct FilteringProjectionIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    kept_indices::Vector{Int}
end

"""
    FilteringProjection(; predicate=Returns(true))

A generic projection that filters the elements in the input collection,
keeping only those for which `predicate(element)` returns `true`.

# Example

    fp = FilteringProjection(predicate=x -> x > 0)
    result = projection_print(fp, [-1, 2, -3, 4])  # [2, 4]
"""
struct FilteringProjection <: Projection
    predicate::Function
end

FilteringProjection(; predicate::Function=Returns(true)) =
    FilteringProjection(predicate)

function projection_print(p::FilteringProjection, input::CellVector, recursion, reference)
    n = length(input)
    kept_indices = Int[i for i in 1:n if p.predicate(input[i])]
    out_cells = Cell[Cell(input[i]) for i in kept_indices]
    output = CellVector(out_cells)
    output.selection = input.selection
    FilteringProjectionIoMap(p, input, output, kept_indices)
end

function projection_print(p::FilteringProjection, input::Vector{Cell}, recursion, reference)
    kept_indices = Int[i for (i, c) in enumerate(input) if p.predicate(c)]
    output = Cell[input[i] for i in kept_indices]
    FilteringProjectionIoMap(p, input, output, kept_indices)
end

function projection_print(p::FilteringProjection, input, recursion, reference)
    kept_indices = findall(p.predicate, input)
    output = input[kept_indices]
    FilteringProjectionIoMap(p, input, output, kept_indices)
end

function map_reference_forward(p::FilteringProjection, iomap::FilteringProjectionIoMap, reference)
    @reference_case reference begin
        [i].rest... => begin
            j = findfirst(==(i), iomap.kept_indices)
            j === nothing && return nothing
            ConcreteReferencePath(ElementReference(j), rest)
        end
        _ => @invoke map_reference_forward(p::Projection, iomap, reference)
    end
end

function map_reference_backward(p::FilteringProjection, iomap::FilteringProjectionIoMap, reference)
    @reference_case reference begin
        [j].rest... => begin
            (j < 1 || j > length(iomap.kept_indices)) && return nothing
            ConcreteReferencePath(ElementReference(iomap.kept_indices[j]), rest)
        end
        _ => @invoke map_reference_backward(p::Projection, iomap, reference)
    end
end

end # module
