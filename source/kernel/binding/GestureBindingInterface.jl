# Fragment of `GestureBindingModule` — the gesture-reading **contract**: the
# one open generic a document type answers to turn an input event into an
# operation. The table interpreter that serves `@gestures`-declared documents
# is the fallback, in `GestureBinding.jl`.

"""
    read_gesture(document, gesture; claimed = nothing) -> Union{Operation, Nothing}

Map a backend-agnostic input gesture to an `Operation` expressed against `document`
itself (i.e. against `document`'s own reference vocabulary, reading only
`document`'s structure and `document.selection`). Returns `nothing` when the document
does not handle the gesture, so a caller can fall back to its own geometry-dependent
handling or let the gesture propagate.

This is the projection-independent half of a domain's reader: any consumer whose
input (or output) is `document` can obtain navigation/editing operations without
re-implementing them, and a backend that renders the domain directly (without a
projection pipeline) gets them for free.

The catch-all `read_gesture(::Document, gesture)` below reads the reified
[`get_document_gesture_bindings`](@ref) table for the document's type — so a domain
authored with [`@gestures`](@ref) needs no hand-written reader. A concrete
`read_gesture(::SomeDocument, …)` method is more specific and still takes precedence;
a document type with neither a method nor any registered gestures yields `nothing`.
"""
function read_gesture end
