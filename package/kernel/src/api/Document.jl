"""
    DocumentApiModule

Document selection API. Declares clear_selection! and set_selection! as
generic functions dispatched on by concrete document types and the default
implementation in common/Operation.jl. Keeping the interface here decouples
the declaration from the implementation and avoids circular dependencies.
"""
module DocumentApiModule

export Document, selection, clear_selection!, set_selection!, with_selection, document_read

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
    selection(document) -> reference or nothing

The document's current selection — a `ReferencePath` or `nothing`. Every document
has one (the [`Document`](@ref) contract requires a `selection` field); the default
reads that conventional field, so a concrete document gets it for free, and one that
stores its selection differently overrides this method.
"""
selection(document::Document) = document.selection

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

"""
    with_selection(document, path) -> document

Construct-and-select: set `path` on `document` and propagate it deeply into the
child documents it traverses (via [`set_selection!`](@ref)), returning
`document`. The one-expression form of
`d = SomeDocument(...); set_selection!(d, path); d` — for building a document
literal whose cursor is fully placed (examples, fixtures, clipboard payloads, and
the gesture→replace builders).
"""
function with_selection end

"""
    document_read(document, gesture) -> Union{Operation, Nothing}

Map a backend-agnostic input gesture to an Operation expressed against
`document` itself (i.e. against `document`'s own reference vocabulary, reading
only `document`'s structure and `document.selection`). Returns `nothing` when
the document does not handle the gesture, so a projection reader can fall back
to its own geometry-dependent handling or let the gesture propagate.

This is the projection-independent half of a domain's reader: any projection
whose output (or input) is `document` can obtain navigation/editing operations
without re-implementing them, and a backend that renders the domain directly
(e.g. ConsoleBackend on a bare TextText) gets them for free.

The catch-all `document_read(::Document, gesture)` is supplied by
`GestureBindingModule` (`common/GestureBinding.jl`): it interprets the reified
`document_gestures` table for the document's type, so a domain authored with
`@gestures` needs no hand-written reader. Concrete `document_read(::SomeDoc, …)`
methods (Text, Syntax) are more specific and still take precedence; a document
type with neither a method nor any registered gestures yields `nothing`.
"""
function document_read end

end # module
