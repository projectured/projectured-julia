# Fragment of `DocumentModule` — the document contract shared by every concrete
# document type: the `Document` abstract supertype, the selection generics
# (get/clear/set/with), and the domain-facing `read_gesture` seam. Declaring the
# generics here (as `function foo end`) decouples the declarations from the
# implementations, which land in `Document.jl` for the shared machinery, in
# `common/Operation.jl` for the default clear/set (folded in by P4), and in each
# concrete document type. Included by `DocumentModule.jl`; shares its namespace.

"""
    Document

Abstract base type for all document types.

Two contracts bind every concrete document:

1. **Selection field.** Every document must carry a `selection` field holding a
   `Reference` (a `ReferencePath` or `nothing`) that tracks the current selection.
   The field is stored in a `Cell`; `document.selection` reads through it (the
   `@document`-generated `getproperty` unwraps the Cell), so [`selection`](@ref)
   returns the path/`nothing`, not the Cell itself.

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
    get_selection(document) -> reference or nothing

The document's current selection — a `ReferencePath` or `nothing`. Every document
has one (the [`Document`](@ref) contract requires a `selection` field); the default
reads that conventional field, so a concrete document gets it for free, and one that
stores its selection differently overrides this method.
"""
get_selection(document::Document) = document.selection

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
    read_gesture(document, gesture) -> Union{Operation, Nothing}

Map a backend-agnostic input gesture to an Operation expressed against
`document` itself (i.e. against `document`'s own reference vocabulary, reading
only `document`'s structure and `document.selection`). Returns `nothing` when
the document does not handle the gesture, so a projection reader can fall back
to its own geometry-dependent handling or let the gesture propagate.

This is the projection-independent half of a domain's reader: any projection
whose output (or input) is `document` can obtain navigation/editing operations
without re-implementing them, and a backend that renders the domain directly
(without a projection pipeline) gets them for free.

The catch-all `read_gesture(::Document, gesture)` is supplied by
`GestureBindingModule` (`common/GestureBinding.jl`): it interprets the reified
`get_document_gesture_bindings` table for the document's type, so a domain authored with
`@gestures` needs no hand-written reader. A concrete `read_gesture(::SomeDoc, …)`
method is more specific and still takes precedence; a document type with neither a
method nor any registered gestures yields `nothing`.
"""
function read_gesture end
