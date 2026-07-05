# Fragment of `OperationModule` — the operation contract: the `Operation`
# abstract supertype, the `evaluate_operation` generic, and
# `invalidate_projection!` (a duck-typed seam the editor loop overrides).
# The concrete operations, splice helpers, and the R1 `child_reference_steps`
# traversal seam live in `Operations.jl`; the R2 open `reroot_operation`
# generic lives in `Rerooting.jl`.

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
after the reader pipeline produces an operation. This module declares only the
abstract vocabulary (`Operation` and this generic); the concrete operations and
the default `::Nothing`/catch-all methods live in `OperationModule`
(`common/Operation.jl`).
"""
function evaluate_operation end

"""
    invalidate_projection!(editor)

Ask `editor` to drop any cached projection/IoMap so the next print rebuilds from
scratch. An operation that changes the document in a way the reactive pipeline
cannot propagate incrementally (e.g. a whole-root swap) calls this. The default is
a **no-op**, so a caller that keeps no cache — or a non-editor `editor` argument —
is unaffected; the editor loop adds the method that actually clears its cache. The
generic lives here so `evaluate_operation` methods can call it without depending on
the concrete editor type.
"""
invalidate_projection!(editor) = nothing
