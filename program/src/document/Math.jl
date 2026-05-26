"""
    MathModule

The math document domain provides reactive representations of arithmetic formulas.
Every math value is a Document with all mutable fields wrapped in reactive Cells,
enabling automatic dependency tracking and incremental updates.

The domain includes:
- **Leaf types**: `MathVariable` (named variable), `PrimitiveNumber` (numeric literal, from PrimitiveModule)
- **Compound types**: `MathBinaryOperation` (binary +, -, *, /), `MathParenthesized` (explicit grouping), `MathAssignment` (X = expr)
- **Utility types**: `MathInsertion` for cursor positioning

Example: `X = (3 * A + B) / 2` is represented as:
```
MathAssignment(
  MathVariable("X"),
  MathBinaryOperation(:/, MathParenthesized(
    MathBinaryOperation(:+,
      MathBinaryOperation(:*, PrimitiveNumber(3), MathVariable("A")),
      MathVariable("B"))),
    PrimitiveNumber(2)))
```

Selection semantics:
- Variables: `.name[k]` — character offset within the variable name
- Binary operations: `.left`, `.right` — cursor within operands; `.operator[k]` — character within operator symbol
- Parenthesized: `.content` — cursor within the inner expression
- Assignments: `.target`, `.value` — cursor within LHS or RHS
"""
module MathModule

import ..ReactiveModule: Cell
import ..DocumentModule: Document, @document
import ..ReferenceModule: Reference
export MathDocument, MathInsertion, MathVariable, MathBinaryOperation, MathParenthesized, MathAssignment,
       IMathInsertion, IMathVariable, IMathBinaryOperation, IMathParenthesized, IMathAssignment,
       _operator_string

# ── Abstract base ─────────────────────────────────────────────────────────────

abstract type MathDocument <: Document end

# ── MathInsertion ─────────────────────────────────────────────────────────────

@document struct MathInsertion <: MathDocument
    value::Any
    selection::Reference
end

MathInsertion() = MathInsertion(Cell(nothing), Cell(nothing))

# ── MathVariable ──────────────────────────────────────────────────────────────

"""
    MathVariable(name::AbstractString)

A named variable in a math expression (e.g. `X`, `A`, `B`).
`name` is a `Cell` holding a `String`.
"""
@document struct MathVariable <: MathDocument
    name::String
    selection::Reference
end

MathVariable(name::AbstractString) = MathVariable(Cell(name), Cell(nothing))

# ── MathBinaryOperation ──────────────────────────────────────────────────────

"""
    MathBinaryOperation(operator::Symbol, left, right)

A binary arithmetic operation. `operator` is one of `:+`, `:-`, `:*`, `:/`.
`left` and `right` are any `Document` (typically `MathDocument` or `PrimitiveNumber`).
"""
@document struct MathBinaryOperation <: MathDocument
    operator::Symbol
    left::Document
    right::Document
    selection::Reference
end

MathBinaryOperation(op::Symbol, left, right) =
    MathBinaryOperation(Cell(op), Cell(left), Cell(right), Cell(nothing))

# ── MathParenthesized ────────────────────────────────────────────────────────

"""
    MathParenthesized(content)

Explicit parenthesized grouping around a sub-expression.
"""
@document struct MathParenthesized <: MathDocument
    content::Document
    selection::Reference
end

MathParenthesized(content) = MathParenthesized(Cell(content), Cell(nothing))

# ── MathAssignment ────────────────────────────────────────────────────────────

"""
    MathAssignment(target, value)

An assignment expression: `target = value`.
"""
@document struct MathAssignment <: MathDocument
    target::Document
    value::Document
    selection::Reference
end

MathAssignment(target, value) = MathAssignment(Cell(target), Cell(value), Cell(nothing))

# ── Utility ───────────────────────────────────────────────────────────────────

function _operator_string(op::Symbol)
    op === :+ && return "+"
    op === :- && return "-"
    op === :* && return "*"
    op === :/ && return "/"
    return string(op)
end

# ── Display ───────────────────────────────────────────────────────────────────

Base.show(io::IO, ::MathInsertion) = print(io, "⌷")
Base.show(io::IO, v::MathVariable) = print(io, v.name)

function Base.show(io::IO, b::MathBinaryOperation)
    show(io, b.left)
    print(io, " ", _operator_string(b.operator), " ")
    show(io, b.right)
end

function Base.show(io::IO, p::MathParenthesized)
    print(io, "(")
    show(io, p.content)
    print(io, ")")
end

function Base.show(io::IO, a::MathAssignment)
    show(io, a.target)
    print(io, " = ")
    show(io, a.value)
end

end # module
