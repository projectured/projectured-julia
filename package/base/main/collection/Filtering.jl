"""
    FilteringProjectionModule

Domain-independent projection that restricts a collection document to the
subset of elements matching a given predicate.
"""
module FilteringProjectionModule

import ..ProjectionApiModule: print_document, map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: IoMap, var"@iomap"
import ..CellModule: Cell, set_cell_function!
import ..CollectionModule: CellVector
import ..ReferenceModule: ConcreteReference, ElementReferenceStep, PositionReferenceStep, extend_reference, get_reference_node_type
import ..ReferenceModule: var"@reference_case"
export FilteringProjection, FilteringProjectionIoMap

# `kept_indices` and `output` are computed cells for a reactive `CellVector`
# input, so the IoMap keeps its identity while the kept subset tracks the input
# (AR-STABLE-IOMAP-IDENTITY); `iomap.kept_indices` reads the current vector.
@iomap struct FilteringProjectionIoMap
    projection::Any
    input::Any
    output::Any
    kept_indices::Any
end

"""
    FilteringProjection(; predicate=Returns(true))

A generic projection that filters the elements in the input collection,
keeping only those for which `predicate(element)` returns `true`.

# Example

    fp = FilteringProjection(predicate=x -> x > 0)
    result = print_document(fp, [-1, 2, -3, 4])  # [2, 4]
"""
struct FilteringProjection <: Projection
    predicate::Function
end

FilteringProjection(; predicate::Function=Returns(true)) =
    FilteringProjection(predicate)

function print_document(p::FilteringProjection, recursion, input::CellVector, ctx)
    kept = Cell(() -> Int[i for i in 1:length(input) if p.predicate(input[i])])
    output = CellVector(() -> [input[i] for i in kept[]])
    set_cell_function!(getfield(output, :selection), () -> input.selection)
    FilteringProjectionIoMap(p, input, output, kept)
end

function print_document(p::FilteringProjection, recursion, input::Vector{Cell}, ctx)
    kept_indices = Int[i for (i, c) in enumerate(input) if p.predicate(c)]
    output = Cell[input[i] for i in kept_indices]
    FilteringProjectionIoMap(p, input, output, kept_indices)
end

function print_document(p::FilteringProjection, recursion, input, ctx)
    kept_indices = findall(p.predicate, input)
    output = input[kept_indices]
    FilteringProjectionIoMap(p, input, output, kept_indices)
end

function map_reference_forward(p::FilteringProjection, iomap::FilteringProjectionIoMap, reference)
    @reference_case reference begin
        [i].rest... => begin
            j = findfirst(==(i), iomap.kept_indices)
            j === nothing && return nothing
            ConcreteReference(get_reference_node_type(iomap.output), ElementReferenceStep(j), rest)
        end
        _ => @invoke map_reference_forward(p::Projection, iomap, reference)
    end
end

function map_reference_backward(p::FilteringProjection, iomap::FilteringProjectionIoMap, reference)
    @reference_case reference begin
        [j].rest... => begin
            (j < 1 || j > length(iomap.kept_indices)) && return nothing
            ConcreteReference(get_reference_node_type(iomap.input), ElementReferenceStep(iomap.kept_indices[j]), rest)
        end
        _ => @invoke map_reference_backward(p::Projection, iomap, reference)
    end
end

end # module
