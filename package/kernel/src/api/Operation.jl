"""
    OperationApiModule

Domain operations produced by the reader side of the projection pipeline
and applied by evaluate_operation in the editor. An operation carries the
intent of a user gesture expressed in the document's own terms, decoupled
from the raw device event that triggered it.
"""
module OperationApiModule

export Operation, NoOperation, evaluate_operation, splice_string, splice_value!, splice_number

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

evaluate_operation(editor, ::NoOperation) = nothing

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
    splice_string(old, s, e, replacement) -> String

Replace the characters of `old` between 0-based boundaries `[s, e]` with
`replacement`. Character-aware, so multi-byte characters survive intact.
Boundaries are clamped: `s <= 0` keeps nothing on the left, `e >= length(old)`
keeps nothing on the right. This is the one canonical text splice — every
text-replace edit in every domain routes through it.
"""
function splice_string(old::AbstractString, s::Int, e::Int, replacement::AbstractString)
    n = length(old)
    left  = s <= 0 ? "" : first(old, s)
    right = e >= n ? "" : last(old, n - e)
    String(left) * replacement * String(right)
end

"""
    splice_number(old_str, s, e, replacement) -> Union{Float64, Nothing}

Splice the textual form of a number between 0-based boundaries `[s, e]`, then
parse the result back to a `Float64`. Returns `nothing` for an empty result or
unparseable input (the value cell tolerates `nothing` as the empty sentinel).
"""
function splice_number(old_str::AbstractString, s::Int, e::Int, replacement::AbstractString)
    new_str = splice_string(old_str, s, e, replacement)
    isempty(new_str) ? nothing : tryparse(Float64, new_str)
end

"""
    splice_value!(owner, field, value, s, e, replacement)

Apply a text-replace edit to `owner.<field>` between 0-based boundaries `[s, e]`.
Dispatch is on the *representation* of the current `value` (read from the field
by the caller), not on the document type — so a single small set of methods
covers every domain:

- `AbstractString` — write the spliced string back through the field.
- `Nothing`        — a cleared text field; splice against the empty string.
- `Number`         — splice the textual form and reparse (editing a number's text
                     means "reparse it"; see [`splice_number`](@ref)).
- `TextString`     — the field holds a styled span; splice its `.content` in place.
- `TextText`       — the field holds a flat span sequence; locate the span the
                     range falls inside and splice it.

The last two methods live in `TextModule` (which owns those types). A later
unification of all replace-part operations around a reference will add a
sequence/`CellVector` method here for structural element edits.
"""
function splice_value! end

splice_value!(owner, field::Symbol, value::AbstractString, s::Int, e::Int, replacement::AbstractString) =
    setproperty!(owner, field, splice_string(value, s, e, replacement))

splice_value!(owner, field::Symbol, ::Nothing, s::Int, e::Int, replacement::AbstractString) =
    setproperty!(owner, field, splice_string("", s, e, replacement))

splice_value!(owner, field::Symbol, value::Number, s::Int, e::Int, replacement::AbstractString) =
    setproperty!(owner, field, splice_number(string(value), s, e, replacement))

end # module
