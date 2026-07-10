# Fragment of `DocumentModule` — the `Document` abstract supertype and the
# minimal contract every concrete document must satisfy. The `@document` codegen
# and shared value protocol land in the sibling `Document.jl` fragment.
# See [`documentation/concepts.md`](../../../../documentation/concepts.md)
# for the single-place narrative of the document editing model — the wider
# cluster of Reference, Operation, gesture, and projection that this contract
# is only one piece of.

"""
    Document

Abstract base type for all document types.

Two contracts bind every concrete document:

1. **Selection field.** Every document must carry a `selection` field holding a
   reference (a path or `nothing`) that tracks the current selection. The field
   is stored in a `Cell`; `document.selection` reads through it (the
   `@document`-generated `getproperty` unwraps the Cell), so the returned value
   is the path/`nothing`, not the Cell itself. The generics that read, clear,
   set, and canonicalize this field live at the reference layer, since their
   payload is a reference path.

2. **Field names ARE the reference vocabulary.** A `FieldReference("foo")` in a
   selection/reference path is resolved by `getfield(document, :foo)` — so a
   document's *struct field names are public API*. A path like
   `entries[1].value.value{3}` only navigates because `entries` and `value` are
   literally field names on the documents it passes through. Renaming a field
   silently breaks every stored reference, every hand-built `@reference`, and
   every projection that maps onto that field. Choose field names deliberately
   and treat them as a stable interface, not an implementation detail.
"""
abstract type Document end
