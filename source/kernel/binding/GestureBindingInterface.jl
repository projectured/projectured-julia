# Fragment of `GestureBindingModule` — the gesture-reading **contract**: the
# open generic a document type answers to turn an input event into an
# operation, and the two tables that other packages add bindings to. The
# defaults and the table interpreter that serves `@gestures`-declared documents
# are in `GestureBinding.jl`.

"""
    read_gesture(document, gesture; claimed = nothing) -> Union{Operation, Nothing}

Map a backend-agnostic input gesture to an `Operation` expressed against `document`
itself (i.e. against `document`'s own reference vocabulary, reading only
`document`'s structure and `document.selection`). Returns `nothing` when the document
does not handle the gesture, so a caller can fall back to its own geometry-dependent
handling or let the gesture propagate.

This is the projection-independent half of a domain's reader: any caller whose
input (or output) is `document` can obtain navigation/editing operations without
re-implementing them, and a backend that renders the domain directly (without a
projection pipeline) gets them with no reader of its own.

The catch-all `read_gesture(::Document, gesture)` in `GestureBinding.jl` reads the
reified [`get_document_gesture_bindings`](@ref) table for the document's type — so a
domain authored with [`@gestures`](@ref) needs no hand-written reader. A concrete
`read_gesture(::SomeDocument, …)` method is more specific and still takes precedence;
a document type with neither a method nor any registered gestures yields `nothing`.
"""
function read_gesture end

"""
    get_document_gesture_bindings_own(::Type{T}) -> Vector{GestureBinding}

The bindings declared *directly* on type `T` by `@gestures T …` (default empty). Use
[`get_document_gesture_bindings`](@ref) to also collect inherited supertype bindings.
"""
function get_document_gesture_bindings_own end

"""
    get_instance_gesture_bindings(document) -> Vector{GestureBinding}

Per-*instance* gesture bindings carried by `document` itself, checked ahead of the
per-type table so an instance can add, override (by shadowing a same-pattern
default), or suppress behavior. Default empty, so any object that does not opt in
behaves as if it had none. Because the default is empty and untyped it also serves
values that are not `Document`s — pass such a target's selection to
[`read_bound_gesture`](@ref) explicitly.
"""
function get_instance_gesture_bindings end
