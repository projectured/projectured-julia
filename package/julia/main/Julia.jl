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
A splatted argument — `f(xs...)`, `(a, b...)`. `value` is what is
splatted; the `...` is postfix, which is why this is a node of its own
rather than a `JuliaUnaryOp`.
"""
@document struct JuliaSplat <: JuliaDocument
    value::Document
end

"""
A broadcast call — `f.(a, b)`. Structurally a call whose dot means
"apply elementwise", and written as one, so it keeps `callee` and
`arguments` rather than reusing `JuliaFieldAccess` (which is what the
same `Expr(:.)` head means when its second argument is a name).
"""
@document struct JuliaBroadcast <: JuliaDocument
    callee::Document
    arguments::CellVector
end

"""
An interpolated string — `"a \$(x) b"`. `parts` alternates literal text
(`JuliaString`) with the expressions between; a part that is not a
`JuliaString` is rendered inside `\$(…)`.
"""
@document struct JuliaStringInterpolation <: JuliaDocument
    parts::CellVector = CellVector()
end

"""
One literal run inside an interpolated string. Distinct from
`JuliaString` because it is already inside the quotes: it prints its
text and nothing else.
"""
@document struct JuliaStringChunk <: JuliaDocument
    text::String
end

"""
One interpolated expression inside a string — the `\$(…)` part.
"""
@document struct JuliaInterpolation <: JuliaDocument
    value::Document
end

"""
A `where` clause — `f(x::T) where {T}`, `Vector{T} where T`.
`parameters` are the type variables it introduces; the braces are
always written, which is the form that stays readable when there is
more than one.
"""
@document struct JuliaWhere <: JuliaDocument
    body::Document
    parameters::CellVector = CellVector()
end

"""
A comprehension or a generator — `[f(i) for i in r]`, `Any[…]`,
`(f(i) for i in r)`.

`element_type` is the type before the bracket (`JuliaEmpty` when there
is none) and `brackets` distinguishes a comprehension, which builds a
collection, from a generator, which does not.
"""
@document struct JuliaComprehension <: JuliaDocument
    expression::Document
    iterators::CellVector
    element_type::Document = JuliaEmpty()
    brackets::Bool = true
    condition::Document = JuliaEmpty()
end

"""
A `do` block — `map(xs) do x … end`. `call` is the call the block is
attached to; `parameters` and `body` are the function it passes,
written out rather than kept as a lambda, because `do` writes them
without the arrow a lambda would.
"""
@document struct JuliaDo <: JuliaDocument
    call::Document
    parameters::CellVector
    body::Document
end

"""
A `let` block — `let x = 1, y = 2 … end`. `bindings` are the
assignments it opens with (possibly none, for a bare `let … end`).
"""
@document struct JuliaLet <: JuliaDocument
    bindings::CellVector
    body::Document
end

"""
A named tuple — `(; a = 1, b = 2)`. Distinct from `JuliaTuple` because
the leading `;` and the `name = value` entries are not what a
positional tuple writes.
"""
@document struct JuliaNamedTuple <: JuliaDocument
    entries::CellVector = CellVector()
end

"""
A function definition. `result_type` is the declared return type and
`where_clause` a [`JuliaWhereParameters`](@ref); both are `JuliaEmpty`
when absent, and print as nothing.

The `where` lives here rather than wrapping the whole definition in a
[`JuliaWhere`](@ref), because that is where it is written: after the
parameter list, not after `end`. It is a single document rather than a
collection because **`params` is this struct's one vector field** — a
`@document` with two of them loses the sugar that wraps a raw `Vector`
into a `CellVector`, and `params` would stop being a place the
selection walker can descend.
"""
@document struct JuliaFunction <: JuliaDocument
    name::Document
    params::CellVector
    body::Document
    result_type::Document = JuliaEmpty()
    where_clause::Document = JuliaEmpty()
end

"""
The type variables a `where` introduces, as one document — `where {T,
S}`. Its own node so a function's signature can carry it in a single
field (see [`JuliaFunction`](@ref)).
"""
@document struct JuliaWhereParameters <: JuliaDocument
    parameters::CellVector
end

"""
A bare function declaration — `function f end`, which introduces a
name without a method. Its own node because it has no parameter list
at all, which is not the same as an empty one.
"""
@document struct JuliaFunctionDeclaration <: JuliaDocument
    name::Document
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
