# Fragment of `LayoutModule`.
#
# The places of a layout along one axis, as the lines of a text and the children of
# a stack are placed: a value of each place, combined over aligned blocks of
# places, so the offset of a place, the extent of all places and the place of an
# offset each read cells to a depth of log2 of the count of places.

"""
    PlaceBlocks{T}(read_value, combine)

A value of each place of a layout, combined over aligned blocks of places: a
block of `size` places, a power of two, starts after a multiple of `size`, and
it combines the totals of its two halves. `read_value(place)` reads the value of
a place from its cells, such as the extent of a child and the gap after it, and
`combine` is `+` for the offsets of the places or `max` for the extent across
them.

Use it to place many children along an axis: the total of the places before a
place combines the blocks of the binary form of their count, so it reads cells to
a depth of log2 of the count of places, never a chain of every place before it.
A change of one value computes again the blocks that hold it and the totals that
read them, and a total that comes out the same stops there. The cell of a block
and of a total is made at its first read, and kept.

# Example

    heights = [Cell(20), Cell(30), Cell(25)]
    blocks = PlaceBlocks{Int}(i -> heights[i][], +)
    get_total_before(blocks, 3)          # 50, where the third child starts
    find_place_at(blocks, 35, 3)         # (2, 20): the second child holds 35

See also `get_block_total`, `get_total_before` and `find_place_at`.
"""
struct PlaceBlocks{T}
    read_value::Function
    combine::Function
    blocks::Dict{Tuple{Int,Int},Cell}
    prefixes::Dict{Int,Cell}
end

PlaceBlocks{T}(read_value::Function, combine::Function) where {T} =
    PlaceBlocks{T}(read_value, combine, Dict{Tuple{Int,Int},Cell}(), Dict{Int,Cell}())

"""
    get_block_total(blocks::PlaceBlocks, first, size) -> T

The total of the `size` places from `first`, for a block whose size is a power of
two and whose first place follows a multiple of its size. A block of one place is
the value of that place.
"""
function get_block_total(blocks::PlaceBlocks{T}, first::Int, size::Int) where {T}
    size == 1 && return blocks.read_value(first)::T
    cell = get!(blocks.blocks, (first, size)) do
        half = size ÷ 2
        Cell(@computation blocks.combine(get_block_total(blocks, first, half),
                                         get_block_total(blocks, first + half, half)))
    end
    cell[]::T
end

"""
    get_total_before(blocks::PlaceBlocks, place) -> T

The total of the places before `place`: the offset where it starts in a sum, or
the extent across the places before it in a maximum. The total before the place
after the last is the total of all places. It combines the blocks of the binary
form of `place - 1`, the largest first, so the totals of all places share their
blocks.
"""
function get_total_before(blocks::PlaceBlocks{T}, place::Int) where {T}
    cell = get!(blocks.prefixes, place) do
        place == 1 && return Cell(zero(T))
        Cell(Computation(function ()
            total = zero(T)
            first = 1
            size = prevpow(2, place - 1)
            while first < place
                if first + size <= place
                    total = blocks.combine(total, get_block_total(blocks, first, size))
                    first += size
                end
                size ÷= 2
            end
            total
        end))
    end
    cell[]::T
end

"""
    find_place_at(blocks::PlaceBlocks, offset, count) -> (place, start)

The place among the first `count` that holds `offset` in a sum, and the offset
`start` where that place starts: the last place that starts at or before
`offset`. A descent through the blocks, the largest first, finds it. An offset
past the end is in the last place.
"""
function find_place_at(blocks::PlaceBlocks{T}, offset, count::Int) where {T}
    place = 1
    start = zero(T)
    size = prevpow(2, count)
    while size >= 1
        if place + size - 1 <= count
            total = get_block_total(blocks, place, size)
            if start + total <= offset
                start += total
                place += size
            end
        end
        size ÷= 2
    end
    place <= count && return (place, start)
    (count, start - get_block_total(blocks, count, 1))
end
