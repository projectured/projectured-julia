# Fragment of `ReferenceModule` — the **path-producing** walk over
# `walk_document`: locations are `Reference`s.
#
# The walk itself lives in the document layer, one layer down, and knows nothing
# of references. It cannot: a `Reference` is declared *here*. It takes the
# location functions as parameters instead — this file supplies ones that build
# reference paths, while the value-collecting `search_documents` supplies the
# defaults that hand back the child object.

# The path-valued walk. A location is a reversed chain of steps: `()` for the root,
# and `Pair{Any,Any}(parent, step)` for a child, where `step` is the name of a field
# (a `Symbol` or a `String`) or the 1-based index of an element (an `Int`). A visit
# costs one pair, and `search_references` builds a `Reference` for a result only.
# The chain has one type at every depth, so the walk compiles once for each type of
# node. The `:once_per_path` cycle policy (reports distinct paths, not objects) is
# documented on `search_references` below.
const _PATH_WALK = DocumentWalk(
    locate_field   = (location, name, child) ->
        Pair{Any,Any}(location, name isa Symbol ? name : string(name)),
    locate_element = (location, index, child) -> Pair{Any,Any}(location, index),
    initial        = root -> (),
    policy         = :once_per_path)

# The `Reference` of a location of `_PATH_WALK`, read from the deepest step back to
# the root.
function _make_location_reference(location)
    path = EmptyReference()
    while location isa Pair
        step = location.second
        head = step isa Int ? ElementReferenceStep(step) :
                              FieldReferenceStep(string(step))
        path = ConcreteReference(head, path)
        location = location.first
    end
    path
end

"""
    search_references(obj, predicate; include_selection=false, maxdepth=64, raw=false) -> Vector{Reference}
    search_references(obj, query::Union{AbstractString,Regex}; …)                      -> Vector{Reference}

Walk any object and return a `Reference` to every match. Pass a predicate, or
a `String` (substring) / `Regex` that matches leaf nodes by their string form,
e.g. `search_references(editor.document, "Alice")` or `search_references(doc, r"TODO|FIXME")`.
Cells are unwrapped transparently (no path step); struct fields contribute a
`FieldReferenceStep`, and array / `CellVector` elements an `ElementReferenceStep`.

By default the paths are **document-scoped**: a match on a raw scalar folds to
the path of its nearest enclosing `Document`, so every returned path addresses a
selectable node. Pass `raw=true` to get the path to the **exact matched node**
instead (scalar leaves included) — the path-valued counterpart to
`search_documents(...; raw=true)`.

The returned paths are **canonical at rest**: each node records the type of the
document node that it stands on (via [`annotate_reference_types`](@ref)), so results
are self-describing and can be checked again after an edit. `evaluate_reference`
checks those types; pass a result through `strip_reference_types` first if a
consumer needs the plain navigation-only path.

```julia
for ref in search_references(editor.document, v -> v isa JsonString && occursin("TODO", v.value))
    node = evaluate_reference(editor.document, ref)   # the matching JsonString
end
```

`include_selection` includes `selection` fields in the walk. **Every distinct path
to a matching node is returned** — a shared object reachable several ways is a
different *location*, hence a different selection, each time (document-scoped
folding still reports each enclosing-document location once). This is the one place
this search differs from [`search_documents`](@ref), which reports each matching
*node* once; the difference is the cycle policy (`:once_per_path` here vs
`:once_per_object` there), the one walk parameter the two set differently. Only
paths that loop back through an object
already on the current path are dropped, which keeps cyclic graphs (e.g. a
doubly-linked list's `prev`/`next`) finite. `maxdepth` separately bounds recursion
depth for structures that are never the *same* object, e.g. an infinite lazy list
whose nodes are generated fresh on demand. `descend(parent, child)` returns whether
the walk enters `child`, and the default enters every child; see `walk_document`.

`obj` need not be a document — the walk descends **any** object graph (structs,
arrays, dicts), not only document trees. Searching derived/intermediate state for
debugging is one such use; the debugging guide's "Searching the pipeline state"
covers it (those paths are for inspection only, not selectable).
"""
function search_references(obj, predicate; kwargs...)
    root = unwrap_cell(obj)
    locations = walk_document(_PATH_WALK, root, predicate; kwargs...)
    Reference[annotate_reference_types(root, _make_location_reference(location))
              for location in locations]
end

search_references(obj, query::Union{AbstractString,Regex}; kwargs...) =
    search_references(obj, make_string_predicate(query); kwargs...)
