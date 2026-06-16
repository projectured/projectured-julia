"""
    JuliaModule

The Julia document domain provides reactive representations of Julia language constructs.
Every Julia node is a Document with all mutable fields wrapped in reactive Cells,
enabling automatic dependency tracking and incremental updates.

The domain includes:
- **Leaf types**: `JuliaIdentifier`, `JuliaInteger`, `JuliaFloat`, `JuliaString`, `JuliaBool`,
  `JuliaNothing`, `JuliaSymbol`, `JuliaChar`, `JuliaBreak`, `JuliaContinue`
- **Expression types**: `JuliaBinaryOp`, `JuliaUnaryOp`, `JuliaCall`, `JuliaTernary`,
  `JuliaIndex`, `JuliaFieldAccess`, `JuliaTuple`, `JuliaArray`, `JuliaRange`,
  `JuliaTypeAnnotation`
- **Statement types**: `JuliaAssignment`, `JuliaFor`, `JuliaForIterator`, `JuliaWhile`,
  `JuliaReturn`, `JuliaTry`, `JuliaBegin`, `JuliaIf`, `JuliaFunction`, `JuliaBlock`

Example: the factorial function is represented as:
```
JuliaFunction(
  JuliaIdentifier("factorial"),
  [JuliaIdentifier("n")],
  JuliaBlock([
    JuliaIf(
      JuliaBinaryOp(:(==), JuliaIdentifier("n"), JuliaInteger(0)),
      JuliaBlock([JuliaInteger(1)]),
      JuliaBlock([JuliaBinaryOp(:*, JuliaIdentifier("n"),
        JuliaCall(JuliaIdentifier("factorial"), [
          JuliaBinaryOp(:-, JuliaIdentifier("n"), JuliaInteger(1))]))]))]))
```
"""
module JuliaModule

import ..ReactiveModule: Cell
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
import ..OperationApiModule: _apply_string_replace!
export JuliaDocument, JuliaInsertion,
       JuliaIdentifier, JuliaInteger, JuliaFloat, JuliaString, JuliaBool,
       JuliaNothing, JuliaSymbol, JuliaChar,
       JuliaBinaryOp, JuliaUnaryOp, JuliaCall, JuliaTernary,
       JuliaIndex, JuliaFieldAccess, JuliaTuple, JuliaArray, JuliaRange,
       JuliaTypeAnnotation,
       JuliaAssignment, JuliaFor, JuliaForIterator, JuliaWhile,
       JuliaReturn, JuliaBreak, JuliaContinue, JuliaTry, JuliaBegin,
       JuliaIf, JuliaFunction, JuliaBlock,
       _julia_operator_string,
       IJuliaInsertion,
       IJuliaIdentifier, IJuliaInteger, IJuliaFloat, IJuliaString, IJuliaBool,
       IJuliaNothing, IJuliaSymbol, IJuliaChar,
       IJuliaBinaryOp, IJuliaUnaryOp, IJuliaCall, IJuliaTernary,
       IJuliaIndex, IJuliaFieldAccess, IJuliaTuple, IJuliaArray, IJuliaRange,
       IJuliaTypeAnnotation,
       IJuliaAssignment, IJuliaFor, IJuliaForIterator, IJuliaWhile,
       IJuliaReturn, IJuliaBreak, IJuliaContinue, IJuliaTry, IJuliaBegin,
       IJuliaIf, IJuliaFunction, IJuliaBlock

# ── Abstract base ─────────────────────────────────────────────────────────────

abstract type JuliaDocument <: Document end

# ── Insertion (editable Julia source being entered) ────────────────────────────

"""
    JuliaInsertion(value="")

A placeholder holding Julia source text being typed; committed (e.g. on Enter)
by parsing `value` with `juliaparse` into a real `JuliaDocument`.
"""
@document struct JuliaInsertion <: JuliaDocument
    value::String
    selection::Reference
end

JuliaInsertion(value::AbstractString="") = JuliaInsertion(Cell(String(value)), Cell(nothing))

Base.show(io::IO, j::JuliaInsertion) = print(io, "JuliaInsertion(", repr(j.value), ")")

function _apply_string_replace!(target::JuliaInsertion, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    field_name == "value" || error("JuliaInsertion supports only field 'value', got: $field_name")
    old = something(target.value, "")
    n = length(old)
    left  = s <= 0 ? "" : first(old, s)
    right = e >= n ? "" : last(old, n - e)
    target.value = String(left) * replacement * String(right)
end

# ── Literals ──────────────────────────────────────────────────────────────────

"""
    JuliaIdentifier(name::AbstractString)

A named identifier in a Julia expression (e.g. `n`, `factorial`).
"""
@document struct JuliaIdentifier <: JuliaDocument
    name::String
    selection::Reference
end

JuliaIdentifier(name::AbstractString) = JuliaIdentifier(Cell(String(name)), Cell(nothing))

"""
    JuliaInteger(value::Int)

An integer literal in a Julia expression.
"""
@document struct JuliaInteger <: JuliaDocument
    value::Int
    selection::Reference
end

JuliaInteger(value::Int) = JuliaInteger(Cell(value), Cell(nothing))

"""
    JuliaFloat(value::Float64)

A floating-point literal (e.g. `3.14`).
"""
@document struct JuliaFloat <: JuliaDocument
    value::Float64
    selection::Reference
end

JuliaFloat(value::Real) = JuliaFloat(Cell(Float64(value)), Cell(nothing))

"""
    JuliaString(value::AbstractString)

A plain string literal (e.g. `"hello"`). No interpolation.
"""
@document struct JuliaString <: JuliaDocument
    value::String
    selection::Reference
end

JuliaString(value::AbstractString) = JuliaString(Cell(String(value)), Cell(nothing))

"""
    JuliaBool(value::Bool)

A boolean literal (`true` or `false`).
"""
@document struct JuliaBool <: JuliaDocument
    value::Bool
    selection::Reference
end

JuliaBool(value::Bool) = JuliaBool(Cell(value), Cell(nothing))

"""
    JuliaNothing()

The literal `nothing`.
"""
@document struct JuliaNothing <: JuliaDocument
    selection::Reference
end

JuliaNothing() = JuliaNothing(Cell(nothing))

"""
    JuliaSymbol(name::AbstractString)

A symbol literal (e.g. `:foo`). `name` stores the text without the leading colon.
"""
@document struct JuliaSymbol <: JuliaDocument
    name::String
    selection::Reference
end

JuliaSymbol(name::AbstractString) = JuliaSymbol(Cell(String(name)), Cell(nothing))

"""
    JuliaChar(value::Char)

A character literal (e.g. `'x'`).
"""
@document struct JuliaChar <: JuliaDocument
    value::Char
    selection::Reference
end

JuliaChar(value::Char) = JuliaChar(Cell(value), Cell(nothing))

# ── Expressions ───────────────────────────────────────────────────────────────

"""
    JuliaBinaryOp(operator::Symbol, left, right)

A binary operation. `operator` is one of `:+`, `:-`, `:*`, `:/`, `:(==)`, etc.
"""
@document struct JuliaBinaryOp <: JuliaDocument
    operator::Symbol
    left::Document
    right::Document
    selection::Reference
end

JuliaBinaryOp(op::Symbol, left, right) =
    JuliaBinaryOp(Cell(op), Cell(left), Cell(right), Cell(nothing))

"""
    JuliaUnaryOp(operator::Symbol, operand)

A prefix unary operation (e.g. `-x`, `!flag`, `~bits`).
"""
@document struct JuliaUnaryOp <: JuliaDocument
    operator::Symbol
    operand::Document
    selection::Reference
end

JuliaUnaryOp(op::Symbol, operand) =
    JuliaUnaryOp(Cell(op), Cell(operand), Cell(nothing))

"""
    JuliaCall(callee, arguments::Vector)

A function call expression.
"""
@document struct JuliaCall <: JuliaDocument
    callee::Document
    arguments::CellVector
    selection::Reference
end

JuliaCall(callee, arguments::Vector) =
    JuliaCall(Cell(callee), CellVector(Cell[Cell(a) for a in arguments]), Cell(nothing))

"""
    JuliaTernary(condition, then_branch, else_branch)

A ternary expression `cond ? a : b`.
"""
@document struct JuliaTernary <: JuliaDocument
    condition::Document
    then_branch::Document
    else_branch::Document
    selection::Reference
end

JuliaTernary(cond, then_branch, else_branch) =
    JuliaTernary(Cell(cond), Cell(then_branch), Cell(else_branch), Cell(nothing))

"""
    JuliaIndex(collection, indices::Vector)

An indexing expression `a[i, j, …]`.
"""
@document struct JuliaIndex <: JuliaDocument
    collection::Document
    indices::CellVector
    selection::Reference
end

JuliaIndex(collection, indices::Vector) =
    JuliaIndex(Cell(collection), CellVector(Cell[Cell(i) for i in indices]), Cell(nothing))

"""
    JuliaFieldAccess(object, field)

A field access expression `object.field`. `field` is typically a `JuliaIdentifier`.
"""
@document struct JuliaFieldAccess <: JuliaDocument
    object::Document
    field::Document
    selection::Reference
end

JuliaFieldAccess(object, field) =
    JuliaFieldAccess(Cell(object), Cell(field), Cell(nothing))

"""
    JuliaTuple(elements::Vector)

A tuple literal `(a, b, c)`.
"""
@document struct JuliaTuple <: JuliaDocument
    elements::CellVector
    selection::Reference
end

JuliaTuple(elements::Vector) =
    JuliaTuple(CellVector(Cell[Cell(e) for e in elements]), Cell(nothing))

"""
    JuliaArray(elements::Vector)

An array literal `[a, b, c]`.
"""
@document struct JuliaArray <: JuliaDocument
    elements::CellVector
    selection::Reference
end

JuliaArray(elements::Vector) =
    JuliaArray(CellVector(Cell[Cell(e) for e in elements]), Cell(nothing))

"""
    JuliaRange(start, step, stop)

A range expression `start:stop` or `start:step:stop`. `step` may be `nothing`.
"""
@document struct JuliaRange <: JuliaDocument
    start::Document
    step::Union{Document,Nothing}
    stop::Document
    selection::Reference
end

JuliaRange(start, step, stop) =
    JuliaRange(Cell(start), Cell(step), Cell(stop), Cell(nothing))

JuliaRange(start, stop) = JuliaRange(start, nothing, stop)

"""
    JuliaTypeAnnotation(value, type)

A type annotation expression `value::type`.
"""
@document struct JuliaTypeAnnotation <: JuliaDocument
    value::Document
    type::Document
    selection::Reference
end

JuliaTypeAnnotation(value, type) =
    JuliaTypeAnnotation(Cell(value), Cell(type), Cell(nothing))

# ── Statements ────────────────────────────────────────────────────────────────

"""
    JuliaBlock(statements::Vector)

A sequence of statements/expressions.
"""
@document struct JuliaBlock <: JuliaDocument
    statements::CellVector
    selection::Reference
end

JuliaBlock(statements::Vector) =
    JuliaBlock(CellVector(Cell[Cell(s) for s in statements]), Cell(nothing))

"""
    JuliaAssignment(operator::Symbol, target, value)

An assignment statement. `operator` is one of `:(=)`, `:(+=)`, `:(-=)`, `:(*=)`, `:(/=)`.
"""
@document struct JuliaAssignment <: JuliaDocument
    operator::Symbol
    target::Document
    value::Document
    selection::Reference
end

JuliaAssignment(op::Symbol, target, value) =
    JuliaAssignment(Cell(op), Cell(target), Cell(value), Cell(nothing))

JuliaAssignment(target, value) = JuliaAssignment(:(=), target, value)

"""
    JuliaForIterator(variable, iterable)

One `var in iter` clause of a `for` loop. `JuliaFor` holds a `CellVector` of these.
"""
@document struct JuliaForIterator <: JuliaDocument
    variable::Document
    iterable::Document
    selection::Reference
end

JuliaForIterator(variable, iterable) =
    JuliaForIterator(Cell(variable), Cell(iterable), Cell(nothing))

"""
    JuliaFor(iterators::Vector, body)

A for loop `for v1 in i1, v2 in i2 … end`. Each entry of `iterators` is a
`JuliaForIterator`. `body` is typically a `JuliaBlock`.
"""
@document struct JuliaFor <: JuliaDocument
    iterators::CellVector
    body::Document
    selection::Reference
end

JuliaFor(iterators::Vector, body) =
    JuliaFor(CellVector(Cell[Cell(it) for it in iterators]), Cell(body), Cell(nothing))

"""
    JuliaWhile(condition, body)

A while loop `while cond … end`.
"""
@document struct JuliaWhile <: JuliaDocument
    condition::Document
    body::Document
    selection::Reference
end

JuliaWhile(condition, body) =
    JuliaWhile(Cell(condition), Cell(body), Cell(nothing))

"""
    JuliaReturn(value)

A return statement. `value` may be a `Document` or `nothing` for a bare `return`.
"""
@document struct JuliaReturn <: JuliaDocument
    value::Union{Document,Nothing}
    selection::Reference
end

JuliaReturn(value) = JuliaReturn(Cell(value), Cell(nothing))
JuliaReturn() = JuliaReturn(Cell(nothing), Cell(nothing))

"""
    JuliaBreak()

The `break` keyword.
"""
@document struct JuliaBreak <: JuliaDocument
    selection::Reference
end

JuliaBreak() = JuliaBreak(Cell(nothing))

"""
    JuliaContinue()

The `continue` keyword.
"""
@document struct JuliaContinue <: JuliaDocument
    selection::Reference
end

JuliaContinue() = JuliaContinue(Cell(nothing))

"""
    JuliaTry(body, catch_var, catch_branch, finally_branch)

A try expression. `catch_var`, `catch_branch`, and `finally_branch` may each be
`nothing` independently.
"""
@document struct JuliaTry <: JuliaDocument
    body::Document
    catch_var::Union{Document,Nothing}
    catch_branch::Union{Document,Nothing}
    finally_branch::Union{Document,Nothing}
    selection::Reference
end

JuliaTry(body, catch_var, catch_branch, finally_branch) =
    JuliaTry(Cell(body), Cell(catch_var), Cell(catch_branch), Cell(finally_branch), Cell(nothing))

"""
    JuliaBegin(body)

A `begin … end` block expression.
"""
@document struct JuliaBegin <: JuliaDocument
    body::Document
    selection::Reference
end

JuliaBegin(body) = JuliaBegin(Cell(body), Cell(nothing))

"""
    JuliaIf(condition, then_branch, else_branch)

An if-else expression.
"""
@document struct JuliaIf <: JuliaDocument
    condition::Document
    then_branch::Document
    else_branch::Document
    selection::Reference
end

JuliaIf(condition, then_branch, else_branch) =
    JuliaIf(Cell(condition), Cell(then_branch), Cell(else_branch), Cell(nothing))

"""
    JuliaFunction(name, params::Vector, body)

A function definition.
"""
@document struct JuliaFunction <: JuliaDocument
    name::Document
    params::CellVector
    body::Document
    selection::Reference
end

JuliaFunction(name, params::Vector, body) =
    JuliaFunction(Cell(name), CellVector(Cell[Cell(p) for p in params]), Cell(body), Cell(nothing))

# ── Utility ──────────────────────────────────────────────────────────────────

function _julia_operator_string(op::Symbol)
    op === :+ && return "+"
    op === :- && return "-"
    op === :* && return "*"
    op === :/ && return "/"
    op === :(==) && return "=="
    op === :(!=) && return "!="
    op === :(<) && return "<"
    op === :(>) && return ">"
    op === :(<=) && return "<="
    op === :(>=) && return ">="
    op === :! && return "!"
    op === :~ && return "~"
    op === :(=) && return "="
    op === :(+=) && return "+="
    op === :(-=) && return "-="
    op === :(*=) && return "*="
    op === :(/=) && return "/="
    op === :(:) && return ":"
    return string(op)
end

# ── Display ──────────────────────────────────────────────────────────────────

Base.show(io::IO, v::JuliaIdentifier) = print(io, v.name)
Base.show(io::IO, v::JuliaInteger) = print(io, v.value)
Base.show(io::IO, v::JuliaFloat) = print(io, v.value)
Base.show(io::IO, v::JuliaString) = print(io, '"', v.value, '"')
Base.show(io::IO, v::JuliaBool) = print(io, v.value)
Base.show(io::IO, ::JuliaNothing) = print(io, "nothing")
Base.show(io::IO, v::JuliaSymbol) = print(io, ':', v.name)
Base.show(io::IO, v::JuliaChar) = print(io, '\'', v.value, '\'')

function Base.show(io::IO, b::JuliaBinaryOp)
    show(io, b.left)
    print(io, " ", _julia_operator_string(b.operator), " ")
    show(io, b.right)
end

function Base.show(io::IO, u::JuliaUnaryOp)
    print(io, _julia_operator_string(u.operator))
    show(io, u.operand)
end

function Base.show(io::IO, c::JuliaCall)
    show(io, c.callee)
    print(io, "(")
    for (i, arg) in enumerate(c.arguments)
        i > 1 && print(io, ", ")
        show(io, arg)
    end
    print(io, ")")
end

function Base.show(io::IO, t::JuliaTernary)
    show(io, t.condition)
    print(io, " ? ")
    show(io, t.then_branch)
    print(io, " : ")
    show(io, t.else_branch)
end

function Base.show(io::IO, x::JuliaIndex)
    show(io, x.collection)
    print(io, "[")
    for (i, ix) in enumerate(x.indices)
        i > 1 && print(io, ", ")
        show(io, ix)
    end
    print(io, "]")
end

function Base.show(io::IO, f::JuliaFieldAccess)
    show(io, f.object)
    print(io, ".")
    show(io, f.field)
end

function Base.show(io::IO, t::JuliaTuple)
    print(io, "(")
    for (i, e) in enumerate(t.elements)
        i > 1 && print(io, ", ")
        show(io, e)
    end
    print(io, ")")
end

function Base.show(io::IO, a::JuliaArray)
    print(io, "[")
    for (i, e) in enumerate(a.elements)
        i > 1 && print(io, ", ")
        show(io, e)
    end
    print(io, "]")
end

function Base.show(io::IO, r::JuliaRange)
    show(io, r.start)
    print(io, ":")
    if r.step !== nothing
        show(io, r.step)
        print(io, ":")
    end
    show(io, r.stop)
end

function Base.show(io::IO, t::JuliaTypeAnnotation)
    show(io, t.value)
    print(io, "::")
    show(io, t.type)
end

function Base.show(io::IO, b::JuliaBlock)
    for (i, s) in enumerate(b.statements)
        i > 1 && print(io, "; ")
        show(io, s)
    end
end

function Base.show(io::IO, a::JuliaAssignment)
    show(io, a.target)
    print(io, " ", _julia_operator_string(a.operator), " ")
    show(io, a.value)
end

function Base.show(io::IO, it::JuliaForIterator)
    show(io, it.variable)
    print(io, " in ")
    show(io, it.iterable)
end

function Base.show(io::IO, ::JuliaFor)
    print(io, "for ... end")
end

function Base.show(io::IO, ::JuliaWhile)
    print(io, "while ... end")
end

function Base.show(io::IO, r::JuliaReturn)
    print(io, "return")
    if r.value !== nothing
        print(io, " ")
        show(io, r.value)
    end
end

Base.show(io::IO, ::JuliaBreak) = print(io, "break")
Base.show(io::IO, ::JuliaContinue) = print(io, "continue")

function Base.show(io::IO, ::JuliaTry)
    print(io, "try ... end")
end

function Base.show(io::IO, ::JuliaBegin)
    print(io, "begin ... end")
end

function Base.show(io::IO, f::JuliaIf)
    print(io, "if ")
    show(io, f.condition)
    print(io, " ... end")
end

function Base.show(io::IO, f::JuliaFunction)
    print(io, "function ")
    show(io, f.name)
    print(io, "(...) ... end")
end

end # module
