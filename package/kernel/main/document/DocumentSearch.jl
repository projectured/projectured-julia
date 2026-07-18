# Fragment of `DocumentModule` — the **value-collecting** walk: it runs
# `walk_document` under the default `DocumentWalk`, whose locations are the objects
# themselves, so a match is reported as the matched node.
#
# Document-scoped by default — a scalar match (e.g. a `PrimitiveString`'s `value`)
# folds up to its nearest enclosing `Document`, so every result is selectable; a
# scalar with no enclosing document is dropped, and `raw=true` reports the exact
# matched value instead. Contract documented at `search_documents` in
# `DocumentInterface.jl`.
search_documents(obj, predicate; kwargs...) =
    walk_document(DocumentWalk(), obj, predicate; kwargs...)

search_documents(obj, query::Union{AbstractString,Regex}; kwargs...) =
    search_documents(obj, string_predicate(query); kwargs...)
