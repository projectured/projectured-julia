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
args, splats, broadcast, string interpolation, structs, macros, modules) raise a
clear error rather than being silently dropped.
"""
module JuliaParserModule

import ..JuliaModule: JuliaIdentifier, JuliaInteger, JuliaFloat, JuliaString, JuliaBool,
    JuliaNothing, JuliaSymbol, JuliaChar, JuliaBinaryOp, JuliaUnaryOp, JuliaCall,
    JuliaTernary, JuliaIndex, JuliaFieldAccess, JuliaTuple, JuliaArray, JuliaRange,
    JuliaTypeAnnotation, JuliaAssignment, JuliaFor, JuliaForIterator, JuliaWhile,
    JuliaReturn, JuliaBreak, JuliaContinue, JuliaTry, JuliaBegin, JuliaIf, JuliaFunction,
    JuliaBlock, JuliaUsing, JuliaDocument
export juliaparse, juliaparse_file

# ── Operator classification ───────────────────────────────────────────────────
# Matches the operators the printer (`_julia_operator_string` / `JuliaToSyntax`)
# knows how to render. Anything outside these sets falls through to `JuliaCall`,
# which is lossless for display.

const BINARY_OPERATORS = Set{Symbol}([
    :+, :-, :*, :/, :(==), :(!=), :(<), :(>), :(<=), :(>=)])

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

# ── Compound expressions ─────────────────────────────────────────────────────

_convert_head(::Val{:block}, x::Expr) = JuliaBlock(_convert_statements(x.args))

_convert_head(::Val{:tuple}, x::Expr) =
    JuliaTuple(JuliaDocument[convert_expr(e) for e in x.args])

_convert_head(::Val{:vect}, x::Expr) =
    JuliaArray(JuliaDocument[convert_expr(e) for e in x.args])

_convert_head(::Val{:ref}, x::Expr) =
    JuliaIndex(convert_expr(x.args[1]),
               JuliaDocument[convert_expr(i) for i in x.args[2:end]])

_convert_head(::Val{:(::)}, x::Expr) =
    JuliaTypeAnnotation(convert_expr(x.args[1]), convert_expr(x.args[2]))

function _convert_head(::Val{:.}, x::Expr)
    field = x.args[2]
    field isa QuoteNode || error("unsupported field access: $(repr(field))")
    return JuliaFieldAccess(convert_expr(x.args[1]), JuliaIdentifier(String(field.value)))
end

# ── Control flow ─────────────────────────────────────────────────────────────

function _convert_head(::Val{:if}, x::Expr)
    cond = convert_expr(x.args[1])
    then_branch = convert_expr(x.args[2])
    else_branch = length(x.args) >= 3 ? convert_expr(x.args[3]) : JuliaNothing()
    return JuliaIf(cond, then_branch, else_branch)
end

# `elseif` shares the `if` shape.
_convert_head(::Val{:elseif}, x::Expr) = _convert_head(Val(:if), x)

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
