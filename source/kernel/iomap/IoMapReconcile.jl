# Fragment of `IoMapModule` — reactive child-IoMap reconciliation. A projection
# that recomputes its child-IoMap list on a structural change would orphan every
# sibling's output object (the eager engine has no value short-circuit); these
# helpers reuse the prior child IoMap for every child that is unchanged, so an edit
# rebuilds only the slots that genuinely moved.

"""
    reconcile_child_iomaps(elements_fn, make_iomap) -> Cell

Build a reactive cell yielding the child-IoMap vector for the collection
`elements_fn()` returns, reusing the prior IoMap for every element that is the
**same object at the same index** and calling `make_iomap(index, element)` only for
a new or moved slot. Keyed by `(objectid(element), index)`: an append keeps every
surviving element's index (all reused, only the new slot built), while a delete or
front-insert shifts indices so the shifted tail re-projects — which is *correct*,
because a child's absolute reference genuinely moved there and reuse would be wrong,
not merely unminimal. `elements_fn` is read inside the cell on every recompute, so
the reactive dependency on the collection's structure is preserved.
"""
function reconcile_child_iomaps(elements_fn, make_iomap)
    cache = Dict{Tuple{UInt64,Int},Any}()
    Cell(Computed(() -> begin
        elems = elements_fn()
        result = Vector{Any}(undef, length(elems))
        live = Set{Tuple{UInt64,Int}}()
        for (i, x) in enumerate(elems)
            key = (objectid(x), i)
            push!(live, key)
            im = get(cache, key, nothing)
            if im === nothing
                im = make_iomap(i, x)
                cache[key] = im
            end
            result[i] = im
        end
        for k in collect(keys(cache))
            k in live || delete!(cache, k)
        end
        result
    end))
end

"""
    reconcile_child_iomap(value_fn, make_iomap) -> Cell

Single-child analogue of [`reconcile_child_iomaps`](@ref): reconcile one delegated
child by the identity of `value_fn()`. While the value object stays the same (e.g.
editing a string in place) the built child IoMap is reused; when the field is
*swapped* for a new object — crucially a different type — `objectid` changes and the
child IoMap is rebuilt against the new value. Reading `value_fn()` inside the cell
makes the result react to the field changing.
"""
function reconcile_child_iomap(value_fn, make_iomap)
    cached_id = Ref{UInt64}(0)
    cached_im = Ref{Any}(nothing)
    Cell(Computed(() -> begin
        v = value_fn()
        id = objectid(v)
        if cached_im[] === nothing || cached_id[] != id
            cached_im[] = make_iomap(v)
            cached_id[] = id
        end
        cached_im[]
    end))
end
