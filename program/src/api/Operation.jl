"""
    OperationApiModule

Domain operations produced by the reader side of the projection pipeline
and applied by evaluate_operation in the editor. An operation carries the
intent of a user gesture expressed in the document's own terms, decoupled
from the raw device event that triggered it.
"""
module OperationApiModule

export Operation, evaluate_operation

"""
    Operation

Abstract supertype for all domain operations. Concrete operations are produced
by the reader side of the projection pipeline and applied by `evaluate_operation`.
"""
abstract type Operation end

"""
    evaluate_operation(editor, operation::Operation)

Apply `operation` against `editor`. The editor is whatever object holds the
mutable runtime state the operation needs — concretely an `EditorModule.Editor`
in production, with `editor.document` carrying the root document. Concrete
operations add methods reaching for whatever editor fields they need
(`editor.document` is the most common). The editor calls this after the reader
pipeline produces an operation.
"""
function evaluate_operation end

end # module
