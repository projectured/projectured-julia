"""
    DocumentApiModule

Document selection API. Declares clear_selection! and set_selection! as
generic functions dispatched on by concrete document types and the default
implementation in common/Operation.jl. Keeping the interface here decouples
the declaration from the implementation and avoids circular dependencies.
"""
module DocumentApiModule

export Document, clear_selection!, set_selection!

"""
    Document

Abstract base type for all document types.

Two contracts bind every concrete document:

1. **Selection field.** Every document must have a `selection::Reference` field
   (a `ReferencePath` or `nothing`, stored in a `Cell`) tracking the current
   selection state.

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

"""
    clear_selection!(document)

Clear the current selection of `document` and recursively clear the selections
of any child documents reached by the stored path.
"""
function clear_selection! end

"""
    set_selection!(document, path)

Propagate `path` down the document hierarchy starting at `document`. Each step
in the path navigates to a child document and sets that child's `selection` to
the remaining tail of the path.
"""
function set_selection! end

end # module
