"""
    SortingProjectionModule

Domain-independent projection that sorts the elements of a collection
document by a configurable key function.
"""
module SortingProjectionModule

import ..ProjectionApiModule: print_document, print_child, map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: SimpleIoMap
import ..IoMapModule: IoMap
import ..CellModule: Cell
import ..CollectionModule: CellVector
import ..ReferenceModule: ConcreteReference, ElementReferenceStep, PositionReferenceStep, RangeReferenceStep, extend_reference, get_reference_node_type
import ..ReferenceModule: var"@reference_case"
import ..PrinterContextModule: make_child_context
import ..IdentityProjectionModule: IdentityProjection
export SortingProjection, SortingProjectionIoMap

"""
    SortingProjection(; by=identity, lt=isless, rev=false)

A generic projection that sorts the elements in the input collection.

# Example

    srt = SortingProjection(by=length)
    result = print_document(srt, ["bb", "a", "ccc"])  # ["a", "bb", "ccc"]
"""
struct SortingProjection <: Projection
    by::Function
    lt::Function
    rev::Bool
end

SortingProjection(; by::Function=identity, lt::Function=isless, rev::Bool=false) =
    SortingProjection(by, lt, rev)

struct SortingProjectionIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    index_map::Vector{Int}   # index_map[j] is the 1-based input index for 1-based output position j
    element_iomaps::Cell
end

function print_document(p::SortingProjection, recursion, input::CellVector, ctx)
    recursion = something(recursion, IdentityProjection())
    n = length(input)
    perm = sortperm(1:n; by = i -> p.by(input[i]), lt=p.lt, rev=p.rev)
    # Recursively project each element (CellVector getindex already unwraps the Cell)
    children = [print_child(recursion, input[i],
                    make_child_context(ctx, ElementReferenceStep(i)))
                for i in 1:n]
    # Build output by arranging projected elements in sorted order
    out_cells = Cell[Cell(children[perm[j]].output) for j in 1:n]
    output = CellVector(out_cells)
    output.selection = input.selection
    element_iomaps = Cell(children)
    SortingProjectionIoMap(p, input, output, perm, element_iomaps)
end

function print_document(p::SortingProjection, recursion, input::Vector{Cell}, ctx)
    recursion = something(recursion, IdentityProjection())
    n = length(input)
    perm = sortperm(1:n; by = i -> p.by(input[i]), lt=p.lt, rev=p.rev)
    # Recursively project each element (unwrapping Cell like CopyingProjection does)
    children = [print_child(recursion, c[],
                    make_child_context(ctx, ElementReferenceStep(i)))
                for (i, c) in enumerate(input)]
    # Build output by arranging projected Cells in sorted order (no double-wrapping)
    output = [children[perm[j]].output for j in 1:n]
    element_iomaps = Cell(children)
    SortingProjectionIoMap(p, input, output, perm, element_iomaps)
end

function print_document(p::SortingProjection, recursion, input, ctx)
    recursion = something(recursion, IdentityProjection())
    n = length(input)
    perm = sortperm(1:n; by = i -> p.by(input[i]), lt=p.lt, rev=p.rev)
    # Recursively project each element
    children = [print_child(recursion, input[i],
                    make_child_context(ctx, ElementReferenceStep(i)))
                for i in 1:n]
    # Build output by arranging projected elements in sorted order
    output = [children[perm[j]].output for j in 1:n]
    element_iomaps = Cell(children)
    SortingProjectionIoMap(p, input, output, perm, element_iomaps)
end

function map_reference_forward(p::SortingProjection, iomap::SortingProjectionIoMap, reference)
    @reference_case reference begin
        [i].rest... => begin
            n = length(iomap.input)
            (i < 1 || i > n) && return nothing
            j = findfirst(==(i), iomap.index_map)
            j === nothing && return nothing
            elem_iomap = iomap.element_iomaps[][j]
            mapped_tail = map_reference_forward(elem_iomap.projection, elem_iomap, rest)
            mapped_tail === nothing && return nothing
            ConcreteReference(get_reference_node_type(iomap.output), ElementReferenceStep(j), mapped_tail)
        end
        _ => @invoke map_reference_forward(p::Projection, iomap, reference)
    end
end

function map_reference_backward(p::SortingProjection, iomap::SortingProjectionIoMap, reference)
    @reference_case reference begin
        [j].rest... => begin
            n = length(iomap.output)
            (j < 1 || j > n) && return nothing
            elem_iomap = iomap.element_iomaps[][j]
            mapped_tail = map_reference_backward(elem_iomap.projection, elem_iomap, rest)
            mapped_tail === nothing && return nothing
            i = iomap.index_map[j]
            ConcreteReference(get_reference_node_type(iomap.input), ElementReferenceStep(i), mapped_tail)
        end
        _ => @invoke map_reference_backward(p::Projection, iomap, reference)
    end
end

end # module
