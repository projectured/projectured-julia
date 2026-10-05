# The document layer

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

Layer 10 of the kernel — the **document contract** every concrete document
subtypes and every projection consumes. This page is the layer's structural
overview; for the plain-English "what is a document" guide (domain, document,
selection, operation, projection) see the repo-level
[documentation/design/concepts.md](../../design/concepts.md).

The layer lives in [source/kernel/document/](../../../source/kernel/document/), inside one aggregator
module (`DocumentModule`) split across fragments that share its namespace:

```
DocumentModule.jl   (DocumentModule)  — the aggregator: imports the cell and struct layers, exports every public name
    ├─ DocumentInterface.jl  — the contract: the Document supertype + the open generics
    │                          (the traits, the layout registry, the title, the seams of a
    │                          wrapper, copy_document, sync_document! and their hooks,
    │                          search_documents), declaration-only
    ├─ DocumentDefaults.jl   — the default of each generic, HiddenElements, and the debug show
    ├─ DocumentCopy.jl       — copy_document: deep copy, kind-preserving or kind-converting
    ├─ DocumentSync.jl       — sync_document!: the double-buffer shadow sync
    ├─ DocumentMacro.jl      — @document and @document_preset: the document codegen
    │                          (the layouts, the layout registry, the selection field)
    ├─ SelectionDocument.jl  — SelectionDocument, the value a selection cell holds, and
    │                          unwrap_selection
    ├─ DocumentWalk.jl       — walk_document: the one reflection walk, parameterized by DocumentWalk
    ├─ DocumentSearch.jl     — search_documents: the value-collecting walk
    └─ ForwardProtocol.jl    — @forward_protocol / @forward_vector_protocol /
                               @adapt_map_protocol: give a wrapper another type's protocol
```

`DocumentInterface.jl` is the layer's contract file: an abstract type plus
bodiless generic *declarations* only, machine-checked by the layering guard
(PAR-INTERFACE-DECLARES-ONLY). Every other file is a **fragment** — a module-less
file sharing the aggregator's namespace — so the whole layer is one module with no
internal API boundaries; splitting the machinery into separate modules would only
multiply import headers.

Concrete engine documents do not live in this layer: the collections live in
the platform's collection slice, the primitives in its primitive slice, and
`ScreenDocument` in its screen slice. The **document layer is the contract**;
concrete documents belong to the packages built on top of it.

## What every `@document` node carries

1. **A `selection` field.** `@document` appends the field
   `selection::Union{Nothing, Reference, SelectionDocument} = nothing` as the last
   field. It names what is selected *inside* this node: a `Reference`, a
   `SelectionDocument`, or `nothing`. A schema can declare `selection` itself, and
   the field must then be the last one; a value document does this to fix the
   value type of the field (see [macros.md](macros.md)). `Reference` is emitted as
   a **bare symbol**, resolved in the domain's own scope, so the document layer
   takes no upward dependency on the reference layer (Layer 11) that defines the
   type. `SelectionDocument` is defined in this layer, so the macro puts the type
   itself in the expansion.
2. **A selection that is live or dormant.** A `SelectionDocument` holds a
   reference in `primary`, and `live` says whether it is the one selection the
   editor acts on. A document that keeps the selection it loses, such as a tab
   group, holds a dormant one. A read of the property `selection` passes the
   value of the cell through `unwrap_selection`: a live `SelectionDocument` gives
   its reference, and a dormant one gives `nothing`. The generics that *read and
   write* the selection — `get_selection` / `clear_selection!` / `set_selection!`
   — are the **selection layer's** (Layer 12), not this one's; see
   [selection.md](selection.md).
3. **Field names ARE the reference vocabulary.** A `FieldReferenceStep("foo")` in a
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
- **The layout registry** — `get_document_family`, `get_document_cell_type`,
  `get_document_native_type` and `get_document_schema_name`. They answer the
  family of a schema, its cell layout, its native layout (or `nothing`) and the
  name that the programmer wrote. `@document` writes the methods for each schema,
  so a caller asks for a layout and does not name its type. The defaults answer a
  hand-written document.
- **`get_document_title`** — the name that a document carries for itself, or
  `nothing`, the default. Each slice writes the method for its own documents.
- **The seams of a wrapper** — `get_wrapped_document`, `replace_wrapped_document!`
  and `get_edited_field`. A transparent wrapper, such as a history or a tab, adds
  one method to each. The defaults answer the node itself, the replacement, and
  `nothing`.
- **`is_collection_field_type`** and **`get_cell_layout_field_type`** — asked by
  `@document` at expansion, keyed on the symbol of a declared field type. A
  collection type of a higher package registers its name. The macro then wraps a
  raw vector in that collection, and the cell layout of a field declared as a
  `Vector` holds the reactive collection. So the document layer names no concrete
  collection type.

`@document` itself has more parts: the layout list, which says which layouts a
schema emits, and `@document_preset`, which fixes one layout list for a package.
[macros.md](macros.md) describes them.

## The value protocol

Two operations every document reuses, both generic over structure — struct
fields (`fieldnames`), `Vector` elements, and per-slot cells are all traversed
uniformly:

- **`copy_document`** ([DocumentCopy.jl](../../../source/kernel/document/DocumentCopy.jl)) —
  deep-copies a subtree, allocating fresh `Cell`s so the copy shares no reactive
  state with the source. `copy_document(policy, doc)` preserves each cell's kind,
  steered by a `CopyPolicy` (see [A copy under a policy](#a-copy-under-a-policy));
  `copy_document(doc)` is that walk under `PlainCopyPolicy`.
  `copy_document(K, doc)` rebuilds every cell as kind `K` (reactive ↔ mutable ↔
  immutable).
- **`sync_document!`** ([DocumentSync.jl](../../../source/kernel/document/DocumentSync.jl)) — the
  double-buffer shadow sync: mutate a `MutableCell`-kind document freely (no
  per-edit reactive overhead), then at a pause point diff-copy it into a
  `ReactiveCell`-kind shadow, writing a shadow cell only when its value changed so
  the reactive graph sees a minimal invalidation set. One walk handles both
  shapes: a **record** (children are named fields) syncs field-by-field, and a
  **positional collection** (`is_element_collection`) syncs its elements by index
  through the vector protocol.

Both walks are optionally **bounded**. A full walk per frame of an object with
thousand-entry collections is wasted work, so `sync_document!` and the
kind-converting `copy_document(K, doc)` take a `policy` and consult three
generics at every child —
`is_descendable_for_sync`, `compute_sync_element_limit`,
`make_unsynced_placeholder` (declared in
`DocumentInterface.jl`, defaulted in `DocumentDefaults.jl`). The walk gives the
elements that it does not keep to `make_unsynced_placeholder` as a
`HiddenElements`, a vector over the source that copies nothing. The default policy
`nothing` descends everywhere and keeps every element, so an un-policed walk is
the walk described above and pays nothing for the option. This layer never names
a marker *type*, and never sees a policy that is not handed to it: it calls
whoever supplied the policy for what stands where the walk stopped.

The same three hooks bound the walk that the reflection slice's
`sync_reflection!` uses to grow a shadow of an arbitrary Julia value one level
at a time, instead of walking the whole value up front. See
[reflection.md](../platform/reflection/reflection.md) for the policy and the widget view
built on that shadow.

Both use two primitives of the layers below, because the kind of a document is
in its field cells and not in its type name. `make_similar_cell`, of the cell layer,
makes a cell in the kind of another. `get_cell_struct_kind`, of the struct layer,
returns the kind of the cells of a value.

## A copy under a policy

`copy_document(policy, value)` is the copy that keeps each cell's kind. The
policy is a `CopyPolicy`, and it comes first, so no method is ambiguous with the
kind-converting form. A policy steers the walk in two ways:

- **A method on the pair.** `copy_document(::MyPolicy, ::MyDocument)` replaces
  one step of the walk, and dispatch keeps the other steps. The method can
  rebuild the node with `copy_document_fields(policy, document; replacements...)`,
  which copies each field through the walk and puts the value given in a field
  named in `replacements`.
- **Five hooks**, each with the policy first:

| Hook | Asked | Default |
|---|---|---|
| `is_descendable_for_copy(policy, document)` | at each document, the root included | `true` |
| `make_copy_placeholder(policy, document)` | where the walk stops | an error |
| `copy_computed_cell(policy, cell)` | at a cell that computes (`is_computed_cell`) | a cell that stores the value it has now |
| `copy_selection_cell(policy, cell)` | at a document's `selection` cell | a cell that stores the selection it has now, even when a projection computes it |
| `get_copy_memo(policy)` | once per rebuild | `nothing`: no record |

With a memo, a document met twice is one copy, and a document met inside its
own copy stops the walk. A hook stops the whole copy with
`throw(DocumentCopyException(value, reason))`.

A `CellVector` keeps one difference: the plain copy starts the list with no
selection, and every other policy copies the selection.

### The duplicate

A **duplicate** is the copy a person gets when they duplicate a pane: a document
of the same kind that they control on its own.
`make_document_duplicate(document)` makes it with `DuplicatePolicy`, which:

- descends into a document whose kind declares a duplicate, and shares every
  other document, so what the duplicate does not own, it reads;
- stops the copy at a cell that computes, because a copy of its value looks
  live and is not;
- stops the copy at a `Function`, a `Ref` or a `Task`, because an action that
  captures the original acts on it;
- stops the copy at a document that holds itself.

`has_document_duplicate(document)` says whether a kind has a duplicate. A pane
calls it each time it prints a tab, so a method answers from the type and never
walks the tree. A kind declares its duplicate in one line, and adds a
`copy_document(::DuplicatePolicy, ::Kind)` method when one field needs custom
handling. The evaluator of `source/platform/conversation/Evaluator.jl` shares the result of
a form, because a result can be live:

```julia
has_document_duplicate(::EvaluatorDocument) = true
copy_document(policy::DuplicatePolicy, form::EvaluatorForm) =
    copy_document_fields(policy, form; result = form.result)
```

**An action that a duplicate shares receives the document it acts on; it does
not capture it.** Then one function serves the original and its duplicate. An
`Action` declares no duplicate, and a button's duplicate shares it, as every
control that shows one command does.

## The reflection walk

There is exactly one traversal of an object graph
([DocumentWalk.jl](../../../source/kernel/document/DocumentWalk.jl)): `walk_document` descends
positional collections, dicts, arrays, and structs uniformly, stops at scalar
leaves / `is_walk_opaque` nodes / `maxdepth`, and folds a scalar match up to its
enclosing `Document`. A `descend(parent, child)` keyword, given by the caller,
returns whether the walk enters `child` from `parent` at all; a child that it
does not enter is neither matched nor walked, and the default enters every child. What it
deliberately leaves open is how to *name* the node it stands on. Those are the
location functions of a `DocumentWalk`, a parameter object the caller supplies (`locate_field` / `locate_element` / `initial` /
`policy`). Its two callers differ only there: `search_documents`
([DocumentSearch.jl](../../../source/kernel/document/DocumentSearch.jl)) uses the defaults, so a
node's location is the node itself, while `search_references` (one layer up)
supplies functions that build a `Reference`. The walk passes the location
functions in, rather than dispatching them off a subtype. That keeps the walk
*below* the reference layer while still serving it: the walk takes no
dependency on `Reference`, and the caller supplies it.

## The protocol helpers

[ForwardProtocol.jl](../../../source/kernel/document/ForwardProtocol.jl) gives a wrapper document
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

[DocumentDefaults.jl](../../../source/kernel/document/DocumentDefaults.jl) gives `Document` a
depth-limited `Base.show` (bounded by the `:document_depth` IOContext key, with the
`selection` field skipped as noise). This is a debug aid only. Nothing in the
editor pipeline reads it. A domain that needs a *presentable* rendering writes
a projection, not a `show` method.

A field value that is not a document prints in full only when the value bounds
its own text: a bits value, a string, a symbol, a type, a module, a function that
captures nothing, a value of a type that defines `show`, or a container or a
struct of such values, to a depth of three. Any other value prints as
`TypeName(…)`. Base's default `show` of a struct prints every object that the
value reaches. A closure or a `Ref` in a field reaches the editor, so that `show`
does not end in a useful time.

## Testing pressure

The kernel tests of this layer use ONLY documents that they declare themselves:
`ToyNode` and the `Contract*` documents in
[DocumentContractTest.jl](../../../test/kernel/document/DocumentContractTest.jl), and
the `Dm*` documents and the collection `DmCollection` in
[DocumentMacroTest.jl](../../../test/kernel/document/DocumentMacroTest.jl). They
never use a collection, a primitive or a screen document as a fixture. That
constraint is what keeps the interface sufficient. If the contract cannot be
exercised without the concrete documents, it is not actually a contract.

The tests of the walk, the bounded sync and the duplicate use collections and
primitives, so they are in the platform suite: `DocumentWalkTest.jl`,
`BoundedSyncTest.jl` and `DocumentDuplicateTest.jl` in `test/platform/document/`.
