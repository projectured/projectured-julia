# Fragment of `OperationModule` — the operation **contract**: the `Operation`
# abstract supertype, the `WrappingOperation` supertype an operation that holds
# another implements, and the `evaluate_operation` / `invalidate_projection!`
# generics. The concrete operations and the seams that implement and extend this
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
    WrappingOperation

An operation that holds one other operation and does something around it.

Use it as the supertype when a change is another change plus an effect: a record
of the way back, a transaction, a trace. A subtype answers
`get_wrapped_operation` and `rewrap_operation`, and every seam that maps a
`CompoundOperation` member by member then maps the operation inside it too, so
the inner reference reaches the editor in the frame it must be applied in.

# Example

    struct TraceOperation <: WrappingOperation
        operation::Any
    end
    get_wrapped_operation(o::TraceOperation) = o.operation
    rewrap_operation(::TraceOperation, inner) = TraceOperation(inner)

See also `CompoundOperation`, which holds many operations rather than one, and
`reroot_operation`, the seam this supertype serves.
"""
abstract type WrappingOperation <: Operation end

"""
    get_wrapped_operation(operation::WrappingOperation)

The operation that `operation` holds.

See also `WrappingOperation` and `rewrap_operation`.
"""
function get_wrapped_operation end

"""
    rewrap_operation(operation::WrappingOperation, inner)

`operation` with `inner` in place of the operation it holds.

Use it to rebuild a wrapper once its inner operation is mapped or rerooted. It
is the inverse of `get_wrapped_operation`, so declare the two methods together
or declare neither.

See also `WrappingOperation` and `reroot_operation`.
"""
function rewrap_operation end

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
