# Fragment of `DocumentModule` — the reflection search over a document tree.
#
# `search_documents` walks an arbitrary document tree and collects the matching
# nodes. By default it reports *documents*: a match on a raw scalar (a String /
# Number leaf, e.g. a `PrimitiveString`'s value) folds up to the nearest
# enclosing `Document`, so every result is a selectable node. `raw=true` reports
# the exact matched value instead (scalars included). A path-producing
# counterpart one layer up walks the same structure with the same `raw` switch;
# the two walks are structurally parallel (element-collection / dict / array /
# fields), so a fix to one branch here should be mirrored there.

# A node is a search leaf — nothing to descend into — when it is a scalar Julia
# value or an opaque document (see `is_opaque`).
_is_search_leaf(x) = x === nothing || x isa Number || x isa AbstractString ||
                     x isa Symbol || x isa Char || is_opaque(x)

# A search query is either a predicate (called on each node) or a String / Regex.
# A String/Regex is turned into a predicate matching any *leaf* node whose textual
# form (the string / symbol / number / char rendered) contains the substring /
# matches the regex. Struct and collection nodes have no textual form, so they
# never match a String/Regex query — pass a predicate to match on type or shape.
_search_text(x::AbstractString) = x
_search_text(x::Symbol)         = string(x)
_search_text(x::Number)         = string(x)
_search_text(x::Char)           = string(x)
_search_text(::Any)             = nothing

_text_query(q::AbstractString) = x -> (t = _search_text(x); t !== nothing && occursin(q, t))
_text_query(q::Regex)          = x -> (t = _search_text(x); t !== nothing && occursin(q, t))

"""
    search_documents(obj, predicate; include_selection=false, maxdepth=64, raw=false) -> Vector
    search_documents(obj, query::Union{AbstractString,Regex}; …)                      -> Vector

Walk any object and return the matching nodes, **each at most once** even when a
node is shared / reachable by several paths. A `String` (substring) or `Regex`
may be passed instead of a predicate to match leaf nodes by their textual form.

By default the result is **document-scoped**: a match on a raw scalar (a String /
Number / Bool leaf — e.g. a `PrimitiveString`'s `value`) folds up to the nearest
enclosing `Document`, so every returned node is an addressable, selectable
document. A predicate that matches a `Document` directly returns that document. A
scalar match with no enclosing document (e.g. searching a bare iomap or `Dict`
whose match sits above any document) is dropped.

```julia
strings = search_documents(editor.document, v -> v isa JsonString)
alice   = search_documents(editor.document, "Alice")   # the JsonString, not the raw "Alice"
```

Pass `raw=true` to return the **exact matched value** instead — scalars included,
no folding — the object-valued counterpart to a raw `search_references`:

```julia
search_documents(editor.document, "Alice"; raw=true)   # ["Alice"]
```

`include_selection` includes `selection` fields in the walk. A single global
visited set makes the walk visit each object once, so shared subtrees / DAGs are
not re-walked and cyclic graphs terminate. `maxdepth` separately bounds recursion
depth for structures that are never the *same* object, e.g. an infinite lazy list
whose nodes are generated fresh on demand.
"""
function search_documents(obj, predicate; include_selection::Bool=false, maxdepth::Int=64, raw::Bool=false)
    results = Any[]
    _search_documents!(results, IdDict{Any,Bool}(), unwrap_cell(obj), predicate,
                       nothing, IdDict{Any,Bool}(), include_selection, maxdepth, raw)
    results
end

search_documents(obj, query::Union{AbstractString,Regex}; kwargs...) =
    search_documents(obj, _text_query(query); kwargs...)

# `enclosing` is the nearest `Document` ancestor of `obj` (or `obj` itself when it
# is a document); a folded (`raw=false`) scalar match is reported against it.
# `reported` dedups by target identity — sibling scalars under one document share
# the same enclosing object, so the document is reported once.
function _search_documents!(results, reported, obj, predicate, enclosing, seen, include_selection, depth, raw)
    haskey(seen, obj) && return
    seen[obj] = true
    here = obj isa Document ? obj : enclosing
    if (try predicate(obj) catch; false end)
        target = raw ? obj : here
        if target !== nothing && !haskey(reported, target)
            push!(results, target); reported[target] = true
        end
    end
    depth <= 0 && return
    _is_search_leaf(obj) && return
    if is_element_collection(obj)
        for i in 1:length(obj)
            _search_documents!(results, reported, unwrap_cell(obj[i]), predicate, here, seen, include_selection, depth - 1, raw)
        end
    elseif obj isa AbstractDict
        # Walk values, not `fieldnames` (which descends into hash-table internals
        # whose `Memory` buffers have undefined slots).
        for v in values(obj)
            _search_documents!(results, reported, unwrap_cell(v), predicate, here, seen, include_selection, depth - 1, raw)
        end
    elseif obj isa AbstractArray
        for i in 1:length(obj)
            isassigned(obj, i) || continue
            _search_documents!(results, reported, unwrap_cell(obj[i]), predicate, here, seen, include_selection, depth - 1, raw)
        end
    else
        fnames = try fieldnames(typeof(obj)) catch; () end
        for fn in fnames
            (fn == :ref || (fn == :selection && !include_selection)) && continue
            isdefined(obj, fn) || continue
            _search_documents!(results, reported, unwrap_cell(getfield(obj, fn)), predicate, here, seen, include_selection, depth - 1, raw)
        end
    end
end
