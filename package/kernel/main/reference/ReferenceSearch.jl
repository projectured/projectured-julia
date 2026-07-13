# Fragment of `ReferenceModule` — the path-producing **reflection search**.
#
# `search_references` reports *where* each matching node lives, as an annotated
# `ReferencePath`. Like `search_documents` (the value-collecting counterpart one
# layer down in the document layer) it is document-scoped by default — a raw
# scalar match folds to the path of its nearest enclosing `Document`, so the path
# is selectable — with a `raw=true` opt-out. The two walks are structurally
# parallel; keep them in sync. The small query / leaf helpers below duplicate the
# document layer's one-liners (as `_deref_cell` in `ReferenceStep.jl` already does)
# rather than importing them across the layer boundary; they key off the exported
# `is_opaque` / `is_element_collection` document traits.

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
    search_references(obj, predicate; include_selection=false, maxdepth=64, raw=false) -> Vector{ReferencePath}
    search_references(obj, query::Union{AbstractString,Regex}; …)                      -> Vector{ReferencePath}

Walk any object and return a `ReferencePath` to every match. Pass a predicate, or
a `String` (substring) / `Regex` that matches leaf nodes by their textual form,
e.g. `search_references(editor.document, "Alice")` or `search_references(doc, r"TODO|FIXME")`.
Cells are unwrapped transparently (no path step); struct fields contribute a
`FieldReference`, and array / `CellVector` elements an `ElementReference`.

By default the paths are **document-scoped**: a match on a raw scalar folds to
the path of its nearest enclosing `Document`, so every returned path addresses a
selectable node. Pass `raw=true` to get the path to the **exact matched node**
instead (scalar leaves included) — the path-valued counterpart to
`search_documents(...; raw=true)`.

The returned paths are **canonical at rest**: each navigation step is preceded by
a `TypeReference(typeof(node))` checkpoint (via [`annotate_reference_types`](@ref)),
so results are self-describing and carry replay-validation checkpoints.
`evaluate_reference` honours the checkpoints; pass a result through
`strip_reference_types` first if a consumer needs the plain navigation-only path.

```julia
for ref in search_references(editor.document, v -> v isa JsonString && occursin("TODO", v.value))
    node = evaluate_reference(editor.document, ref)   # the matching JsonString
end
```

`include_selection` includes `selection` fields in the walk. Every distinct path
to a matching node is returned — a shared object reachable by several paths is a
different *location* (hence a different selection) each time, so all of them are
reported (document-scoped folding still reports each enclosing-document location
once). Only paths that loop back through an object already on the current path are
dropped, which keeps cyclic graphs (e.g. a doubly-linked list's `prev`/`next`)
finite. `maxdepth` separately bounds recursion depth for structures that are never
the *same* object, e.g. an infinite lazy list whose nodes are generated fresh on
demand. See [`search_documents`](@ref) for the matching nodes themselves (each once).

`obj` need not be a document — the walk descends **any** object graph (structs,
arrays, dicts), not only document trees. Searching derived/intermediate state for
debugging is one such use; the debugging guide's "Searching the pipeline state"
covers it (those paths are for inspection only, not selectable).
"""
function search_references(obj, predicate; include_selection::Bool=false, maxdepth::Int=64, raw::Bool=false)
    results = ReferencePath[]
    root = _deref_cell(obj)
    _search_references!(results, IdDict{Any,Bool}(), root, predicate,
                        EmptyReferencePath(), nothing, IdDict{Any,Bool}(), include_selection, maxdepth, raw)
    # Leave search results in canonical form: annotate each plain navigation path
    # with `TypeReference(typeof(node))` checkpoints against `obj`, so the
    # references are self-describing and carry replay-validation checkpoints
    # (see annotate_reference_types).
    ReferencePath[annotate_reference_types(root, p) for p in results]
end

search_references(obj, query::Union{AbstractString,Regex}; kwargs...) =
    search_references(obj, _text_query(query); kwargs...)

# `enclosing_path` is the path to the nearest enclosing document (this node's own
# `path` when it is a document); a folded (`raw=false`) scalar match reports it.
# The walk-wide `reported` set dedups targets by identity: sibling scalars under
# one document share the same `enclosing_path` object, so that document's path is
# reported once, while distinct locations (distinct path objects) are all kept.
function _search_references!(results, reported, obj, predicate, path, enclosing_path, seen, include_selection, depth, raw)
    # Drop only paths that loop back through an object already on *this* path:
    # `seen` holds the current path's ancestors (copied per level), so distinct
    # paths to a shared object are all reported while a path returning to one of
    # its own ancestors is neither recorded nor descended (cyclic graphs stay finite).
    if ismutable(obj)
        haskey(seen, obj) && return
        seen = copy(seen); seen[obj] = true
    end
    here = obj isa Document ? path : enclosing_path
    if (try predicate(obj) catch; false end)
        target = raw ? path : here
        if target !== nothing && !haskey(reported, target)
            push!(results, target); reported[target] = true
        end
    end
    depth <= 0 && return
    _is_search_leaf(obj) && return
    if is_element_collection(obj)
        for i in 1:length(obj)
            _search_references!(results, reported, _deref_cell(obj[i]), predicate,
                            append_reference(path, ElementReference(i)), here, seen, include_selection, depth - 1, raw)
        end
    elseif obj isa AbstractDict
        # Walk a Dict by its values, not its `fieldnames` (which would descend into
        # the hash-table internals — `.keys`/`.vals` `Memory` buffers whose unused
        # slots are undefined references). Use the key as the field step so the
        # reference is meaningful (matches how a JSON object field is addressed).
        for (k, v) in obj
            _search_references!(results, reported, _deref_cell(v), predicate,
                            append_reference(path, FieldReference(string(k))), here, seen, include_selection, depth - 1, raw)
        end
    elseif obj isa AbstractArray
        for i in 1:length(obj)
            isassigned(obj, i) || continue
            _search_references!(results, reported, _deref_cell(obj[i]), predicate,
                            append_reference(path, ElementReference(i)), here, seen, include_selection, depth - 1, raw)
        end
    else
        fnames = try fieldnames(typeof(obj)) catch; () end
        for fn in fnames
            (fn == :ref || (fn == :selection && !include_selection)) && continue
            isdefined(obj, fn) || continue
            _search_references!(results, reported, _deref_cell(getfield(obj, fn)), predicate,
                            append_reference(path, FieldReference(string(fn))), here, seen, include_selection, depth - 1, raw)
        end
    end
end
