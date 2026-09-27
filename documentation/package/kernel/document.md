# The document layer

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

Layer 9 of the kernel — the **document contract** every concrete document
subtypes and every projection consumes. This page is the layer's structural
overview; for the plain-English "what is a document" guide (domain, document,
selection, operation, projection) see the repo-level
[documentation/design/concepts.md](../../design/concepts.md).

The layer lives in [source/kernel/document/](../../../source/kernel/document/), inside one aggregator
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
(PAR-INTERFACE-DECLARES-ONLY). Every other file is a **fragment** — a module-less
file sharing the aggregator's namespace — so the whole layer is one module with no
internal API boundaries; splitting the machinery into separate modules would only
multiply import headers.

Concrete engine documents do not live in this layer: `Collection` and `Primitive`
live in `base`, `ScreenDocument` in `visual`. The **document layer is the
contract**; concrete documents belong to the packages built on top of it.

## What every `@document` node carries

1. **A `selection` field.** `@document` appends a `selection::Reference = nothing`
   field (always last, always defaulted); declaring one by hand is an error. It
   names what is selected *inside* this node — a `Reference`, or `nothing`.
   `Reference` is emitted as a **bare symbol**, resolved in the domain's own
   scope, so the document layer takes no upward dependency on the reference layer
   (Layer 10) that defines the type. The generics that *read and write* the
   selection — `get_selection` / `clear_selection!` / `set_selection!` /
   `with_selection` — are the **selection layer's** (Layer 11), not this one's; see
   [selection.md](selection.md).
2. **Field names ARE the reference vocabulary.** A `FieldReferenceStep("foo")` in a
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
`is_descendable_for_sync`, `sync_element_limit`, `make_unsynced_placeholder` (declared in
`DocumentInterface.jl`, defaulted in `DocumentDefaults.jl`). The default policy
`nothing` descends everywhere and keeps every element, so an un-policed walk is
the walk described above and pays nothing for the option. This layer never names
a marker *type*, and never sees a policy that is not handed to it: it calls
whoever supplied the policy for what stands where the walk stopped.

The same three hooks bound the walk that `ProjecturedReflection`'s
`sync_reflection!` uses to grow a shadow of an arbitrary Julia value one level
at a time, instead of walking the whole value up front. See
[reflection.md](../reflection/reflection.md) for the policy and the widget view
built on that shadow.

Both use two primitives of the layers below, because the kind of a document is
in its field cells and not in its type name. `copy_cell_as`, of the cell layer,
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
handling:

```julia
has_document_duplicate(::SimulationFilter) = true
copy_document(policy::DuplicatePolicy, form::SimulationFilter) =
    copy_document_fields(policy, form; runner = Ref{Any}(filter_runner(form)))
```

**An action that a duplicate shares receives the document it acts on; it does
not capture it.** The runner's action above is called with the form whose Run
was pressed, so one function serves the original and its duplicate. An `Action`
declares no duplicate, and a button's duplicate shares it, as every control
that shows one command does.

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

## Testing pressure

Kernel tests for this layer use ONLY a test-local `@document struct ToyNode`,
never `Collection` or `Primitive`. You cannot reach for the engine documents
as fixtures. That constraint is what keeps the interface sufficient. If the
contract cannot be exercised without the concrete documents, it is not actually a
contract. See
[test/document/DocumentContractTest.jl](../../../test/kernel/document/DocumentContractTest.jl).
