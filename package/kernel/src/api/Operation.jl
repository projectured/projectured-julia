"""
    OperationApiModule

Domain operations produced by the reader side of the projection pipeline
and applied by evaluate_operation in the editor. An operation carries the
intent of a user gesture expressed in the document's own terms, decoupled
from the raw device event that triggered it.
"""
module OperationApiModule

export Operation, NoOperation, evaluate_operation

"""
    Operation

Abstract supertype for all domain operations. Concrete operations are produced
by the reader side of the projection pipeline and applied by `evaluate_operation`.
"""
abstract type Operation end

"""
    NoOperation()

An operation that does nothing when applied. Its purpose is to *consume* a
gesture without effecting a change: a reader (or a per-instance gesture binding)
returns `NoOperation()` to say "this gesture is handled — stop looking",
distinct from returning `nothing`, which means "declined, keep looking / fall
through". The canonical way for a per-instance binding to **suppress** a default
behavior (see `instance_gestures`) is to map the pattern to a `NoOperation()`.
"""
struct NoOperation <: Operation end

"""
    evaluate_operation(editor, operation::Operation)

Apply `operation` against `editor`. The editor is whatever object holds the
mutable runtime state the operation needs — concretely an `EditorModule.Editor`
in production, with `editor.document` carrying the root document. Concrete
operations add methods reaching for whatever editor fields they need
(`editor.document` is the most common). The editor calls this after the reader
pipeline produces an operation. The default methods (`::NoOperation`,
`::Nothing`, and the catch-all) live in `OperationModule`; the `splice_*`
text-edit helpers this interface used to carry now live there too — this module
declares only the abstract vocabulary.
"""
function evaluate_operation end

end # module
