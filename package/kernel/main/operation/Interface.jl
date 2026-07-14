# Fragment of `OperationModule` — the operation **contract**: the `Operation`
# abstract supertype, the `evaluate_operation` generic, and
# `invalidate_projection!` (a duck-typed seam whose caller overrides it).
# The concrete operations, the splice helpers, the `child_reference_steps`
# traversal seam, and both generics' catch-all methods live in `Operations.jl`;
# the open `reroot_operation` generic lives in `Rerooting.jl`.

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
