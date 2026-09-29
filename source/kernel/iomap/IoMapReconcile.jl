# Fragment of `IoMapModule` — the reconcilers that reuse a child IoMap across a change.

"""
    reconcile_child_iomaps(elements_fn, make_iomap) -> Cell

Build a reactive cell yielding the child-IoMap vector for the collection
`elements_fn()` returns, reusing the prior IoMap for every element that is the
**same object at the same index** and calling `make_iomap(index, element)` only for
a new or moved slot. A projection that made every child IoMap again on a
structural change would orphan the output object of each sibling, because the
reactive engine has no value short-circuit. Keyed by `(objectid(element), index)`:
an append keeps every surviving element's index (all reused, only the new slot
built), while a delete or front-insert shifts indices so the shifted tail
re-projects — which is *correct*, because a child's absolute reference moved
there and reuse would be wrong. `elements_fn` is read inside the cell on every
recompute, so the reactive dependency on the collection's structure is preserved.

The IoMap that `make_iomap` returns must hold `element`, as its `input`. The cache
key is `objectid(element)`, a number and not a reference, so only the cached IoMap
keeps the element alive. The key of a mutable element comes from its address, and
Julia can give that address to a new object after the element is collected. A new
element at the same index then gets the IoMap of the old one.
"""
function reconcile_child_iomaps(elements_fn, make_iomap)
    # The IoMaps of the last computation. Each computation fills a new table, which
    # holds only the slots that are there now, and puts it in place of the old one.
    cache = Ref(Dict{Tuple{UInt64,Int},Any}())
    Cell(@computation begin
        elems = elements_fn()
        result = Vector{Any}(undef, length(elems))
        previous = cache[]
        current = Dict{Tuple{UInt64,Int},Any}()
        sizehint!(current, length(elems))
        for (i, x) in enumerate(elems)
            key = (objectid(x), i)
            im = get(previous, key, nothing)
            im === nothing && (im = make_iomap(i, x))
            current[key] = im
            result[i] = im
        end
        cache[] = current
        result
    end)
end

"""
    reconcile_child_iomap(value_fn, make_iomap) -> Cell

Single-child analogue of [`reconcile_child_iomaps`](@ref): reconcile one delegated
child by the identity of `value_fn()`. While the value object stays the same (e.g.
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
function reconcile_child_iomap(value_fn, make_iomap)
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
