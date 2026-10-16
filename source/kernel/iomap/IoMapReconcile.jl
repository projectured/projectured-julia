# Fragment of `IoMapModule` — the reconcilers that reuse a child IoMap across a change.

"""
    make_reconciled_child_iomaps_cell(elements_fn, make_iomap) -> Cell

Build a reactive cell yielding the child-IoMap vector for the collection
`elements_fn()` returns, reusing the prior IoMap of every element that is still in
the collection, at its old index or at a new one, and calling
`make_iomap(index, element)` only for an element that is new to it. `index` is a
cell of the index of the element: a computation that follows the element when an
insert or a delete moves it, so the path of the child, which reads it, names its
new place. An element at two places of the collection, the same object or an
equal value that is no mutable object, is kept at neither, and each of its IoMaps
gets the cell of its own index, which does not change. `elements_fn` is read inside
the cell on every recompute, so the reactive dependency on the collection's
structure is preserved.

The IoMap that `make_iomap` returns must hold `element`, as its `input`. The cache
keeps the element itself, so the element lives as long as its IoMap is kept.

Use it to print the children of a vector: read the index cell in the path of a
child (`make_element_context`), and nowhere else that a move must not change.
"""
function make_reconciled_child_iomaps_cell(elements_fn, make_iomap)
    # The IoMaps of the last computation, by element, with the index each was
    # last placed at. Each computation fills a new table, which holds only the
    # elements that are there now, and puts it in place of the old one.
    cache = Ref(IdDict{Any,Any}())
    positions = Cell(@computation _map_element_positions(elements_fn()))
    Cell(@computation begin
        elems = elements_fn()
        result = Vector{Any}(undef, length(elems))
        previous = cache[]
        current = IdDict{Any,Any}()
        sizehint!(current, length(elems))
        places = peek(positions)
        for (i, x) in enumerate(elems)
            if get(places, x, 0) == _REPEATED_ELEMENT
                result[i] = make_iomap(ImmutableCell{Any}(i), x)
                continue
            end
            kept = get(previous, x, nothing)
            if kept === nothing || kept[1] === nothing
                placed = Ref(i)
                index = Cell(@computation _get_element_index(positions[], x, placed[]))
                kept = (make_iomap(index, x), placed)
            end
            kept[2][] = i
            current[x] = kept
            result[i] = kept[1]
        end
        cache[] = current
        result
    end)
end

# The mark in the positions of a collection of an element at two places.
const _REPEATED_ELEMENT = typemin(Int)

# The index of each element of `elements`, or the mark for an element at two places.
function _map_element_positions(elements)
    places = IdDict{Any,Int}()
    for (i, x) in enumerate(elements)
        places[x] = haskey(places, x) ? _REPEATED_ELEMENT : i
    end
    places
end

# The index of `element` in `places`, or `placed`, the index of its last placing,
# for an element that is gone or at two places.
function _get_element_index(places, element, placed::Int)
    index = get(places, element, nothing)
    (index === nothing || index == _REPEATED_ELEMENT) ? placed : index
end

"""
    make_reconciled_child_iomap_cell(value_fn, make_iomap) -> Cell

Single-child analogue of [`make_reconciled_child_iomaps_cell`](@ref): reconcile one
delegated child by the identity of `value_fn()`. While the value object stays the same
(e.g.
during an edit inside the value document) the built child IoMap is reused; when
the field is *swapped* for a new object, for example one of a different type,
`objectid` changes and the child IoMap is rebuilt against the new value. Reading
`value_fn()` inside the cell makes the result react to the field changing.

The IoMap that `make_iomap` returns must hold the value, as its `input`. The cache
key is `objectid(value)`, a number and not a reference, so only the cached IoMap
keeps the value alive. The key of a mutable value comes from its address, and Julia
can give that address to a new object after the value is collected. A new value
then gets the IoMap of the old one.
"""
function make_reconciled_child_iomap_cell(value_fn, make_iomap)
    cached_id = Ref{UInt64}(0)
    cached_im = Ref{Any}(nothing)
    Cell(@computation begin
        v = value_fn()
        id = objectid(v)
        if cached_im[] === nothing || cached_id[] != id
            cached_im[] = make_iomap(v)
            cached_id[] = id
        end
        cached_im[]
    end)
end
