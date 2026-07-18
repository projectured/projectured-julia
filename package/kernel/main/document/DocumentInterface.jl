# Fragment of `DocumentModule` — the document **contract**: the `Document`
# abstract type every document subtypes, and the open generics of its shared
# value protocol and reflection walk. Nothing here carries a body — the trait
# defaults live in `DocumentDefaults.jl`, deep copy in `DocumentCopy.jl`, the
# record shadow-sync in `DocumentSync.jl`, the reflection walk and value-search
# in `DocumentWalk.jl` / `DocumentSearch.jl`, and the `@document` codegen that
# declares most concrete documents in `DocumentMacro.jl`.

"""
    Document

Abstract base type for all document types. Most concrete documents are
declared with the [`@document`](@ref) macro (in the sibling
[`DocumentMacro.jl`](DocumentMacro.jl) fragment), which wraps fields in
reactive `Cell`s and generates the shared value protocol; a hand-written struct
may also subtype `Document` directly.
"""
abstract type Document end

"""
    is_element_collection(document) -> Bool

`true` when a document's children are addressed **by position** (an
`ElementReference`, i.e. `[i]`) rather than by named field — a 1-D positional
sequence, not a record. A reflection walk keys off this to emit `[i]` element
paths for a collection instead of descending into its internal storage fields,
so it never has to name a concrete collection type. Defaults to `false`
(records, leaves, and 2-D collections all answer `false`); a 1-D positional
collection opts in with its own method.
"""
function is_element_collection end

"""
    is_walk_opaque(document) -> Bool

`true` when a document is **opaque** to the reflection walk: its internals are
implementation detail, not addressable document content, so the walk treats it as
a leaf and never descends into it. Defaults to `false`; a document whose
contents are configuration or an implementation detail rather than navigable
structure opts in with its own method.
"""
function is_walk_opaque end

"""
    copy_document(value)     -> value      # preserve every cell's kind
    copy_document(K, value)  -> value      # rebuild every cell as kind K

Deep-copy a document subtree, allocating fresh `Cell`s and containers so the
result shares no mutable state with the source. The one-argument form preserves
each cell's kind; the two-argument form rebuilds every cell as kind `K`
(`ReactiveCell` / `MutableCell` / `ImmutableCell`). Plain immutable leaves
(strings, numbers, symbols) pass through unchanged.
"""
function copy_document end

"""
    sync_document!(shadow, source) -> shadow

Update the writable `shadow` document to match `source`, writing a shadow cell
**only when its value changed** — so the downstream reactive graph sees a
*minimal* invalidation set, not a wholesale rebuild. `shadow` may be any
writable kind (`ReactiveCell` or `MutableCell`); `source` may be any kind.

Both shapes are handled: a **record** (children are named fields) syncs
field-by-field, and a **positional collection** (`is_element_collection`) syncs
its elements by index through the vector protocol.
"""
function sync_document! end

"""
    search_documents(obj, predicate; include_selection=false, maxdepth=64, raw=false) -> Vector
    search_documents(obj, query::Union{AbstractString,Regex}; …)                      -> Vector

Walk any object and return the matching nodes, **each at most once** even when a
node is shared. A `String` (substring) or `Regex` matches leaf nodes by their
textual form. By default the result is **document-scoped**: a scalar match folds
up to the nearest enclosing `Document`; pass `raw=true` to return the exact
matched value.
"""
function search_documents end
