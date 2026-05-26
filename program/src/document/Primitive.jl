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
import ..ReferenceModule: Reference
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
    NumberReplaceRangeOperation(document, start_index, end_index, replacement)

Replace characters in the string representation of `document`'s number value
from `start_index` (1-based, inclusive) to `end_index` (1-based, exclusive)
with `replacement`, then parse the result back into a number.
An empty result sets the value to `nothing`.
"""
struct NumberReplaceRangeOperation <: Operation
    document::PrimitiveNumber
    start_index::Int
    end_index::Int
    replacement::String
end

"""
    StringReplaceRangeOperation(document, start_index, end_index, replacement)

Replace characters in `document`'s string value from `start_index`
(1-based, inclusive) to `end_index` (1-based, exclusive) with `replacement`.
"""
struct StringReplaceRangeOperation <: Operation
    document::PrimitiveString
    start_index::Int
    end_index::Int
    replacement::String
end

# ── Operation evaluation ──────────────────────────────────────────────────────

function evaluate_operation(op::NumberReplaceRangeOperation, _document)
    doc = op.document
    old_num = doc.value
    old_str = old_num === nothing ? "" : string(old_num)
    new_str = old_str[1:op.start_index - 1] * op.replacement * old_str[op.end_index:end]
    doc.value = isempty(new_str) ? nothing : tryparse(Float64, new_str)
end

function evaluate_operation(op::StringReplaceRangeOperation, _document)
    doc = op.document
    old_str = something(doc.value, "")
    new_str = old_str[1:op.start_index - 1] * op.replacement * old_str[op.end_index:end]
    doc.value = new_str
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
