"""
    JuliaModule

The Julia document domain — a Julia AST as reactive `Document`s. Leaves
(identifiers, literals), expressions (binary/call/index/…), and statements
(assign/for/if/function/block).
"""
module JuliaModule

import ..CellModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
import ..DomainModule: var"@domain"
export JuliaDocument, _julia_operator_string

# ── Abstract base ─────────────────────────────────────────────────────────────

abstract type JuliaDocument <: Document end

# ── Insertion (editable Julia source being entered) ────────────────────────────

"""
A placeholder holding Julia source text being typed; committed (e.g. on Enter)
by parsing `value` with `juliaparse` into a real `JuliaDocument`.
"""
@document struct JuliaInsertion <: JuliaDocument
    value::String = ""
    selection::Reference = nothing
end

JuliaInsertion(value::AbstractString) = JuliaInsertion(value, nothing)

# `value` is a plain string, so text-replace edits go through the generic `splice_value!`.

# ── Literals ──────────────────────────────────────────────────────────────────

"""
A named identifier in a Julia expression (e.g. `n`, `factorial`).
"""
@document struct JuliaIdentifier <: JuliaDocument
    name::String
    selection::Reference = nothing
end

"""
An integer literal in a Julia expression.
"""
@document struct JuliaInteger <: JuliaDocument
    value::Int
    selection::Reference = nothing
end

"""
A floating-point literal (e.g. `3.14`).
"""
@document struct JuliaFloat <: JuliaDocument
    value::Float64
    selection::Reference = nothing
end

"""
A plain string literal (e.g. `"hello"`). No interpolation.
"""
@document struct JuliaString <: JuliaDocument
    value::String
    selection::Reference = nothing
end

"""
A boolean literal (`true` or `false`).
"""
@document struct JuliaBool <: JuliaDocument
    value::Bool
    selection::Reference = nothing
end

"""
The literal `nothing`.
"""
@document struct JuliaNothing <: JuliaDocument
    selection::Reference = nothing
end

# The insertion kit adopts the existing types: `JuliaNothing` doubles as the
# empty placeholder (it is also the parsed `nothing` literal) and
# `JuliaInsertion` as the source/typed-name buffer — only the traits, the
# `"julia"` alias, and the Insert gesture are generated.
@domain Julia root = JuliaDocument nothing = JuliaNothing insertion = JuliaInsertion

"""
A symbol literal (e.g. `:foo`). `name` stores the text without the leading colon.
"""
@document struct JuliaSymbol <: JuliaDocument
    name::String
    selection::Reference = nothing
end

"""
A character literal (e.g. `'x'`).
"""
@document struct JuliaChar <: JuliaDocument
    value::Char
    selection::Reference = nothing
end

# ── Expressions ───────────────────────────────────────────────────────────────

"""
A binary operation. `operator` is one of `:+`, `:-`, `:*`, `:/`, `:(==)`, etc.
"""
@document struct JuliaBinaryOp <: JuliaDocument
    operator::Symbol
    left::Document
    right::Document
    selection::Reference = nothing
end

"""
A prefix unary operation (e.g. `-x`, `!flag`, `~bits`).
"""
@document struct JuliaUnaryOp <: JuliaDocument
    operator::Symbol
    operand::Document
    selection::Reference = nothing
end

"""
A function call expression.
"""
@document struct JuliaCall <: JuliaDocument
    callee::Document
    arguments::CellVector
    selection::Reference = nothing
end

"""
A ternary expression `cond ? a : b`.
"""
@document struct JuliaTernary <: JuliaDocument
    condition::Document
    then_branch::Document
    else_branch::Document
    selection::Reference = nothing
end

"""
An indexing expression `a[i, j, …]`.
"""
@document struct JuliaIndex <: JuliaDocument
    collection::Document
    indices::CellVector
    selection::Reference = nothing
end

"""
A field access expression `object.field`. `field` is typically a `JuliaIdentifier`.
"""
@document struct JuliaFieldAccess <: JuliaDocument
    object::Document
    field::Document
    selection::Reference = nothing
end

"""
A tuple literal `(a, b, c)`.
"""
@document struct JuliaTuple <: JuliaDocument
    elements::CellVector = CellVector()
    selection::Reference = nothing
end

"""
An array literal `[a, b, c]`.
"""
@document struct JuliaArray <: JuliaDocument
    elements::CellVector = CellVector()
    selection::Reference = nothing
end

"""
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
A type annotation expression `value::type`.
"""
@document struct JuliaTypeAnnotation <: JuliaDocument
    value::Document
    type::Document
    selection::Reference = nothing
end

# ── Statements ────────────────────────────────────────────────────────────────

"""
A sequence of statements/expressions.
"""
@document struct JuliaBlock <: JuliaDocument
    statements::CellVector = CellVector()
    selection::Reference = nothing
end

"""
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
An anonymous function `(p₁, p₂, …) -> body`. `parameters` are the argument
documents (empty for `() -> …`); `body` is the returned expression.
"""
@document struct JuliaLambda <: JuliaDocument
    parameters::CellVector
    body::Document
    selection::Reference = nothing
end

"""
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
One `var in iter` clause of a `for` loop. `JuliaFor` holds a `CellVector` of these.
"""
@document struct JuliaForIterator <: JuliaDocument
    variable::Document
    iterable::Document
    selection::Reference = nothing
end

"""
A for loop `for v1 in i1, v2 in i2 … end`. Each entry of `iterators` is a
`JuliaForIterator`. `body` is typically a `JuliaBlock`.
"""
@document struct JuliaFor <: JuliaDocument
    iterators::CellVector
    body::Document
    selection::Reference = nothing
end

"""
A while loop `while cond … end`.
"""
@document struct JuliaWhile <: JuliaDocument
    condition::Document
    body::Document
    selection::Reference = nothing
end

"""
A return statement. `value` may be a `Document` or `nothing` for a bare `return`.
"""
@document struct JuliaReturn <: JuliaDocument
    value::Union{Document,Nothing} = nothing
    selection::Reference = nothing
end

JuliaReturn(value) = JuliaReturn(value, nothing)

"""
The `break` keyword.
"""
@document struct JuliaBreak <: JuliaDocument
    selection::Reference = nothing
end

"""
The `continue` keyword.
"""
@document struct JuliaContinue <: JuliaDocument
    selection::Reference = nothing
end

"""
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
A `begin … end` block expression.
"""
@document struct JuliaBegin <: JuliaDocument
    body::Document
    selection::Reference = nothing
end

"""
An if-else expression.
"""
@document struct JuliaIf <: JuliaDocument
    condition::Document
    then_branch::Document
    else_branch::Document
    selection::Reference = nothing
end

"""
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
