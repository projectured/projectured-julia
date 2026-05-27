"""
    PrimitiveModule

The primitive domain. Editable, domain-independent wrappers for boolean,
number, and string scalar values with selection and identity. Each value
is stored in a reactive Cell so changes are tracked.
"""
module PrimitiveModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..OperationApiModule: Operation, evaluate_operation
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

# Split `op.reference` into (parent_path, range_step) and verify the
# penultimate step is FieldReference("value") and the terminal step is a
# RangeReference. Throws if the shape is wrong.
function _split_replace_reference(path::ReferencePath)
    steps = ReferenceStep[]
    cur = path
    while cur isa ConcreteReferencePath
        push!(steps, cur.head)
        cur = cur.tail
    end
    length(steps) >= 2 ||
        error("replace-range reference must have at least .value[range] suffix, got: $path")
    value_step = steps[end - 1]
    range_step = steps[end]
    (value_step isa FieldReference && value_step.name == "value") ||
        error("replace-range reference penultimate step must be FieldReference(\"value\"), got: $value_step")
    range_step isa RangeReference ||
        error("replace-range reference terminal step must be a RangeReference, got: $range_step")
    parent_path = EmptyReferencePath()
    for i in (length(steps) - 2):-1:1
        parent_path = ConcreteReferencePath(steps[i], parent_path)
    end
    (parent_path, range_step)
end

# Apply the replacement to `old_str` between 0-based boundaries [s, e].
function _apply_range_replace(old_str::AbstractString, s::Int, e::Int, replacement::AbstractString)
    old_str[1:s] * replacement * old_str[e + 1:end]
end

function _new_cursor_selection(start::Int, replacement::AbstractString)
    new_pos = start + length(replacement)
    ConcreteReferencePath(FieldReference("value"),
        ConcreteReferencePath(RangeReference(new_pos, new_pos), EmptyReferencePath()))
end

function evaluate_operation(op::NumberReplaceRangeOperation, document)
    parent_path, range_step = _split_replace_reference(op.reference)
    target = evaluate_reference(document, parent_path)::PrimitiveNumber
    old_num = target.value
    old_str = old_num === nothing ? "" : string(old_num)
    new_str = _apply_range_replace(old_str, range_step.start, range_step.stop, op.replacement)
    target.value = isempty(new_str) ? nothing : tryparse(Float64, new_str)
    target.selection = _new_cursor_selection(range_step.start, op.replacement)
end

function evaluate_operation(op::StringReplaceRangeOperation, document)
    parent_path, range_step = _split_replace_reference(op.reference)
    target = evaluate_reference(document, parent_path)::PrimitiveString
    old_str = something(target.value, "")
    target.value = _apply_range_replace(old_str, range_step.start, range_step.stop, op.replacement)
    target.selection = _new_cursor_selection(range_step.start, op.replacement)
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
