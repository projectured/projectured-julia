# The document layer

Layer 7 of the kernel — the **document contract** every concrete document
subtypes and every projection consumes. This page is the layer's structural
overview; for the plain-English "what is a document" guide (domain, document,
selection, operation, projection) see the repo-level
[documentation/concepts.md](../../../documentation/concepts.md).

The layer lives in [main/document/](../main/document/), inside one aggregator
module (`DocumentModule`) split across fragments that share its namespace:

```
DocumentModule.jl   (DocumentModule)  — the aggregator: imports Cell, exports every public name
    ├─ DocumentInterface.jl  — the contract: the Document supertype + the open generics
    │                          (is_element_collection / is_walk_opaque / copy_document /
    │                          sync_document! / search_documents), declaration-only
    ├─ DocumentDefaults.jl   — default behaviours: is_element_collection / is_walk_opaque = false + debug show
    ├─ DocumentCopy.jl       — copy_document: deep copy, kind-preserving or kind-converting
    ├─ DocumentSync.jl       — sync_document!: the double-buffer shadow sync
    ├─ DocumentMacro.jl      — @document: the document codegen (injects the selection field)
    ├─ DocumentWalk.jl       — walk_document: the one reflection walk, parameterized by DocumentWalk
    ├─ DocumentSearch.jl     — search_documents: the value-collecting walk
    └─ ForwardProtocol.jl    — @forward_protocol / @forward_vector_protocol /
                               @adapt_map_protocol: give a wrapper another type's protocol
```

`DocumentInterface.jl` is the layer's contract file: an abstract type plus
bodiless generic *declarations* only, machine-checked by the layering guard
(AR-INTERFACE-DECLARES-ONLY). Every other file is a **fragment** — a module-less
file sharing the aggregator's namespace — so the whole layer is one module with no
internal API boundaries; splitting the machinery into separate modules would only
multiply import headers.

Concrete engine documents do not live in this layer: `Collection` and `Primitive`
live in `base`, `ScreenDocument` in `visual`. The **document layer is the
contract**; concrete documents belong to the packages built on top of it.

## What every `@document` node carries

1. **A `selection` field.** `@document` appends a `selection::Reference = nothing`
   field (always last, always defaulted); declaring one by hand is an error. It
   names what is selected *inside* this node — a `ReferencePath`, or `nothing`.
   `Reference` is emitted as a **bare symbol**, resolved in the domain's own
   scope, so the document layer takes no upward dependency on the reference layer
   (Layer 8) that defines the type. The generics that *read and write* the
   selection — `get_selection` / `clear_selection!` / `set_selection!` /
   `with_selection` — are the **selection layer's** (Layer 9), not this one's; see
   [selection.md](selection.md).
2. **Field names ARE the reference vocabulary.** A `FieldReference("foo")` in a
   reference path is resolved by `getfield(document, :foo)` — so struct field
   names are public API. Renaming a field silently breaks every stored reference.
   Choose field names deliberately.

## The contract surface

`DocumentInterface.jl` declares the open generics a concrete document — or a
domain — fills in:

- **`is_element_collection`** — `true` when children are addressed by position
  (`[i]`) rather than by named field; steers the reflection walk. Defaults to
  `false` (in `DocumentDefaults.jl`); a 1-D positional collection opts in.
- **`is_walk_opaque`** — `true` when a document is a walk leaf (its internals are
  implementation detail, not addressable content). Defaults to `false`.
- **`copy_document`** — deep copy (below).
- **`sync_document!`** — the shadow sync (below); the kernel handles both record
  and positional-collection shapes.
- **`search_documents`** — the reflection walk's value-collecting entry point
  (below).

## The value protocol

Two operations every document reuses, both generic over structure — struct
fields (`fieldnames`), `Vector` elements, and per-slot cells are all traversed
uniformly:

- **`copy_document`** ([DocumentCopy.jl](../main/document/DocumentCopy.jl)) —
  deep-copies a subtree, allocating fresh `Cell`s so the copy shares no reactive
  state with the source. `copy_document(doc)` preserves each cell's kind;
  `copy_document(K, doc)` rebuilds every cell as kind `K` (reactive ↔ mutable ↔
  immutable).
- **`sync_document!`** ([DocumentSync.jl](../main/document/DocumentSync.jl)) — the
  double-buffer shadow sync: mutate a `MutableCell`-kind document freely (no
  per-edit reactive overhead), then at a pause point diff-copy it into a
  `ReactiveCell`-kind shadow, writing a shadow cell only when its value changed so
  the reactive graph sees a minimal invalidation set. One walk handles both
  shapes: a **record** (children are named fields) syncs field-by-field, and a
  **positional collection** (`is_element_collection`) syncs its elements by index
  through the vector protocol.

Both lean on cell-layer primitives — `copy_cell_as` (clone a cell in its own kind;
the cell contract) and `get_cell_struct_kind` (the cell kind a value's fields are
built from; the cell-struct toolkit) — since a document's kind lives in its field
cells, not in its type name.

## The reflection walk

There is exactly one traversal of an object graph
([DocumentWalk.jl](../main/document/DocumentWalk.jl)): `walk_document` descends
positional collections, dicts, arrays, and structs uniformly, stops at scalar
leaves / `is_walk_opaque` nodes / `maxdepth`, and folds a scalar match up to its
enclosing `Document`. What it deliberately leaves open is how to *name* the node
it stands on — those are the location functions of a `DocumentWalk`, a parameter
object the caller supplies (`locate_field` / `locate_element` / `initial` /
`policy`). Its two callers differ only there: `search_documents`
([DocumentSearch.jl](../main/document/DocumentSearch.jl)) uses the defaults, so a
node's location is the node itself, while `search_references` (one layer up)
supplies functions that build a `ReferencePath`. Passing the location functions in
— rather than dispatching them off a subtype — is what keeps the walk *below* the
reference layer while still serving it: the walk knows nothing of `ReferencePath`,
the caller supplies it.

## The protocol helpers

[ForwardProtocol.jl](../main/document/ForwardProtocol.jl) gives a wrapper document
another type's method protocol without a hand-written method per function:

- **`@forward_protocol [fns] on T to field`** — forward the listed functions to a
  backing field.
- **`@forward_vector_protocol on T to field`** — forward the whole vector protocol;
  the named-set shorthand for `@forward_protocol`.
- **`@adapt_map_protocol on T to field with EntryCtor(key, value)`** — *adapt* a
  sequence of entry records into an ordered map. Not delegation: the backing field
  is integer-indexed, so the keyed methods translate between a key and its matching
  entry.

## Debug rendering

[DocumentDefaults.jl](../main/document/DocumentDefaults.jl) gives `Document` a
depth-limited `Base.show` (bounded by the `:document_depth` IOContext key, with the
`selection` field skipped as noise). A debug aid only — nothing in the editor
pipeline reads it; a domain that wants a *presentable* rendering writes a
projection, not a `show` method.

## Testing pressure

Kernel tests for this layer use ONLY a test-local `@document struct ToyNode`,
never `Collection` or `Primitive`. That constraint — you cannot reach for the
engine documents as fixtures — is what keeps the interface sufficient. If the
contract cannot be exercised without the concrete documents, it is not actually a
contract. See
[test/document/DocumentContractTest.jl](../test/document/DocumentContractTest.jl).
