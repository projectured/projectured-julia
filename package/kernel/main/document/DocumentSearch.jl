# Fragment of `DocumentModule` — the **value-collecting** strategy over
# `walk_document`: locations are the objects themselves.
#
# The path-producing counterpart (`search_references`, one layer up) is the same
# walk under a different strategy — it is not a parallel implementation, and there
# is no longer anything to keep in sync between them.

"""
    ValueWalk <: DocumentWalk

The [`DocumentWalk`](@ref) whose locations are the matched **objects**. A node's
location is the node, so descending is just handing the child through.

Its cycle rule is `:once_per_object`: reaching one object by two paths yields the
same location twice, so the second visit has nothing to add.
"""
struct ValueWalk <: DocumentWalk end

child_field_location(::ValueWalk, location, name, child)    = child
child_element_location(::ValueWalk, location, index, child) = child

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

`include_selection` includes `selection` fields in the walk. `maxdepth` bounds
recursion depth for structures that are never the *same* object, e.g. an infinite
lazy list whose nodes are generated fresh on demand.

See [`search_references`](@ref) for the *paths* to the matches — the same walk,
reporting where each match lives rather than what it is. That one reports every
distinct path to a shared node; this one reports the node once.
"""
search_documents(obj, predicate; kwargs...) =
    walk_document(ValueWalk(), obj, predicate; kwargs...)

search_documents(obj, query::Union{AbstractString,Regex}; kwargs...) =
    search_documents(obj, text_query(query); kwargs...)
