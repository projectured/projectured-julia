# Fragment of `OperationModule` — the operation **contract**: the `Operation`
# abstract supertype and the `evaluate_operation` / `invalidate_projection!`
# generics. The concrete operations and both seams that implement and extend this
# contract live in `Operations.jl` and `Rerooting.jl`.

"""
    Operation

Abstract supertype for all domain operations. Concrete operations are produced
by the reader side of the projection pipeline and applied by `evaluate_operation`.
"""
abstract type Operation end

"""
    evaluate_operation(editor, operation::Operation)

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
