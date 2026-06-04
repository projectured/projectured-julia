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
import ..OperationApiModule: Operation, evaluate_operation,
                              _apply_string_replace!, _apply_number_replace!
import ..ReferenceModule: Reference, ReferencePath, ConcreteReferencePath, EmptyReferencePath,
                          ReferenceStep, FieldReference, RangeReference, evaluate_reference
export PrimitiveDocument, PrimitiveInsertion, PrimitiveForeign, PrimitiveBool, PrimitiveNumber, PrimitiveString,
       NumberReplaceRangeOperation, StringReplaceRangeOperation,
       evaluate_operation,
       IPrimitiveInsertion, IPrimitiveForeign, IPrimitiveBool, IPrimitiveNumber, IPrimitiveString

# ── Abstract base ─────────────────────────────────────────────────────────────

abstract type PrimitiveDocument <: Document end

# ── PrimitiveInsertion / PrimitiveForeign ───────────────────────────────────

@document struct PrimitiveInsertion <: PrimitiveDocument
    value::Any
    selection::Reference
end
PrimitiveInsertion() = PrimitiveInsertion(Cell(nothing), Cell(nothing))

@document struct PrimitiveForeign <: PrimitiveDocument
    value::Any
    selection::Reference
end
PrimitiveForeign(value) = PrimitiveForeign(Cell(value), Cell(nothing))

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
    value::Number
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
    value::String
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

Inter-string boundary behaviour: when the cursor sits exactly on the boundary
between two adjacent `PrimitiveString` spans, the behaviour is undefined.
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
# precondition — each domain interprets it via its own `_apply_*_replace!`
# method.
function _split_replace_reference(path::ReferencePath)
    steps = ReferenceStep[]
    cur = path
    while cur isa ConcreteReferencePath
        push!(steps, cur.head)
        cur = cur.tail
    end
    length(steps) >= 2 ||
        error("replace-range reference must have at least .<field>[range] suffix, got: $path")
    field_step = steps[end - 1]
    range_step = steps[end]
    field_step isa FieldReference ||
        error("replace-range reference penultimate step must be a FieldReference, got: $field_step")
    range_step isa RangeReference ||
        error("replace-range reference terminal step must be a RangeReference, got: $range_step")
    target_path = EmptyReferencePath()
    for i in (length(steps) - 2):-1:1
        target_path = ConcreteReferencePath(steps[i], target_path)
    end
    (target_path, field_step.name::AbstractString, range_step)
end

# Replace the terminal RangeReference of `path` with a zero-width
# RangeReference at `start + length(replacement)`, leaving the rest intact.
function _replace_terminal_with_cursor(path::ReferencePath, replacement::AbstractString)
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

function evaluate_operation(editor, op::NumberReplaceRangeOperation)
    document = editor.document
    target_path, field_name, range_step = _split_replace_reference(op.reference)
    target = evaluate_reference(document, target_path)
    _apply_number_replace!(target, field_name, range_step.start, range_step.stop, op.replacement)
    _replace_selection_with_cursor!(document, op)
end

function evaluate_operation(editor, op::StringReplaceRangeOperation)
    document = editor.document
    target_path, field_name, range_step = _split_replace_reference(op.reference)
    target = evaluate_reference(document, target_path)
    _apply_string_replace!(target, field_name, range_step.start, range_step.stop, op.replacement)
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

# Apply the replacement to `old_str` between 0-based boundaries [s, e].
function _apply_range_replace(old_str::AbstractString, s::Int, e::Int, replacement::AbstractString)
    old_str[1:s] * replacement * old_str[e + 1:end]
end

# ── Primitive domain implementations ─────────────────────────────────────────

function _apply_string_replace!(target::PrimitiveString, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    field_name == "value" || error("PrimitiveString supports only field 'value', got: $field_name")
    old_str = something(target.value, "")
    target.value = _apply_range_replace(old_str, s, e, replacement)
end

function _apply_number_replace!(target::PrimitiveNumber, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    field_name == "value" || error("PrimitiveNumber supports only field 'value', got: $field_name")
    old_num = target.value
    old_str = old_num === nothing ? "" : string(old_num)
    new_str = _apply_range_replace(old_str, s, e, replacement)
    target.value = isempty(new_str) ? nothing : tryparse(Float64, new_str)
end

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

# ── Display ───────────────────────────────────────────────────────────────────

function Base.show(io::IO, b::PrimitiveBool)
    print(io, "PrimitiveBool(", b.value, ")")
end

function Base.show(io::IO, n::PrimitiveNumber)
    v = n.value
    v === nothing ? print(io, "PrimitiveNumber(nothing)") : print(io, "PrimitiveNumber(", v, ")")
end

function Base.show(io::IO, s::PrimitiveString)
    v = s.value
    v === nothing ? print(io, "PrimitiveString(nothing)") : print(io, "PrimitiveString(", repr(v), ")")
end

end # module
