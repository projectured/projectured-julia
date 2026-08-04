"""
    JuliaModule

The Julia document domain — a Julia AST as reactive `Document`s. Leaves
(identifiers, literals), expressions (binary/call/index/…), and statements
(assign/for/if/function/block).
"""
module JuliaModule

using ..DocumentModule
using ..CollectionModule
using ..ReferenceModule   # `@document` injects the implicit `selection::Union{Nothing, Reference}` field
using ..DomainModule
export _julia_operator_string

# ── Abstract base ─────────────────────────────────────────────────────────────

abstract type JuliaDocument <: Document end

# ── Insertion (editable Julia source being entered) ────────────────────────────

"""
A placeholder holding Julia source text being typed; committed (e.g. on Enter)
by parsing `value` with `juliaparse` into a real `JuliaDocument`.
"""
@document struct JuliaInsertion <: JuliaDocument
    value::String = ""
end

JuliaInsertion(value::AbstractString) = JuliaInsertion(value, nothing)

# `value` is a plain string, so text-replace edits go through the generic `splice_value!`.

# ── Literals ──────────────────────────────────────────────────────────────────

"""
A named identifier in a Julia expression (e.g. `n`, `factorial`).
"""
@document struct JuliaIdentifier <: JuliaDocument
    name::String
end

"""
An integer literal in a Julia expression.
"""
@document struct JuliaInteger <: JuliaDocument
    value::Int
end

"""
A floating-point literal (e.g. `3.14`).
"""
@document struct JuliaFloat <: JuliaDocument
    value::Float64
end

"""
A plain string literal (e.g. `"hello"`). No interpolation.
"""
@document struct JuliaString <: JuliaDocument
    value::String
end

"""
A boolean literal (`true` or `false`).
"""
@document struct JuliaBool <: JuliaDocument
    value::Bool
end

"""
The literal `nothing`.
"""
@document struct JuliaNothing <: JuliaDocument
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
end

"""
A character literal (e.g. `'x'`).
"""
@document struct JuliaChar <: JuliaDocument
    value::Char
end

# ── Expressions ───────────────────────────────────────────────────────────────

"""
A binary operation. `operator` is one of `:+`, `:-`, `:*`, `:/`, `:(==)`, etc.
"""
@document struct JuliaBinaryOp <: JuliaDocument
    operator::Symbol
    left::Document
    right::Document
end

"""
A prefix unary operation (e.g. `-x`, `!flag`, `~bits`).
"""
@document struct JuliaUnaryOp <: JuliaDocument
    operator::Symbol
    operand::Document
end

"""
A function call expression.
"""
@document struct JuliaCall <: JuliaDocument
    callee::Document
    arguments::CellVector
end

"""
A macro call expression, e.g. `@doc "…" expr` or `@show x`. `name` is
the macro name written in source (starts with `@`); `arguments` are
the arguments after the macro name. Line-info nodes the native
`Expr(:macrocall, …)` interleaves are stripped by the parser so
arguments hold only real values.
"""
@document struct JuliaMacroCall <: JuliaDocument
    name::String
    arguments::CellVector
end

"""
A ternary expression `cond ? a : b`.
"""
@document struct JuliaTernary <: JuliaDocument
    condition::Document
    then_branch::Document
    else_branch::Document
end

"""
An indexing expression `a[i, j, …]`.
"""
@document struct JuliaIndex <: JuliaDocument
    collection::Document
    indices::CellVector
end

"""
A field access expression `object.field`. `field` is typically a `JuliaIdentifier`.
"""
@document struct JuliaFieldAccess <: JuliaDocument
    object::Document
    field::Document
end

"""
A tuple literal `(a, b, c)`.
"""
@document struct JuliaTuple <: JuliaDocument
    elements::CellVector = CellVector()
end

"""
An array literal `[a, b, c]`.
"""
@document struct JuliaArray <: JuliaDocument
    elements::CellVector = CellVector()
end

"""
A range expression `start:stop` or `start:step:stop`. `step` may be `nothing`.
"""
@document struct JuliaRange <: JuliaDocument
    start::Document
    step::Union{Document,Nothing}
    stop::Document
end

# a range with no step
JuliaRange(start, stop) = JuliaRange(start, nothing, stop)

"""
A type annotation expression `value::type`.
"""
@document struct JuliaTypeAnnotation <: JuliaDocument
    value::Document
    type::Document
end

"""
The anonymous form of a type annotation — `::T` on its own, as
in a dispatch pin `foo(::Type{Bar}) = …`. Distinct from
`JuliaTypeAnnotation` because there is no value expression to
project (a bare "nothing" would render literally); the printer emits
only `::` followed by `type`.
"""
@document struct JuliaAnonymousTypeAnnotation <: JuliaDocument
    type::Document
end

"""
An empty placeholder that renders as no text at all. The parser
uses it for the else-branch of an `if …end` with no else clause —
distinct from `JuliaNothing` (which renders the literal
`nothing`) and from an empty `JuliaBlock` (which still emits its
trailing line-chrome, producing a stray blank line before the
closing `end`).
"""
@document struct JuliaEmpty <: JuliaDocument
end

# ── Statements ────────────────────────────────────────────────────────────────

"""
A sequence of statements/expressions.
"""
@document struct JuliaBlock <: JuliaDocument
    statements::CellVector = CellVector()
end

"""
A `using`/`import`/`export` statement. `keyword` is `:using`, `:import`,
`:export` or `:public`; `path` is the rendered spec exactly as written, e.g.
`"Main.OmnetppPredExample"`, `"A, B"`, or `"A: x, y"`. Kept as a flat string
(the spec is a path or a name list, not a nested expression), so the projection
renders the keyword highlighted and the rest verbatim.
"""
@document struct JuliaUsing <: JuliaDocument
    keyword::Symbol
    path::String
end

"""
An anonymous function `(p₁, p₂, …) -> body`. `parameters` are the argument
documents (empty for `() -> …`); `body` is the returned expression.
"""
@document struct JuliaLambda <: JuliaDocument
    parameters::CellVector
    body::Document
end

"""
An assignment statement. `operator` is one of `:(=)`, `:(+=)`, `:(-=)`, `:(*=)`, `:(/=)`.
"""
@document struct JuliaAssignment <: JuliaDocument
    operator::Symbol
    target::Document
    value::Document
end

# assignment defaulting the operator to `=`
JuliaAssignment(target, value) = JuliaAssignment(:(=), target, value)

"""
A `const` declaration wrapping an assignment (`const X = value`).
The inner `assignment` is typically a `JuliaAssignment`.
"""
@document struct JuliaConst <: JuliaDocument
    assignment::Document
end

"""
A docstring attached to a definition — the natural surface form
Julia writes as a triple-quoted string above a definition. `text` is
the raw docstring content (no surrounding quotes); `subject` is the
definition the docstring documents (a `JuliaFunction`, `JuliaConst`,
`JuliaAssignment`, …). At the `Expr` level Julia desugars a
docstring to `Core.@doc "text" subject`; the parser recognises that
pattern and lifts it back to this form so the source renders as a
docstring, not as a raw macrocall.
"""
@document struct JuliaDocstring <: JuliaDocument
    text::String
    subject::Document
end

"""
An abstract type declaration — `abstract type Name <: Super end` or
`abstract type Name end`. `header` is the name expression as written
(a `JuliaIdentifier` for the simple case, a `JuliaSubtype` when a
supertype is given, a `JuliaCurly` when type parameters appear).
"""
@document struct JuliaAbstractType <: JuliaDocument
    header::Document
end

"""
A struct declaration — `struct Name … end` or
`mutable struct Name … end`. `mutable` is `true` for the mutable
form; `header` is the name expression as written (same shapes as
`JuliaAbstractType.header`); `body` is a `JuliaBlock` of field /
constructor statements. Line-info nodes the parser interleaves in
the body are stripped, mirroring `_convert_statements` for a plain
block.
"""
@document struct JuliaStruct <: JuliaDocument
    mutable::Bool
    header::Document
    body::Document
end

"""
A module definition `module Name … end`; `bare` distinguishes `baremodule`.
`body` is a `JuliaBlock` of the module's top-level statements.

A module is the unit a `.jl` file *is*, which is why it is modeled: a document
that projects to a complete, loadable file has to be able to say `module`.
"""
@document struct JuliaModuleDef <: JuliaDocument
    name::String
    body::Document
    bare::Bool = false
end

"""
A subtype expression `lhs <: rhs`. Distinct from `JuliaBinaryOp`
because `<:` is not a runtime operator — the parser emits it as
`Expr(:<:, lhs, rhs)` and it appears in type headers, not in
arithmetic. Keeping a dedicated document type lets the printer style
it as a keyword-tinted operator and lets a future kind-checker
reason about it without pattern-matching on operator strings.
"""
@document struct JuliaSubtype <: JuliaDocument
    lhs::Document
    rhs::Document
end

"""
A parametric type expression `Foo{T, S, …}` — Julia's
`Expr(:curly, callee, params…)`. `callee` is the base type
(typically a `JuliaIdentifier`); `params` are the type arguments,
which may be identifiers, other parametric types, or `<:` bounds.
"""
@document struct JuliaCurly <: JuliaDocument
    callee::Document
    params::CellVector
end

"""
One `var in iter` clause of a `for` loop. `JuliaFor` holds a `CellVector` of these.
"""
@document struct JuliaForIterator <: JuliaDocument
    variable::Document
    iterable::Document
end

"""
A for loop `for v1 in i1, v2 in i2 … end`. Each entry of `iterators` is a
`JuliaForIterator`. `body` is typically a `JuliaBlock`.
"""
@document struct JuliaFor <: JuliaDocument
    iterators::CellVector
    body::Document
end

"""
A while loop `while cond … end`.
"""
@document struct JuliaWhile <: JuliaDocument
    condition::Document
    body::Document
end

"""
A return statement. `value` may be a `Document` or `nothing` for a bare `return`.
"""
@document struct JuliaReturn <: JuliaDocument
    value::Union{Document,Nothing} = nothing
end

JuliaReturn(value) = JuliaReturn(value, nothing)

"""
The `break` keyword.
"""
@document struct JuliaBreak <: JuliaDocument
end

"""
The `continue` keyword.
"""
@document struct JuliaContinue <: JuliaDocument
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
end

"""
A `begin … end` block expression.
"""
@document struct JuliaBegin <: JuliaDocument
    body::Document
end

"""
An if-else expression.
"""
@document struct JuliaIf <: JuliaDocument
    condition::Document
    then_branch::Document
    else_branch::Document
end

"""
A function definition.
"""
@document struct JuliaFunction <: JuliaDocument
    name::Document
    params::CellVector
    body::Document
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
    op === :(===) && return "==="
    op === :(!==) && return "!=="
    op === :! && return "!"
    op === :~ && return "~"
    op === :&& && return "&&"
    op === :|| && return "||"
    op === :(=) && return "="
    op === :(+=) && return "+="
    op === :(-=) && return "-="
    op === :(*=) && return "*="
    op === :(/=) && return "/="
    op === :(:) && return ":"
    return string(op)
end

end # module
