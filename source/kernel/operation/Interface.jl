# Fragment of `OperationModule` — the operation **contract**: the `Operation`
# abstract supertype and the `evaluate_operation` / `invalidate_projection!`
# generics. The concrete operations and both seams that implement and extend this
# contract live in `Operations.jl` and `Rerooting.jl`.

"""
    Operation

One change of a document, as a value: what is changed, where, and to what.

Use it as the type of anything a person's act means for a document. A reader
answers one of these instead of changing the document itself, so the change can
be inspected, refused, logged, undone, or sent somewhere else before it happens.

# Example

    struct ShrinkBoxOperation <: Operation
        box::Any
    end
    evaluate_operation(editor, o::ShrinkBoxOperation) = (o.box.width[] -= 1)

See also `evaluate_operation`, which applies one, and `read_intent`, which
answers one.
"""
abstract type Operation end

"""
    evaluate_operation(editor, operation::Operation)

Carry out a change: the one place where a document is written.

Use it to apply what a reader answered. Every concrete operation adds a method
of its own, which reaches for what it needs on the editor, most often the
document it holds. Nothing else writes a document, so what happened to one is
what was evaluated on it.

# Example

    change = read_intent(projection, iomap, event)
    change === nothing || evaluate_operation(editor, change)

See also `Operation`, `read_intent`, and `invalidate_projection!`.

Apply `operation` against `editor`. The `editor` is whatever object holds the
mutable runtime state the operation needs, with `editor.document` carrying the
root document. Concrete operations add methods reaching for whatever editor
fields they need (`editor.document` is the most common). The caller invokes this
after the reader pipeline produces an operation.
"""
function evaluate_operation end

"""
    invalidate_projection!(editor)

Ask `editor` to drop any cached projection/IoMap so the next print rebuilds from
scratch. An operation that changes the document in a way the reactive pipeline
cannot propagate incrementally (e.g. a whole-root swap) calls this. Answering is
optional — a caller that keeps no cache does nothing — so an `evaluate_operation`
method can call it without knowing the concrete type of the object it is handed.
"""
function invalidate_projection! end
