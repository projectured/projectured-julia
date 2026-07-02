"""
    PrimitiveModule

The primitive domain. Editable, domain-independent wrappers for boolean,
number, and string scalar values with selection and identity. Each value
is stored in a reactive Cell so changes are tracked.
"""
module PrimitiveModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..DocumentApiModule: clear_selection!, set_selection!
import ..OperationApiModule: Operation, evaluate_operation
import ..OperationModule: splice_string, splice_value!, splice_number
import ..ReferenceModule: Reference, ReferencePath, ConcreteReferencePath, EmptyReferencePath,
                          ReferenceStep, FieldReference, RangeReference, evaluate_reference,
                          strip_reference_types
export PrimitiveDocument, PrimitiveInsertion, PrimitiveBool, PrimitiveNumber, PrimitiveString,
       NumberReplaceRangeOperation, StringReplaceRangeOperation,
       evaluate_operation,
       IPrimitiveInsertion, IPrimitiveBool, IPrimitiveNumber, IPrimitiveString

# ── Abstract base ─────────────────────────────────────────────────────────────

abstract type PrimitiveDocument <: Document end

# ── PrimitiveInsertion ──────────────────────────────────────────────────────

"""
    PrimitiveInsertion(; value=nothing, selection=nothing)

An empty primitive-domain slot — a "hole" awaiting a value, the primitive
counterpart of a domain's insertion placeholder. `value` holds whatever pending
content has been typed into it (or `nothing` while still empty); editing it is how
a concrete primitive value comes to replace the insertion.
"""
@document struct PrimitiveInsertion <: PrimitiveDocument
    value::Any = nothing
    selection::Reference = nothing
end

# ── PrimitiveBool ─────────────────────────────────────────────────────────────

"""
    PrimitiveBool(value; selection=nothing)

A primitive domain-independent boolean document with selection and identity.
`value` is a `Cell` holding a `Bool`.
"""
@document struct PrimitiveBool <: PrimitiveDocument
    value::Bool
    selection::Reference
end

PrimitiveBool(value::Bool; selection=nothing) =
    PrimitiveBool(Cell(value), Cell(selection))

# ── PrimitiveNumber ───────────────────────────────────────────────────────────

"""
    PrimitiveNumber(value; selection=nothing)

A primitive domain-independent number document with selection and identity.
`value` is a `Cell` holding a `Number` or `nothing`.
"""
@document struct PrimitiveNumber <: PrimitiveDocument
    value::Union{Number, Nothing}
    selection::Reference
end

PrimitiveNumber(value; selection=nothing) =
    PrimitiveNumber(Cell(value), Cell(selection))

# ── PrimitiveString ───────────────────────────────────────────────────────────

"""
    PrimitiveString(value; selection=nothing)

A primitive domain-independent string document with selection and identity.
`value` is a `Cell` holding a `String` or `nothing`.
"""
@document struct PrimitiveString <: PrimitiveDocument
    value::Union{String, Nothing}
    selection::Reference
end

PrimitiveString(value; selection=nothing) =
    PrimitiveString(Cell(value), Cell(selection))

# ── Operations ────────────────────────────────────────────────────────────────

"""
    NumberReplaceRangeOperation(reference, replacement)

Replace characters in the string representation of a `PrimitiveNumber`'s value.
`reference` is a `ReferencePath` rooted at the editor's document whose terminal
step is a `RangeReference(s, e)` (0-based boundaries) and whose penultimate
step is `FieldReference("value")`. The path up to those two steps locates the
target `PrimitiveNumber`. After evaluation the target's `selection` is updated
to a zero-width cursor at `s + length(replacement)`.

An empty result sets the value to `nothing`.
"""
struct NumberReplaceRangeOperation <: Operation
    reference::ReferencePath
    replacement::String
end

"""
    StringReplaceRangeOperation(reference, replacement)

Replace characters in a `PrimitiveString`'s value. `reference` is a
`ReferencePath` rooted at the editor's document whose terminal step is a
`RangeReference(s, e)` (0-based boundaries) and whose penultimate step is
`FieldReference("value")`. The path up to those two steps locates the target
`PrimitiveString`. After evaluation the target's `selection` is updated to a
zero-width cursor at `s + length(replacement)`.

Inter-string boundary behaviour: when the cursor sits exactly on the boundary
between two adjacent `PrimitiveString` spans, the behaviour is undefined.
"""
struct StringReplaceRangeOperation <: Operation
    reference::ReferencePath
    replacement::String
end

# ── Operation evaluation ──────────────────────────────────────────────────────

# Split `op.reference` into (target_path, field_name, range_step). The
# penultimate step is the field-name carrying the text/number value; the
# terminal step is the RangeReference. The field name is data, not a
# precondition — `splice_value!` interprets the field's current value by its
# representation (string / number / span / span-sequence).
function _split_replace_reference(path::ReferencePath)
    # Operate on the plain navigation path: drop selection-style type checkpoints
    # so the `.<field>[range]` suffix split sees only real steps.
    path = strip_reference_types(path)
    steps = ReferenceStep[]
    cur = path
    while cur isa ConcreteReferencePath
        push!(steps, cur.head)
        cur = cur.tail
    end
    # An un-splittable reference has no editable `.<field>[range]` slot — e.g. an
    # edit aimed at a projection-introduced span (a placeholder/insertion rendered
    # as `…[i].proj(p, .value[k])`, whose terminal is a `ProjectionReference` with
    # no input pre-image). Return `nothing` so the caller no-ops instead of
    # crashing the editor.
    length(steps) >= 2 || return nothing
    field_step = steps[end - 1]
    range_step = steps[end]
    field_step isa FieldReference || return nothing
    range_step isa RangeReference || return nothing
    target_path = EmptyReferencePath()
    for i in (length(steps) - 2):-1:1
        target_path = ConcreteReferencePath(steps[i], target_path)
    end
    (target_path, field_step.name::AbstractString, range_step)
end

# Replace the terminal RangeReference of `path` with a zero-width
# RangeReference at `start + length(replacement)`, leaving the rest intact.
function _replace_terminal_with_cursor(path::ReferencePath, replacement::AbstractString)
    # Plain navigation path only; the rebuilt path is re-canonicalized when it is
    # handed to `set_selection!`.
    path = strip_reference_types(path)
    steps = ReferenceStep[]
    cur = path
    while cur isa ConcreteReferencePath
        push!(steps, cur.head)
        cur = cur.tail
    end
    range_step = steps[end]::RangeReference
    new_pos = range_step.start + length(replacement)
    steps[end] = RangeReference(new_pos, new_pos)
    result = EmptyReferencePath()
    for i in length(steps):-1:1
        result = ConcreteReferencePath(steps[i], result)
    end
    result
end

# A number edit always has number semantics regardless of the field's current
# value (an empty/cleared field reparses from ""), so it does not go through the
# representation-dispatched `splice_value!` — it forces the number path here.
function evaluate_operation(editor, op::NumberReplaceRangeOperation)
    document = editor.document
    split = _split_replace_reference(op.reference)
    split === nothing && return            # no editable slot (e.g. projection-introduced span)
    target_path, field_name, range_step = split
    target = evaluate_reference(document, target_path)
    field = Symbol(field_name)
    old = getproperty(target, field)
    setproperty!(target, field,
                 splice_number(old === nothing ? "" : string(old),
                               range_step.start, range_step.stop, op.replacement))
    _replace_selection_with_cursor!(document, op)
end

function evaluate_operation(editor, op::StringReplaceRangeOperation)
    document = editor.document
    split = _split_replace_reference(op.reference)
    split === nothing && return            # no editable slot (e.g. projection-introduced span)
    target_path, field_name, range_step = split
    target = evaluate_reference(document, target_path)
    field = Symbol(field_name)
    splice_value!(target, field, getproperty(target, field),
                  range_step.start, range_step.stop, op.replacement)
    _replace_selection_with_cursor!(document, op)
end

# Propagate a zero-width cursor selection at the post-edit position down
# the full path so every node along the way (root, intermediates, target)
# holds the suffix relevant to its subtree.
function _replace_selection_with_cursor!(document, op)
    new_path = _replace_terminal_with_cursor(op.reference, op.replacement)
    clear_selection!(document)
    set_selection!(document, new_path)
end

# Text/number edits to PrimitiveString / PrimitiveNumber are handled generically
# by `splice_value!` (string / number representations) — no per-type method
# needed; the value field is a plain `String`/`Number`.

# ── Sequence interface for PrimitiveString ────────────────────────────────────

Base.length(s::PrimitiveString) = length(something(s.value, ""))

Base.getindex(s::PrimitiveString, i::Integer) = something(s.value, "")[i]

function Base.getindex(s::PrimitiveString, r::UnitRange{Int})
    PrimitiveString(something(s.value, "")[r])
end

Base.iterate(s::PrimitiveString, state...) = iterate(something(s.value, ""), state...)

Base.isempty(s::PrimitiveString) = isempty(something(s.value, ""))

Base.firstindex(::PrimitiveString) = 1
Base.lastindex(s::PrimitiveString) = lastindex(something(s.value, ""))

function Base.setindex!(s::PrimitiveString, ch::AbstractChar, i::Integer)
    str = something(s.value, "")
    s.value = str[1:i-1] * string(ch) * str[i+1:end]
    return ch
end

end # module
