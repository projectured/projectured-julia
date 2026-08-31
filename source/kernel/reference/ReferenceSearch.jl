# Fragment of `ReferenceModule` — the **path-producing** walk over
# `walk_document`: locations are `Reference`s.
#
# The walk itself lives in the document layer, one layer down, and knows nothing
# of references. It cannot: a `Reference` is declared *here*. It takes the
# location functions as parameters instead — this file supplies ones that build
# reference paths, while the value-collecting `search_documents` supplies the
# defaults that hand back the child object.

# The path-valued walk: descending by a field appends a `FieldReferenceStep`, by an
# index an `ElementReferenceStep`, and the root is the empty path. The `:once_per_path`
# cycle policy (reports distinct paths, not objects) is documented on
# `search_references` below.
const _PATH_WALK = DocumentWalk(
    locate_field   = (location, name, child) -> extend_reference(location, FieldReferenceStep(string(name))),
    locate_element = (location, index, child) -> extend_reference(location, ElementReferenceStep(index)),
    initial        = root -> EmptyReference(),
    policy         = :once_per_path)

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

The returned paths are **canonical at rest**: each navigation step is preceded by
a `TypeReferenceStep(typeof(node))` checkpoint (via [`annotate_reference_types`](@ref)),
so results are self-describing and carry replay-validation checkpoints.
`evaluate_reference` honours the checkpoints; pass a result through
`strip_reference_types` first if a consumer needs the plain navigation-only path.

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
whose nodes are generated fresh on demand.

`obj` need not be a document — the walk descends **any** object graph (structs,
arrays, dicts), not only document trees. Searching derived/intermediate state for
debugging is one such use; the debugging guide's "Searching the pipeline state"
covers it (those paths are for inspection only, not selectable).
"""
function search_references(obj, predicate; kwargs...)
    root = unwrap_cell(obj)
    paths = walk_document(_PATH_WALK, root, predicate; kwargs...)
    Reference[annotate_reference_types(root, p) for p in paths]
end

search_references(obj, query::Union{AbstractString,Regex}; kwargs...) =
    search_references(obj, string_predicate(query); kwargs...)
