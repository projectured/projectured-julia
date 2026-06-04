"""
    OperationApiModule

Domain operations produced by the reader side of the projection pipeline
and applied by evaluate_operation in the editor. An operation carries the
intent of a user gesture expressed in the document's own terms, decoupled
from the raw device event that triggered it.
"""
module OperationApiModule

export Operation, evaluate_operation, _apply_string_replace!, _apply_number_replace!

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

"""
    _apply_string_replace!(target, field_name, s, e, replacement)

Apply a string-replace edit to `target.<field_name>` between 0-based boundaries
`[s, e]`. Each domain module adds methods for the document types whose `value`
field (or analogous text-bearing field) is a string. The default method errors
so missing methods are easy to diagnose.
"""
function _apply_string_replace!(target, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    error("No _apply_string_replace! method for target $(typeof(target)).$(field_name)")
end

"""
    _apply_number_replace!(target, field_name, s, e, replacement)

Apply a number-replace edit to `target.<field_name>`. The target's stringified
value is updated between 0-based boundaries `[s, e]`, then parsed back to a
number (or `nothing` on parse failure / empty result).
"""
function _apply_number_replace!(target, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    error("No _apply_number_replace! method for target $(typeof(target)).$(field_name)")
end

end # module
