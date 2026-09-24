# Fragment of `JuliaModule`.
#
# Parser for Julia source code. Converts Julia source text into a `JuliaDocument`
# tree from `JuliaModule`.
#
# Provides:
# - `parse_julia(text)` — parse a Julia string into a `JuliaDocument`
# - `parse_julia_file(path)` — read and parse a `.jl` file from disk
#
# The parser delegates lexing and grammar to Julia's own parser (`Meta.parseall`,
# backed by `JuliaSyntax`). A single recursive pass (`convert_expr`) walks the
# native `Expr`/literal tree and builds `JuliaDocument` nodes directly — there is
# no intermediate representation of our own.
#
# Some constructs the `Expr` AST collapses are mapped to a default:
# - `a ? b : c` parses identically to an `if`, so it becomes `JuliaIf` (never `JuliaTernary`).
# - `begin … end` parses to a block, so it becomes `JuliaBlock` (never `JuliaBegin`).
#
# A construct with no node in the domain raises a clear error rather than
# being silently dropped.
# ── Operator classification ───────────────────────────────────────────────────
# Matches the operators the printer (`_julia_operator_string` / `JuliaToSyntax`)
# knows how to render. Anything outside these sets falls through to `JuliaCall`,
# which is lossless for display.

const BINARY_OPERATORS = Set{Symbol}([
    :+, :-, :*, :/, :^, :(==), :(!=), :(<), :(>), :(<=), :(>=),
    :(===), :(!==)])

const UNARY_OPERATORS = Set{Symbol}([:-, :!, :~])

const COMPOUND_ASSIGNMENTS = Set{Symbol}([:(+=), :(-=), :(*=), :(/=)])

# ── Entry points ──────────────────────────────────────────────────────────────

"""
    parse_julia(text::AbstractString) -> JuliaDocument

Parse a Julia source string into a `JuliaDocument` tree.

Top-level source with several statements becomes a `JuliaBlock`; a single
expression is returned bare.
"""
function parse_julia(text::AbstractString)
    parsed = Meta.parseall(String(text))
    # `parseall` always wraps in `Expr(:toplevel, …)` interleaved with
    # `LineNumberNode`s. Flatten: one real statement → bare, otherwise a block.
    stmts = _convert_statements(parsed.args)
    length(stmts) == 1 && return stmts[1]
    return JuliaBlock(stmts)
end

"""
    parse_julia_file(path::AbstractString) -> JuliaDocument

Read a Julia source file from disk and parse it into a `JuliaDocument` tree.
"""
function parse_julia_file(path::AbstractString)
    parse_julia(read(path, String))
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
    # The keyword arguments after `;` arrive as a leading `Expr(:parameters, kw…)`,
    # and they are kept apart, so the call prints the `;` its code wrote. A range,
    # an operator and a unary operator take no keywords.
    positional = Any[]
    keywords   = Any[]
    for a in x.args[2:end]
        if a isa Expr && a.head === :parameters
            append!(keywords, a.args)
        else
            push!(positional, a)
        end
    end
    args = isempty(keywords) ? positional : Any[]
    if callee === :(:)
        if length(args) == 2
            return JuliaRange(convert_expr(args[1]), convert_expr(args[2]))
        elseif length(args) == 3
            return JuliaRange(convert_expr(args[1]), convert_expr(args[2]), convert_expr(args[3]))
        end
    end
    if callee isa Symbol
        if length(args) == 2 && callee in BINARY_OPERATORS
            return JuliaBinaryOperation(callee, convert_expr(args[1]), convert_expr(args[2]))
        elseif length(args) == 1 && callee in UNARY_OPERATORS
            return JuliaUnaryOperation(callee, convert_expr(args[1]))
        end
    end
    return JuliaCall(convert_expr(callee), JuliaDocument[convert_expr(a) for a in positional],
                     JuliaDocument[convert_expr(k) for k in keywords])
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
    JuliaModuleDefinition(String(name), convert_expr(x.args[3]), !standard)
end

# `A <: B` — outside a type header this could be a runtime test, but
# most sightings are in headers. Kept as a dedicated document type.
#
# The ONE-argument form is the anonymous bound `Vector{<:Real}`, which is the
# same operator with nothing on its left; `JuliaEmpty` on the left is what says
# so, and the printer drops the space it would otherwise leave.
_convert_head(::Val{:<:}, x::Expr) =
    length(x.args) == 1 ? JuliaSubtype(JuliaEmpty(), convert_expr(x.args[1])) :
                          JuliaSubtype(convert_expr(x.args[1]), convert_expr(x.args[2]))

# Short-circuit operators — Julia's parser emits `&&`/`||` as their
# own heads rather than as `Expr(:call, :&&, …)`, so a generic binary
# routing does not catch them. Both render as ordinary binary ops.
_convert_head(::Val{:&&}, x::Expr) =
    JuliaBinaryOperation(:&&, convert_expr(x.args[1]), convert_expr(x.args[2]))
_convert_head(::Val{:||}, x::Expr) =
    JuliaBinaryOperation(:||, convert_expr(x.args[1]), convert_expr(x.args[2]))

# `Foo{T, S}` — parametric type. The head is `:curly`, args are the
# callee (a `JuliaIdentifier`) followed by the parameter expressions.
function _convert_head(::Val{:curly}, x::Expr)
    callee = convert_expr(x.args[1])
    params = JuliaDocument[convert_expr(a) for a in x.args[2:end]]
    JuliaCurly(callee, params)
end

# ── Assignment (plain and compound) ──────────────────────────────────────────

function _convert_head(::Val{:(=)}, x::Expr)
    target = x.args[1]
    value = x.args[2]
    # Julia wraps the body of a short function definition in a block, as in
    # `f(x) = x` becoming `f(x) = begin x end`. A body of one statement is
    # unwrapped, so the definition prints on one line, as it was written. The
    # signature is a call, a call with `where`, or a call with a return type; a
    # plain assignment keeps its block.
    if target isa Expr && target.head in (:call, :where, :(::)) &&
       value isa Expr && value.head === :block
        statements = [s for s in value.args if !(s isa LineNumberNode)]
        length(statements) == 1 && (value = statements[1])
    end
    JuliaAssignment(:(=), convert_expr(target), convert_expr(value))
end

for op in (:(+=), :(-=), :(*=), :(/=), :(%=), :(^=), :(÷=),
           :(|=), :(&=), :(⊻=), :(<<=), :(>>=))
    @eval _convert_head(::Val{$(QuoteNode(op))}, x::Expr) =
        JuliaAssignment($(QuoteNode(op)), convert_expr(x.args[1]), convert_expr(x.args[2]))
end

# A keyword argument `k = v` (inside a call) is structurally a plain assignment.
_convert_head(::Val{:kw}, x::Expr) =
    JuliaAssignment(:(=), convert_expr(x.args[1]), convert_expr(x.args[2]))

# ── using / import / export ──────────────────────────────────────────────────
# `using A.B`        → Expr(:using, Expr(:., :A, :B))
# `using A, B`       → Expr(:using, Expr(:., :A), Expr(:., :B))
# `import A: x, y`   → Expr(:import, Expr(:(:), Expr(:., :A), Expr(:., :x), …))
# `export a, b`      → Expr(:export, :a, :b)
# All three are a keyword followed by a flat spec, which is why one node type
# carries them.
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
_convert_head(::Val{:export}, x::Expr) =
    JuliaUsing(:export, join((_module_path_string(a) for a in x.args), ", "))
_convert_head(::Val{:public}, x::Expr) =
    JuliaUsing(:public, join((_module_path_string(a) for a in x.args), ", "))

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
    JuliaLambda(JuliaDocument[convert_expr(p) for p in params], body,
                a isa Expr && a.head in (:tuple, :block))
end

# ── Compound expressions ─────────────────────────────────────────────────────

_convert_head(::Val{:block}, x::Expr) = JuliaBlock(_convert_statements(x.args))

# `a; b` written on ONE line parses to a `:toplevel` *nested* inside the outer
# one, so a semicolon-separated statement group reaches here instead of being
# flattened by `parse_julia`'s own top-level handling. It means exactly what a
# `:block` means — a sequence of statements — and converts the same way.
_convert_head(::Val{:toplevel}, x::Expr) = JuliaBlock(_convert_statements(x.args))

function _convert_head(::Val{:tuple}, x::Expr)
    # `(; a = 1)` puts its entries in a `:parameters` child; `(a = 1,)` writes
    # them as assignments. Either way it is a named tuple, not a positional one.
    if length(x.args) == 1 && x.args[1] isa Expr && x.args[1].head === :parameters
        return convert_expr(x.args[1])
    end
    if !isempty(x.args) && all(a -> a isa Expr && (a.head === :(=) || a.head === :kw), x.args)
        return JuliaNamedTuple(JuliaDocument[convert_expr(e) for e in x.args])
    end
    JuliaTuple(JuliaDocument[convert_expr(e) for e in x.args])
end

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

# One head, two meanings: `a.b` names a field, `f.(x)` broadcasts a call. The
# second argument tells them apart — a name, or the argument tuple.
function _convert_head(::Val{:.}, x::Expr)
    field = x.args[2]
    if field isa Expr && field.head === :tuple
        return JuliaBroadcast(convert_expr(x.args[1]),
                              JuliaDocument[convert_expr(a) for a in field.args])
    end
    field isa QuoteNode || error("unsupported field access: $(repr(field))")
    return JuliaFieldAccess(convert_expr(x.args[1]), JuliaIdentifier(String(field.value)))
end

# ── The rest of ordinary Julia ───────────────────────────────────────────────

_convert_head(::Val{:...}, x::Expr) = JuliaSplat(convert_expr(x.args[1]))

# `a < b < c` → Expr(:comparison, a, :<, b, :<, c). Folded left into ordinary
# binary operations: it prints back exactly as written, which is what a syntax
# model owes. (Julia's own meaning — `a < b && b < c` — differs from the folded
# form's, so this is a rendering, not a semantics.)
function _convert_head(::Val{:comparison}, x::Expr)
    result = convert_expr(x.args[1])
    for index in 2:2:(length(x.args) - 1)
        result = JuliaBinaryOperation(x.args[index], result, convert_expr(x.args[index + 1]))
    end
    result
end

# `"a $(x) b"` -> Expr(:string, "a ", :x, " b"). A literal chunk stays a string;
# everything else is an expression to be written back inside `$(…)`.
_convert_head(::Val{:string}, x::Expr) =
    JuliaStringInterpolation(JuliaDocument[_convert_string_part(part) for part in x.args])

# Inside the quotes a literal run is text, not a string literal — it has no
# quotes of its own — and everything else is written back as an interpolation.
_convert_string_part(part::AbstractString) = JuliaStringChunk(String(part))
_convert_string_part(part) = JuliaInterpolation(convert_expr(part))

# `f(x) where {T}` → Expr(:where, body, T…). Nested `where`s flatten, because
# `where {T} where {S}` and `where {T, S}` mean the same thing and one of them
# reads.
function _convert_head(::Val{:where}, x::Expr)
    body = x.args[1]
    parameters = Any[x.args[2:end]...]
    while body isa Expr && body.head === :where
        prepend!(parameters, body.args[2:end])
        body = body.args[1]
    end
    JuliaWhere(convert_expr(body),
               JuliaDocument[convert_expr(p) for p in parameters])
end

# `[f(i) for i in r]` → Expr(:comprehension, Expr(:generator, f(i), i = r)).
_convert_head(::Val{:comprehension}, x::Expr) = _comprehension(x.args[1], JuliaEmpty(), true)
_convert_head(::Val{:typed_comprehension}, x::Expr) =
    _comprehension(x.args[2], convert_expr(x.args[1]), true)
_convert_head(::Val{:generator}, x::Expr) = _comprehension(x, JuliaEmpty(), false)

# The generator inside: its first argument is the expression, the rest are the
# `var = iterable` clauses a `for` loop writes the same way.
function _comprehension(generator, element_type, brackets::Bool)
    (generator isa Expr && generator.head === :generator) ||
        error("unsupported comprehension body: $(repr(generator))")
    spec = generator.args[2]
    # `[e for i in r if p]` puts the clauses under a `:filter` whose first
    # argument is the condition.
    condition = JuliaEmpty()
    if spec isa Expr && spec.head === :filter
        condition = convert_expr(spec.args[1])
        spec = length(spec.args) == 2 ? spec.args[2] : Expr(:block, spec.args[2:end]...)
    end
    JuliaComprehension(convert_expr(generator.args[1]),
                       _convert_for_iterators(spec),
                       element_type, brackets, condition)
end

# `map(xs) do x … end` → Expr(:do, call, Expr(:->, tuple, body)). The lambda is
# taken apart here because `do` writes its parameters without an arrow.
function _convert_head(::Val{:do}, x::Expr)
    lambda = x.args[2]
    (lambda isa Expr && lambda.head === :->) ||
        error("unsupported do block: $(repr(lambda))")
    spec = lambda.args[1]
    parameters = spec isa Expr && spec.head === :tuple ? spec.args : Any[spec]
    JuliaDo(convert_expr(x.args[1]),
            JuliaDocument[convert_expr(a) for a in parameters],
            convert_expr(lambda.args[2]))
end

# `let x = 1, y = 2; … end` → Expr(:let, bindings, body). One binding is the
# assignment itself; several are a block of them; none is an empty block.
function _convert_head(::Val{:let}, x::Expr)
    spec = x.args[1]
    bindings = if spec isa Expr && spec.head === :block
        JuliaDocument[convert_expr(b) for b in spec.args if !(b isa LineNumberNode)]
    elseif spec === nothing || (spec isa Expr && isempty(spec.args) && spec.head === :block)
        JuliaDocument[]
    else
        JuliaDocument[convert_expr(spec)]
    end
    JuliaLet(bindings, convert_expr(x.args[2]))
end

# `(; a = 1)` → Expr(:tuple, Expr(:parameters, Expr(:kw, …)…)); `(a = 1,)` →
# Expr(:tuple, Expr(:(=), …)). Both are named tuples; the first is the form
# with the semicolon.
_convert_head(::Val{:parameters}, x::Expr) =
    JuliaNamedTuple(JuliaDocument[convert_expr(e) for e in x.args])

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
    # `function f end` — a name with no method, and no parameter list at all.
    length(x.args) == 1 && return JuliaFunctionDeclaration(convert_expr(x.args[1]))
    sig = x.args[1]
    result_type = JuliaEmpty()
    type_parameters = JuliaDocument[]
    # `function f(x) where {T}` — the signature is the call wrapped in a where,
    # possibly more than once.
    while sig isa Expr && sig.head === :where
        append!(type_parameters, JuliaDocument[convert_expr(v) for v in sig.args[2:end]])
        sig = sig.args[1]
    end
    # `function f(x)::T` — the signature is the call wrapped in an annotation.
    if sig isa Expr && sig.head === :(::) && length(sig.args) == 2
        result_type = convert_expr(sig.args[2])
        sig = sig.args[1]
    end
    # `function (x) … end` — anonymous, so it is a lambda written the long way.
    if sig isa Expr && sig.head === :tuple
        return JuliaLambda(JuliaDocument[convert_expr(p) for p in sig.args],
                           convert_expr(x.args[2]))
    end
    (sig isa Expr && sig.head === :call) ||
        error("unsupported function signature: $(repr(sig))")
    name = convert_expr(sig.args[1])
    params = JuliaDocument[convert_expr(p) for p in sig.args[2:end]]
    body = convert_expr(x.args[2])
    where_clause = isempty(type_parameters) ? JuliaEmpty() :
                                            JuliaWhereParameters(type_parameters)
    return JuliaFunction(name, params, body, result_type, where_clause)
end
