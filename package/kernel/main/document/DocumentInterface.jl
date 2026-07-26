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
`ElementReferenceStep`, i.e. `[i]`) rather than by named field — a 1-D positional
sequence, not a record. A reflection walk keys off this to emit `[i]` element
paths for a collection instead of descending into its internal storage fields,
so it never has to name a concrete collection type. Defaults to `false`
(records, leaves, and 2-D collections all answer `false`); a 1-D positional
collection opts in with its own method.
"""
function is_element_collection end

"""
    document_family(x) -> Type
    document_family(::Type) -> Type

The **family** a document belongs to: the identity used to decide whether two
documents are the same document — including when they are two different *variant
layouts* of one `@document` schema (the isbits/immutable stem and the native
`mutable struct`, which do not share a type wrapper). Defaults to the type's name
wrapper (`Base.typename(T).wrapper`), so a plain type is its own family; the
`@document` macro overrides it to the schema's **abstract family type**, so every
variant of one schema answers the same family.
"""
function document_family end

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
    is_collection_field_type(::Val{name}) -> Bool

`true` when a `@document` field declared with type `name` should receive the
collection-construction sugar — a positional constructor that wraps a raw
`AbstractVector` into that type (`Foo([a, b])` / `Foo(a, b)`). The expansion-time
companion of `is_element_collection`, keyed on the declared type's **symbol** so
the `@document` macro can ask without resolving — or even naming — the type: a
collection type registers `Val{:ItsName}` from the package that defines it (and
must offer a `Type(::AbstractVector)` constructor), so the document layer names no
concrete collection type. Defaults to `false`.
"""
function is_collection_field_type end

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
    should_descend_sync(policy, depth, slot) -> Bool
    sync_element_limit(policy, source, shadow) -> Int
    unsynced_placeholder(policy, source, current) -> value

The **bound** on a sync or a copy. `sync_document!`/`copy_document` consult these
at every child; the default policy (`nothing`) answers "descend", "take them all"
and never reaches the third, so an un-policed walk is the whole walk.

A policy that answers otherwise makes the walk stop, and
`unsynced_placeholder` supplies what stands where it stopped — a marker the
policy's owner understands. That keeps the marker's *type* out of this layer:
the walk knows only that something goes in the slot.

`depth` is the child's depth (1 for a root's children). `slot` is what occupies
it now — including a placeholder the policy itself put there, which is how a
policy recognises "already stopped here" and how a consumer's request to go
deeper reaches the walk. `unsynced_placeholder` likewise receives `current` so a
policy can hand back the placeholder already standing there rather than a fresh
one, leaving the shadow's identity alone.

`sync_element_limit` is given the whole source and shadow rather than counts,
because how many elements to keep depends on what the shadow already holds —
including whether its trailing placeholder was flagged — and that is the
policy's own bookkeeping, not this layer's.

Defaults in `DocumentDefaults.jl`; see `package/base/doc/bounded-sync.md`
for the policy `base` supplies.
"""
function should_descend_sync end
function sync_element_limit end
function unsynced_placeholder end

"""
    search_documents(obj, predicate; include_selection=false, maxdepth=64, raw=false) -> Vector
    search_documents(obj, query::Union{AbstractString,Regex}; …)                      -> Vector

Walk any object and return the matching nodes, **each at most once** even when a
node is shared. A `String` (substring) or `Regex` matches leaf nodes by their
string form. By default the result is **document-scoped**: a scalar match folds
up to the nearest enclosing `Document`; pass `raw=true` to return the exact
matched value.
"""
function search_documents end
