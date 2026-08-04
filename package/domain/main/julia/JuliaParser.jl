"""
    JuliaParserModule

Parser for Julia source code. Converts Julia source text into a `JuliaDocument`
tree from `JuliaModule`.

Provides:
- `juliaparse(text)` — parse a Julia string into a `JuliaDocument`
- `juliaparse_file(path)` — read and parse a `.jl` file from disk

The parser delegates lexing and grammar to Julia's own parser (`Meta.parseall`,
backed by `JuliaSyntax`). A single recursive pass (`convert_expr`) walks the
native `Expr`/literal tree and builds `JuliaDocument` nodes directly — there is
no intermediate representation of our own.

Some constructs the `Expr` AST collapses are mapped to a default:
- `a ? b : c` parses identically to an `if`, so it becomes `JuliaIf` (never `JuliaTernary`).
- `begin … end` parses to a block, so it becomes `JuliaBlock` (never `JuliaBegin`).

Constructs with no node in the domain (short-circuit `&&`/`||`, `where`, keyword
args, splats, broadcast, string interpolation) raise a
clear error rather than being silently dropped.
"""
module JuliaParserModule

import ..JuliaModule: JuliaIdentifier, JuliaInteger, JuliaFloat, JuliaString, JuliaBool,
    JuliaNothing, JuliaSymbol, JuliaChar, JuliaBinaryOp, JuliaUnaryOp, JuliaCall,
    JuliaMacroCall, JuliaConst, JuliaDocstring,
    JuliaAbstractType, JuliaStruct, JuliaSubtype, JuliaCurly,
    JuliaAnonymousTypeAnnotation, JuliaEmpty,
    JuliaTernary, JuliaIndex, JuliaFieldAccess, JuliaTuple, JuliaArray, JuliaRange,
    JuliaTypeAnnotation, JuliaAssignment, JuliaFor, JuliaForIterator, JuliaWhile,
    JuliaReturn, JuliaBreak, JuliaContinue, JuliaTry, JuliaBegin, JuliaIf, JuliaFunction,
    JuliaBlock, JuliaUsing, JuliaLambda, JuliaModuleDef, JuliaDocument
export juliaparse, juliaparse_file

# ── Operator classification ───────────────────────────────────────────────────
# Matches the operators the printer (`_julia_operator_string` / `JuliaToSyntax`)
# knows how to render. Anything outside these sets falls through to `JuliaCall`,
# which is lossless for display.

const BINARY_OPERATORS = Set{Symbol}([
    :+, :-, :*, :/, :(==), :(!=), :(<), :(>), :(<=), :(>=),
    :(===), :(!==)])

const UNARY_OPERATORS = Set{Symbol}([:-, :!, :~])

const COMPOUND_ASSIGNMENTS = Set{Symbol}([:(+=), :(-=), :(*=), :(/=)])

# ── Entry points ──────────────────────────────────────────────────────────────

"""
    juliaparse(text::AbstractString) -> JuliaDocument

Parse a Julia source string into a `JuliaDocument` tree.

Top-level source with several statements becomes a `JuliaBlock`; a single
expression is returned bare.
"""
function juliaparse(text::AbstractString)
    parsed = Meta.parseall(String(text))
    # `parseall` always wraps in `Expr(:toplevel, …)` interleaved with
    # `LineNumberNode`s. Flatten: one real statement → bare, otherwise a block.
    stmts = _convert_statements(parsed.args)
    length(stmts) == 1 && return stmts[1]
    return JuliaBlock(stmts)
end

"""
    juliaparse_file(path::AbstractString) -> JuliaDocument

Read a Julia source file from disk and parse it into a `JuliaDocument` tree.
"""
function juliaparse_file(path::AbstractString)
    juliaparse(read(path, String))
end

# ── Core recursive conversion ─────────────────────────────────────────────────

# Convert a list of raw `Expr.args`, dropping line-number bookkeeping.
function _convert_statements(args)
    JuliaDocument[convert_expr(a) for a in args if !(a isa LineNumberNode)]
end

"""
    convert_expr(x) -> JuliaDocument

The single recursive pass: turn one node of Julia's native AST (an `Expr`, a
literal, a `Symbol`, or a `QuoteNode`) directly into a `JuliaDocument`.
"""
function convert_expr(x)
    # ── Leaves ────────────────────────────────────────────────────────────────
    x === nothing && return JuliaNothing()
    x isa Bool && return JuliaBool(x)            # before Integer: Bool <: Integer
    x isa Integer && return JuliaInteger(Int(x))
    x isa Real && return JuliaFloat(Float64(x))
    x isa AbstractString && return JuliaString(String(x))
    x isa Char && return JuliaChar(x)
    # `nothing` in source parses to the *symbol* `:nothing`, not the value.
    x === :nothing && return JuliaNothing()
    x isa Symbol && return JuliaIdentifier(String(x))
    x isa QuoteNode && return _convert_quote(x.value)

    x isa Expr || error("unsupported Julia node: $(typeof(x))")
    return _convert_head(Val(x.head), x)
end

# `:foo` reaches us as `QuoteNode(:foo)`; `:(a + b)` as `QuoteNode(Expr(...))`.
# Only plain symbol quotes map to `JuliaSymbol`.
function _convert_quote(v)
    v isa Symbol && return JuliaSymbol(String(v))
    error("unsupported quoted Julia construct: $(typeof(v))")
end

# Dispatch on the `Expr` head. Default arm raises a clear error.
_convert_head(::Val{H}, x::Expr) where {H} =
    error("unsupported Julia construct: $(repr(x.head))")

# ── Calls: range / binary / unary / general ──────────────────────────────────

function _convert_head(::Val{:call}, x::Expr)
    callee = x.args[1]
    # Keyword arguments arrive as a leading `Expr(:parameters, kw…)` (the args
    # after `;`). Flatten them into the argument list as `key = value`
    # assignments — `f(a; k=v)` and `f(a, k=v)` are equivalent Julia. Emit the
    # positional arguments first, then the keywords, so the rendering reads
    # naturally (`f(editor, title = …)`), regardless of AST order.
    positional = Any[]
    keywords   = Any[]
    for a in x.args[2:end]
        if a isa Expr && a.head === :parameters
            append!(keywords, a.args)
        else
            push!(positional, a)
        end
    end
    args = vcat(positional, keywords)
    if callee === :(:)
        if length(args) == 2
            return JuliaRange(convert_expr(args[1]), convert_expr(args[2]))
        elseif length(args) == 3
            return JuliaRange(convert_expr(args[1]), convert_expr(args[2]), convert_expr(args[3]))
        end
    end
    if callee isa Symbol
        if length(args) == 2 && callee in BINARY_OPERATORS
            return JuliaBinaryOp(callee, convert_expr(args[1]), convert_expr(args[2]))
        elseif length(args) == 1 && callee in UNARY_OPERATORS
            return JuliaUnaryOp(callee, convert_expr(args[1]))
        end
    end
    return JuliaCall(convert_expr(callee), JuliaDocument[convert_expr(a) for a in args])
end

# ── Macrocall ────────────────────────────────────────────────────────────────
# `Expr(:macrocall, name, lineinfo, args...)` — the name may be a bare
# `Symbol` (`@show`), a `GlobalRef` (`Core.@doc`), or a dotted path
# `Expr(:., mod, QuoteNode(:@name))`. `x.args[2]` is a LineNumberNode
# the macro-expander uses; skip it and any interleaved LineNumberNodes
# in the remainder.
function _convert_head(::Val{:macrocall}, x::Expr)
    name_expr = x.args[1]
    name = _macro_name_string(name_expr)
    rest = length(x.args) >= 2 ? x.args[3:end] : Any[]
    # Docstrings are the surface form of Julia; the parser desugars
    # `"""text""" def` into `Core.@doc "text" def`. Lift it back to a
    # `JuliaDocstring` so the render is a docstring, not a macrocall.
    if _is_doc_macro(name)
        real_args = Any[a for a in rest if !(a isa LineNumberNode)]
        if length(real_args) == 2 && real_args[1] isa AbstractString
            return JuliaDocstring(String(real_args[1]), convert_expr(real_args[2]))
        end
    end
    args = JuliaDocument[convert_expr(a) for a in rest if !(a isa LineNumberNode)]
    return JuliaMacroCall(name, args)
end

# `@doc` written directly, or the fully-qualified `Core.@doc` the
# parser emits when it desugars a `"""..."""` docstring. Match both.
_is_doc_macro(name::AbstractString) =
    name == "@doc" || name == "Core.@doc" || endswith(name, ".@doc")

_macro_name_string(s::Symbol) = String(s)
_macro_name_string(g::GlobalRef) = string(g.mod, ".", g.name)
function _macro_name_string(x::Expr)
    # A dotted macro name like `Core.@doc` parses as
    # Expr(:., :Core, QuoteNode(:var"@doc")). Best-effort:
    # concat the segments so the printer round-trips.
    x.head === :. || error("unsupported macro name: $(repr(x))")
    left  = _macro_name_string(x.args[1])
    right = x.args[2] isa QuoteNode ? _macro_name_string(x.args[2].value) : string(x.args[2])
    string(left, ".", right)
end
_macro_name_string(x) = string(x)

# ── const ─────────────────────────────────────────────────────────────────────
# `const NAME = VALUE` parses to `Expr(:const, Expr(:(=), NAME, VALUE))`.
_convert_head(::Val{:const}, x::Expr) = JuliaConst(convert_expr(x.args[1]))

# ── Type declarations ────────────────────────────────────────────────────────

# `abstract type Name end` parses to `Expr(:abstract, Name)`.
# `abstract type Name <: Super end` parses to
# `Expr(:abstract, Expr(:<:, Name, Super))`.
_convert_head(::Val{:abstract}, x::Expr) = JuliaAbstractType(convert_expr(x.args[1]))

# `struct Name … end`         → `Expr(:struct, false, header, body)`.
# `mutable struct Name … end` → `Expr(:struct, true,  header, body)`.
function _convert_head(::Val{:struct}, x::Expr)
    mutable = x.args[1]::Bool
    header  = convert_expr(x.args[2])
    body    = convert_expr(x.args[3])
    JuliaStruct(mutable, header, body)
end

# `module Name … end` → `Expr(:module, true, name, body)`;
# `baremodule` sets the flag false (the flag is "include the standard preamble",
# so a bare module is `false`).
function _convert_head(::Val{:module}, x::Expr)
    standard = x.args[1]::Bool
    name = x.args[2]
    name isa Symbol || error("unsupported module name: $(repr(name))")
    JuliaModuleDef(String(name), convert_expr(x.args[3]), !standard)
end

# `A <: B` — outside a type header this could be a runtime test, but
# most sightings are in headers. Kept as a dedicated document type.
_convert_head(::Val{:<:}, x::Expr) =
    JuliaSubtype(convert_expr(x.args[1]), convert_expr(x.args[2]))

# Short-circuit operators — Julia's parser emits `&&`/`||` as their
# own heads rather than as `Expr(:call, :&&, …)`, so a generic binary
# routing does not catch them. Both render as ordinary binary ops.
_convert_head(::Val{:&&}, x::Expr) =
    JuliaBinaryOp(:&&, convert_expr(x.args[1]), convert_expr(x.args[2]))
_convert_head(::Val{:||}, x::Expr) =
    JuliaBinaryOp(:||, convert_expr(x.args[1]), convert_expr(x.args[2]))

# `Foo{T, S}` — parametric type. The head is `:curly`, args are the
# callee (a `JuliaIdentifier`) followed by the parameter expressions.
function _convert_head(::Val{:curly}, x::Expr)
    callee = convert_expr(x.args[1])
    params = JuliaDocument[convert_expr(a) for a in x.args[2:end]]
    JuliaCurly(callee, params)
end

# ── Assignment (plain and compound) ──────────────────────────────────────────

_convert_head(::Val{:(=)}, x::Expr) =
    JuliaAssignment(:(=), convert_expr(x.args[1]), convert_expr(x.args[2]))

for op in (:(+=), :(-=), :(*=), :(/=))
    @eval _convert_head(::Val{$(QuoteNode(op))}, x::Expr) =
        JuliaAssignment($(QuoteNode(op)), convert_expr(x.args[1]), convert_expr(x.args[2]))
end

# A keyword argument `k = v` (inside a call) is structurally a plain assignment.
_convert_head(::Val{:kw}, x::Expr) =
    JuliaAssignment(:(=), convert_expr(x.args[1]), convert_expr(x.args[2]))

# ── using / import ───────────────────────────────────────────────────────────
# `using A.B`        → Expr(:using, Expr(:., :A, :B))
# `using A, B`       → Expr(:using, Expr(:., :A), Expr(:., :B))
# `import A: x, y`   → Expr(:import, Expr(:(:), Expr(:., :A), Expr(:., :x), …))
# The spec is a module *path*, so render it straight to a string rather than a
# nested expression tree.
function _module_path_string(e)
    if e isa Expr && e.head === :.
        return join(string.(e.args), ".")
    elseif e isa Expr && e.head === :(:)
        head  = _module_path_string(e.args[1])
        names = join((_module_path_string(a) for a in e.args[2:end]), ", ")
        return string(head, ": ", names)
    else
        return string(e)
    end
end

_convert_head(::Val{:using}, x::Expr) =
    JuliaUsing(:using, join((_module_path_string(a) for a in x.args), ", "))
_convert_head(::Val{:import}, x::Expr) =
    JuliaUsing(:import, join((_module_path_string(a) for a in x.args), ", "))

# Anonymous function `args -> body`. `args` is a single symbol (`x -> …`), a
# tuple (`(x, y) -> …`, `() -> …`), and the body is usually a `:block` wrapping
# one expression.
function _convert_head(::Val{:->}, x::Expr)
    a = x.args[1]
    params = if a isa Expr && a.head === :tuple
        Any[p for p in a.args]
    elseif a isa Expr && a.head === :block
        Any[p for p in a.args if !(p isa LineNumberNode)]
    else
        Any[a]
    end
    b = x.args[2]
    body = if b isa Expr && b.head === :block
        stmts = _convert_statements(b.args)
        length(stmts) == 1 ? stmts[1] : JuliaBlock(stmts)
    else
        convert_expr(b)
    end
    JuliaLambda(JuliaDocument[convert_expr(p) for p in params], body)
end

# ── Compound expressions ─────────────────────────────────────────────────────

_convert_head(::Val{:block}, x::Expr) = JuliaBlock(_convert_statements(x.args))

# `a; b` written on ONE line parses to a `:toplevel` *nested* inside the outer
# one, so a semicolon-separated statement group reaches here instead of being
# flattened by `juliaparse`'s own top-level handling. It means exactly what a
# `:block` means — a sequence of statements — and converts the same way.
_convert_head(::Val{:toplevel}, x::Expr) = JuliaBlock(_convert_statements(x.args))

_convert_head(::Val{:tuple}, x::Expr) =
    JuliaTuple(JuliaDocument[convert_expr(e) for e in x.args])

_convert_head(::Val{:vect}, x::Expr) =
    JuliaArray(JuliaDocument[convert_expr(e) for e in x.args])

_convert_head(::Val{:ref}, x::Expr) =
    JuliaIndex(convert_expr(x.args[1]),
               JuliaDocument[convert_expr(i) for i in x.args[2:end]])

function _convert_head(::Val{:(::)}, x::Expr)
    # `x::T` parses as `Expr(:(::), x, T)` — the two-argument form.
    # `::T` on its own (a dispatch pin like `foo(::Type{Bar}) = …`)
    # parses as `Expr(:(::), T)` — no value, only the type.
    if length(x.args) == 1
        JuliaAnonymousTypeAnnotation(convert_expr(x.args[1]))
    else
        JuliaTypeAnnotation(convert_expr(x.args[1]), convert_expr(x.args[2]))
    end
end

function _convert_head(::Val{:.}, x::Expr)
    field = x.args[2]
    field isa QuoteNode || error("unsupported field access: $(repr(field))")
    return JuliaFieldAccess(convert_expr(x.args[1]), JuliaIdentifier(String(field.value)))
end

# ── Control flow ─────────────────────────────────────────────────────────────

function _convert_head(::Val{:if}, x::Expr)
    cond = convert_expr(x.args[1])
    # Julia's parser distinguishes `if x; y; end` (statement form,
    # then/else are `:block` wrappers) from `x ? y : z` (ternary,
    # then/else are the raw expressions). Route the ternary form to
    # `JuliaTernary` so the printer keeps it on one line, and leave
    # the statement form on `JuliaIf` for the block layout.
    then_arg = x.args[2]
    is_stmt_form = then_arg isa Expr && then_arg.head === :block
    if !is_stmt_form && length(x.args) >= 3 &&
       !(x.args[3] isa Expr && x.args[3].head === :block)
        return JuliaTernary(cond, convert_expr(then_arg), convert_expr(x.args[3]))
    end
    then_branch = convert_expr(then_arg)
    # An `if …end` with no else parses with 2 args. Use a
    # `JuliaEmpty` placeholder — it renders to nothing at all, so
    # neither the `nothing` literal (from `JuliaNothing`) nor a
    # phantom blank line (from an empty `JuliaBlock`'s trailing
    # line-chrome) appears before the closing `end`.
    else_branch = length(x.args) >= 3 ? convert_expr(x.args[3]) : JuliaEmpty()
    return JuliaIf(cond, then_branch, else_branch)
end

# `elseif` shares the `if` SHAPE but Julia's parser wraps the
# elseif's CONDITION in an `Expr(:block, LineNumberNode, cond)`
# (mirroring the block-wrapping it does for the branch bodies).
# Strip that wrapper so the condition renders as a normal expression
# instead of a JuliaBlock.
function _convert_head(::Val{:elseif}, x::Expr)
    unwrapped = Expr(:if, _unwrap_elseif_cond(x.args[1]), x.args[2:end]...)
    _convert_head(Val(:if), unwrapped)
end

# `Expr(:block, [LineNumberNode,] cond)` → `cond`. Anything else
# (including a bare `Symbol` from a hand-crafted Expr) passes
# through unchanged.
function _unwrap_elseif_cond(cond)
    cond isa Expr && cond.head === :block || return cond
    real = [a for a in cond.args if !(a isa LineNumberNode)]
    length(real) == 1 || return cond   # unexpected shape; hand back verbatim
    real[1]
end

function _convert_head(::Val{:while}, x::Expr)
    return JuliaWhile(convert_expr(x.args[1]), convert_expr(x.args[2]))
end

function _convert_head(::Val{:for}, x::Expr)
    spec = x.args[1]
    iterators = _convert_for_iterators(spec)
    return JuliaFor(iterators, convert_expr(x.args[2]))
end

# `for v in it` → spec is `Expr(:(=), v, it)`.
# `for a in x, b in y` → spec is `Expr(:block, Expr(:(=), …), Expr(:(=), …))`.
function _convert_for_iterators(spec)
    if spec isa Expr && spec.head === :block
        return JuliaForIterator[_convert_for_clause(c) for c in spec.args if !(c isa LineNumberNode)]
    end
    return JuliaForIterator[_convert_for_clause(spec)]
end

function _convert_for_clause(clause)
    (clause isa Expr && clause.head === :(=)) ||
        error("unsupported for-loop iterator: $(repr(clause))")
    return JuliaForIterator(convert_expr(clause.args[1]), convert_expr(clause.args[2]))
end

function _convert_head(::Val{:return}, x::Expr)
    # A bare `return` parses to `Expr(:return, nothing)`.
    isempty(x.args) && return JuliaReturn()
    x.args[1] === nothing && return JuliaReturn()
    return JuliaReturn(convert_expr(x.args[1]))
end

_convert_head(::Val{:break}, ::Expr) = JuliaBreak()
_convert_head(::Val{:continue}, ::Expr) = JuliaContinue()

function _convert_head(::Val{:try}, x::Expr)
    # Expr(:try, body, catch_var, catch_body[, finally_body])
    body = convert_expr(x.args[1])
    catch_var = x.args[2] === false ? nothing : convert_expr(x.args[2])
    catch_branch = _try_branch(x.args[3])
    finally_branch = length(x.args) >= 4 ? _try_branch(x.args[4]) : nothing
    return JuliaTry(body, catch_var, catch_branch, finally_branch)
end

# An absent catch/finally body is `false` in the AST.
_try_branch(b) = b === false ? nothing : convert_expr(b)

# ── Definitions ──────────────────────────────────────────────────────────────

function _convert_head(::Val{:function}, x::Expr)
    sig = x.args[1]
    (sig isa Expr && sig.head === :call) ||
        error("unsupported function signature: $(repr(sig))")
    name = convert_expr(sig.args[1])
    params = JuliaDocument[convert_expr(p) for p in sig.args[2:end]]
    body = convert_expr(x.args[2])
    return JuliaFunction(name, params, body)
end

end # module
