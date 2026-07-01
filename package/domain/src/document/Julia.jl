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
export JuliaDocument, JuliaInsertion,
       JuliaIdentifier, JuliaInteger, JuliaFloat, JuliaString, JuliaBool,
       JuliaNothing, JuliaSymbol, JuliaChar,
       JuliaBinaryOp, JuliaUnaryOp, JuliaCall, JuliaTernary,
       JuliaIndex, JuliaFieldAccess, JuliaTuple, JuliaArray, JuliaRange,
       JuliaTypeAnnotation,
       JuliaAssignment, JuliaFor, JuliaForIterator, JuliaWhile,
       JuliaReturn, JuliaBreak, JuliaContinue, JuliaTry, JuliaBegin,
       JuliaIf, JuliaFunction, JuliaBlock, JuliaUsing, JuliaLambda,
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
    value::String = ""
    selection::Reference = nothing
end

JuliaInsertion(value::AbstractString) = JuliaInsertion(value, nothing)

# A JuliaInsertion's `value` (the buffer of typed text) is a plain string, so
# text-replace edits are handled generically by `splice_value!` (see
# OperationApiModule). No per-type method is needed.

# ── Literals ──────────────────────────────────────────────────────────────────

"""
    JuliaIdentifier(name::AbstractString)

A named identifier in a Julia expression (e.g. `n`, `factorial`).
"""
@document struct JuliaIdentifier <: JuliaDocument
    name::String
    selection::Reference = nothing
end

"""
    JuliaInteger(value::Int)

An integer literal in a Julia expression.
"""
@document struct JuliaInteger <: JuliaDocument
    value::Int
    selection::Reference = nothing
end

"""
    JuliaFloat(value::Float64)

A floating-point literal (e.g. `3.14`).
"""
@document struct JuliaFloat <: JuliaDocument
    value::Float64
    selection::Reference = nothing
end

"""
    JuliaString(value::AbstractString)

A plain string literal (e.g. `"hello"`). No interpolation.
"""
@document struct JuliaString <: JuliaDocument
    value::String
    selection::Reference = nothing
end

"""
    JuliaBool(value::Bool)

A boolean literal (`true` or `false`).
"""
@document struct JuliaBool <: JuliaDocument
    value::Bool
    selection::Reference = nothing
end

"""
    JuliaNothing()

The literal `nothing`.
"""
@document struct JuliaNothing <: JuliaDocument
    selection::Reference = nothing
end

"""
    JuliaSymbol(name::AbstractString)

A symbol literal (e.g. `:foo`). `name` stores the text without the leading colon.
"""
@document struct JuliaSymbol <: JuliaDocument
    name::String
    selection::Reference = nothing
end

"""
    JuliaChar(value::Char)

A character literal (e.g. `'x'`).
"""
@document struct JuliaChar <: JuliaDocument
    value::Char
    selection::Reference = nothing
end

# ── Expressions ───────────────────────────────────────────────────────────────

"""
    JuliaBinaryOp(operator::Symbol, left, right)

A binary operation. `operator` is one of `:+`, `:-`, `:*`, `:/`, `:(==)`, etc.
"""
@document struct JuliaBinaryOp <: JuliaDocument
    operator::Symbol
    left::Document
    right::Document
    selection::Reference = nothing
end

"""
    JuliaUnaryOp(operator::Symbol, operand)

A prefix unary operation (e.g. `-x`, `!flag`, `~bits`).
"""
@document struct JuliaUnaryOp <: JuliaDocument
    operator::Symbol
    operand::Document
    selection::Reference = nothing
end

"""
    JuliaCall(callee, arguments::Vector)

A function call expression.
"""
@document struct JuliaCall <: JuliaDocument
    callee::Document
    arguments::CellVector
    selection::Reference = nothing
end

"""
    JuliaTernary(condition, then_branch, else_branch)

A ternary expression `cond ? a : b`.
"""
@document struct JuliaTernary <: JuliaDocument
    condition::Document
    then_branch::Document
    else_branch::Document
    selection::Reference = nothing
end

"""
    JuliaIndex(collection, indices::Vector)

An indexing expression `a[i, j, …]`.
"""
@document struct JuliaIndex <: JuliaDocument
    collection::Document
    indices::CellVector
    selection::Reference = nothing
end

"""
    JuliaFieldAccess(object, field)

A field access expression `object.field`. `field` is typically a `JuliaIdentifier`.
"""
@document struct JuliaFieldAccess <: JuliaDocument
    object::Document
    field::Document
    selection::Reference = nothing
end

"""
    JuliaTuple(elements::Vector)

A tuple literal `(a, b, c)`.
"""
@document struct JuliaTuple <: JuliaDocument
    elements::CellVector = CellVector()
    selection::Reference = nothing
end

"""
    JuliaArray(elements::Vector)

An array literal `[a, b, c]`.
"""
@document struct JuliaArray <: JuliaDocument
    elements::CellVector = CellVector()
    selection::Reference = nothing
end

"""
    JuliaRange(start, step, stop)

A range expression `start:stop` or `start:step:stop`. `step` may be `nothing`.
"""
@document struct JuliaRange <: JuliaDocument
    start::Document
    step::Union{Document,Nothing}
    stop::Document
    selection::Reference = nothing
end

# a range with no step
JuliaRange(start, stop) = JuliaRange(start, nothing, stop)

"""
    JuliaTypeAnnotation(value, type)

A type annotation expression `value::type`.
"""
@document struct JuliaTypeAnnotation <: JuliaDocument
    value::Document
    type::Document
    selection::Reference = nothing
end

# ── Statements ────────────────────────────────────────────────────────────────

"""
    JuliaBlock(statements::Vector)

A sequence of statements/expressions.
"""
@document struct JuliaBlock <: JuliaDocument
    statements::CellVector = CellVector()
    selection::Reference = nothing
end

"""
    JuliaUsing(keyword::Symbol, path::AbstractString)

A `using`/`import` statement. `keyword` is `:using` or `:import`; `path` is the
rendered module spec exactly as written, e.g. `"Main.OmnetppPredExample"`,
`"A, B"`, or `"A: x, y"`. Kept as a flat string (the spec is a path, not a nested
expression), so the projection renders the keyword highlighted and the path
verbatim.
"""
@document struct JuliaUsing <: JuliaDocument
    keyword::Symbol
    path::String
    selection::Reference = nothing
end

"""
    JuliaLambda(parameters::Vector, body)

An anonymous function `(p₁, p₂, …) -> body`. `parameters` are the argument
documents (empty for `() -> …`); `body` is the returned expression.
"""
@document struct JuliaLambda <: JuliaDocument
    parameters::CellVector
    body::Document
    selection::Reference = nothing
end

"""
    JuliaAssignment(operator::Symbol, target, value)

An assignment statement. `operator` is one of `:(=)`, `:(+=)`, `:(-=)`, `:(*=)`, `:(/=)`.
"""
@document struct JuliaAssignment <: JuliaDocument
    operator::Symbol
    target::Document
    value::Document
    selection::Reference = nothing
end

# assignment defaulting the operator to `=`
JuliaAssignment(target, value) = JuliaAssignment(:(=), target, value)

"""
    JuliaForIterator(variable, iterable)

One `var in iter` clause of a `for` loop. `JuliaFor` holds a `CellVector` of these.
"""
@document struct JuliaForIterator <: JuliaDocument
    variable::Document
    iterable::Document
    selection::Reference = nothing
end

"""
    JuliaFor(iterators::Vector, body)

A for loop `for v1 in i1, v2 in i2 … end`. Each entry of `iterators` is a
`JuliaForIterator`. `body` is typically a `JuliaBlock`.
"""
@document struct JuliaFor <: JuliaDocument
    iterators::CellVector
    body::Document
    selection::Reference = nothing
end

"""
    JuliaWhile(condition, body)

A while loop `while cond … end`.
"""
@document struct JuliaWhile <: JuliaDocument
    condition::Document
    body::Document
    selection::Reference = nothing
end

"""
    JuliaReturn(value)

A return statement. `value` may be a `Document` or `nothing` for a bare `return`.
"""
@document struct JuliaReturn <: JuliaDocument
    value::Union{Document,Nothing} = nothing
    selection::Reference = nothing
end

JuliaReturn(value) = JuliaReturn(value, nothing)

"""
    JuliaBreak()

The `break` keyword.
"""
@document struct JuliaBreak <: JuliaDocument
    selection::Reference = nothing
end

"""
    JuliaContinue()

The `continue` keyword.
"""
@document struct JuliaContinue <: JuliaDocument
    selection::Reference = nothing
end

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
    selection::Reference = nothing
end

"""
    JuliaBegin(body)

A `begin … end` block expression.
"""
@document struct JuliaBegin <: JuliaDocument
    body::Document
    selection::Reference = nothing
end

"""
    JuliaIf(condition, then_branch, else_branch)

An if-else expression.
"""
@document struct JuliaIf <: JuliaDocument
    condition::Document
    then_branch::Document
    else_branch::Document
    selection::Reference = nothing
end

"""
    JuliaFunction(name, params::Vector, body)

A function definition.
"""
@document struct JuliaFunction <: JuliaDocument
    name::Document
    params::CellVector
    body::Document
    selection::Reference = nothing
end

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

end # module
