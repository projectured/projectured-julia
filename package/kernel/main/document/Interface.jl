# Fragment of `DocumentModule` — the `Document` abstract supertype and the
# minimal contract every concrete document must satisfy. The `@document` codegen
# and value protocol land in the sibling `Document.jl` fragment; the
# selection-path generics (`get_selection` / `clear_selection!` / `set_selection!`
# / `with_selection`) reference `Reference`, so they live at the reference layer
# (`reference/ReferenceModule.jl`, AR-47); the domain-facing `read_gesture`
# seam references `gesture` and `Operation`, so it lives at the device layer
# (`device/GestureModule.jl`). Consumers importing the whole document editing
# model reach for each seam from its home layer; the umbrella re-exports them
# flat. See [`documentation/concepts.md`](../../../../documentation/concepts.md)
# for the single-place narrative of that model.

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
