# Fragment of `ReferenceModule` — the `@reference` / `@step` construction DSL,
# the compact surface syntax for building `ReferencePath`s / `ReferenceStep`s.
# The pattern-matching counterpart is `@reference_case` in
# `ReferenceCase.jl`, its fragment sibling.

# ------------------------------------------------------------
# Parsing for constructor DSL
#
# Rootless forms:
#   address.city
#   items[i].name
#   xs{s:e}
#   config.field(fname)
#   cursor.point(x, y)
#   rendered.proj(p, [0])
#   rendered.proj(p, token[i])
#
# Splicing:
#   ^(expr)              — splice a ReferencePath or ReferenceStep at the front
#   value.^(expr)        — splice at the end of a chain (parses as .^ broadcast)
#   ^(expr).field        — splice followed by more steps
#
# Semantics:
#   - top-level bare symbols in path position are literal field names
#   - inside [expr], field(expr), point(x,y), proj(p, path), arguments are
#     ordinary Julia expressions that get evaluated at runtime
# ------------------------------------------------------------

abstract type BuildStep end

struct BSField <: BuildStep
    nameexpr
end

struct BSIndex <: BuildStep
    idxexpr
end

struct BSPosition <: BuildStep
    idxexpr
end

struct BSRange <: BuildStep
    startexpr
    stopexpr
end

struct BSPathSplice <: BuildStep
    expr
end

# A `.name(args...)` DSL entry whose step type is registered by dispatch on
# `dsl_build_step(::Val{name}, escaped_args...)`. Kernel-owned entries (`.field`,
# `.point`, `.proj`) register in this file; higher packages register their own.
struct BSExtension <: BuildStep
    name::Symbol
    args::Vector{Any}
end

# A first-class type checkpoint step: `f::T` emits the steps of `f` and then a
# TypeReference(T) — "f first then T".
struct BSType <: BuildStep
    typeexpr
end

function _parse_build_path(ex)
    steps = BuildStep[]
    _parse_build_path!(steps, ex)
    return steps
end

function _parse_build_path!(steps::Vector{BuildStep}, ex)
    if ex isa Symbol
        # Path-position symbol => literal field name
        push!(steps, BSField(String(ex)))
        return steps

    elseif ex isa Expr && ex.head == :(::)
        # f::T — emit the steps of `f`, then a TypeReference(T) checkpoint.
        # A leading `::T` (no `f`) emits the checkpoint then the rest of the chain.
        if length(ex.args) == 2
            _parse_build_path!(steps, ex.args[1])
            _build_type_suffix!(steps, ex.args[2])
        else
            _build_leading_type!(steps, ex.args[1])
        end
        return steps

    elseif ex isa Expr && ex.head == :. && ex.args[2] isa QuoteNode
        # a.b
        _parse_build_path!(steps, ex.args[1])
        push!(steps, BSField(String(ex.args[2].value)))
        return steps

    elseif ex isa Expr && ex.head == :ref
        # base[idx] — ElementReference (1-based), or base[i, j] — RangeReference
        if length(ex.args) == 2
            _parse_build_path!(steps, ex.args[1])
            push!(steps, BSIndex(ex.args[2]))
        elseif length(ex.args) == 3
            _parse_build_path!(steps, ex.args[1])
            push!(steps, BSRange(ex.args[2], ex.args[3]))
        else
            error("indexing supports 1 or 2 dimensions in @reference: $ex")
        end
        return steps

    elseif ex isa Expr && ex.head == :curly
        # base{idx} — PositionReference (0-based), or base{s:e} — RangeReference
        length(ex.args) == 2 || error("only one-dimensional position is supported in @reference: $ex")
        _parse_build_path!(steps, ex.args[1])
        push!(steps, _braces_step(ex.args[2], ex))
        return steps

    elseif ex isa Expr && ex.head == :call
        f = ex.args[1]

        if f == :proj
            # Top-level: proj(projection, subpath) — dispatched through the
            # extension seam so the concrete step type can live in the
            # package that owns projections.
            length(ex.args) == 3 || error(".proj(projection, outpath) expects exactly two arguments: $ex")
            push!(steps, BSExtension(:proj, Any[ex.args[2], _parse_build_subpath(ex.args[3])]))
            return steps

        elseif f == :(^)
            # ^(expr) at path position — splice
            length(ex.args) == 2 || error("^(expr) expects exactly one argument: $ex")
            push!(steps, BSPathSplice(ex.args[2]))
            return steps

        elseif f == :.^ && length(ex.args) == 3
            # base.^(expr) — Julia parses `base.^(expr)` as binary broadcast
            # `.^`; we use it as "path-tail splice at the end of the chain"
            _parse_build_path!(steps, ex.args[2])
            push!(steps, BSPathSplice(ex.args[3]))
            return steps

        elseif f isa Expr && f.head == :. && f.args[2] isa QuoteNode
            opname = f.args[2].value
            _parse_build_path!(steps, f.args[1])

            if opname == :field
                length(ex.args) == 2 || error(".field(name) expects exactly one argument")
                push!(steps, BSField(ex.args[2]))
                return steps

            elseif opname == :proj
                length(ex.args) == 3 || error(".proj(projection, outpath) expects exactly two arguments")
                push!(steps, BSExtension(:proj, Any[ex.args[2], _parse_build_subpath(ex.args[3])]))
                return steps

            else
                # Everything else is dispatched through the extension seam so
                # a higher-package step type (e.g. `.point(x, y)` in visual/
                # graphics) can register its own DSL entry at its own site.
                push!(steps, BSExtension(opname, Any[ex.args[2:end]...]))
                return steps
            end
        else
            error("unsupported call form in @reference: $ex")
        end

    elseif ex isa Expr && ex.head == :vect
        # [i] as a relative subpath — ElementReference (1-based), or [i, j] — RangeReference
        if length(ex.args) == 1
            push!(steps, BSIndex(ex.args[1]))
        elseif length(ex.args) == 2
            push!(steps, BSRange(ex.args[1], ex.args[2]))
        else
            error("subpath vector syntax supports 1 or 2 elements in @reference: $ex")
        end
        return steps

    elseif ex isa Expr && ex.head == :braces
        # {i} or {s:e} as a relative subpath
        length(ex.args) == 1 || error("subpath braces syntax supports exactly one element, e.g. {0} or {0:k}: $ex")
        push!(steps, _braces_step(ex.args[1], ex))
        return steps

    else
        error("unsupported @reference syntax: $ex")
    end
end

# `x::T` type suffix: a bare `T` is a checkpoint; a `T{i}` / `T[i]` (which Julia
# parses as a parametric/indexed type) is read as the checkpoint `T` followed by
# a position/range/element step — so `value::Leaf{s:e}` needs no parens.
function _build_type_suffix!(steps::Vector{BuildStep}, T)
    if T isa Expr && T.head == :curly
        push!(steps, BSType(T.args[1]))
        push!(steps, _braces_step(T.args[2], T))
    elseif T isa Expr && T.head == :ref
        push!(steps, BSType(T.args[1]))
        if length(T.args) == 2
            push!(steps, BSIndex(T.args[2]))
        elseif length(T.args) == 3
            push!(steps, BSRange(T.args[2], T.args[3]))
        else
            error("type suffix index supports 1 or 2 dimensions: $T")
        end
    else
        push!(steps, BSType(T))
    end
end

# Leading `::X`: a bare symbol is just the checkpoint; a chain like
# `Node.value{s:e}` (which Julia parses entirely under the `::`) is read as
# checkpoint `Node` followed by the `.value{s:e}` steps — so no parens.
function _build_leading_type!(steps::Vector{BuildStep}, X)
    if X isa Symbol
        push!(steps, BSType(X))
    else
        n = length(steps)
        _parse_build_path!(steps, X)
        root = steps[n + 1]
        (root isa BSField && root.nameexpr isa String) ||
            error("leading ::T must start with a type name: $X")
        steps[n + 1] = BSType(Symbol(root.nameexpr))
    end
end

# Lower the inner expression of `{...}` to either a position or range step.
function _braces_step(inner, ctx)
    if inner isa Expr && inner.head == :call && length(inner.args) == 3 && inner.args[1] == :(:)
        return BSRange(inner.args[2], inner.args[3])
    end
    return BSPosition(inner)
end

function _parse_build_subpath(ex)
    # ^(expr) splices an already-computed ReferencePath directly
    if ex isa Expr && ex.head == :call && ex.args[1] == :(^)
        length(ex.args) == 2 || error("^(expr) expects exactly one argument: $ex")
        return BuildStep[BSPathSplice(ex.args[2])]
    end
    return _parse_build_path(ex)
end

# ------------------------------------------------------------
# Code generation
# ------------------------------------------------------------

function _gen_build_step(step::BSField)
    nameex = step.nameexpr isa String ? QuoteNode(step.nameexpr) : esc(step.nameexpr)
    return :(ReferenceModule.FieldReference(String($nameex)))
end

function _gen_build_step(step::BSIndex)
    return :(ReferenceModule.ElementReference(Int($(esc(step.idxexpr)))))
end

function _gen_build_step(step::BSPosition)
    return :(ReferenceModule.PositionReference(Int($(esc(step.idxexpr)))))
end

function _gen_build_step(step::BSRange)
    return :(ReferenceModule.RangeReference(Int($(esc(step.startexpr))), Int($(esc(step.stopexpr)))))
end

function _gen_build_step(step::BSPathSplice)
    return esc(step.expr)
end

function _gen_build_step(step::BSType)
    return :(ReferenceModule.TypeReference($(esc(step.typeexpr))))
end

# Extension-registered `.name(args...)` DSL entries dispatch through
# `dsl_build_step(::Val{name}, escaped_args...)`. The `.proj` entry is
# special-cased: its second arg is a subpath the parser already parsed
# into a `Vector{BuildStep}`, so we lower it before dispatching.
function _gen_build_step(step::BSExtension)
    args = if step.name === :proj
        Any[esc(step.args[1]), _gen_build_path(step.args[2])]
    else
        Any[esc(a) for a in step.args]
    end
    return dsl_build_step(Val(step.name), args...)
end

"""
    dsl_build_step(::Val{name}, escaped_args...) -> Expr

Return the expression that constructs the step type mapped to `.name(args...)`
in the `@reference` DSL. `escaped_args` are `esc`'d Julia expressions ready
to splice into the returned constructor call. Each package registers a
`::Val{:name}` method for its own step types; the kernel registers
`.point` (moves to visual/graphics in step 5) and `.proj` (moves to
kernel/projection).
"""
function dsl_build_step end

dsl_build_step(::Val{n}, args...) where {n} =
    error("no `dsl_build_step(::Val{$(QuoteNode(n))}, …)` method registered — `.$(n)(…)` is not a known @reference step")

# No kernel-registered `.name(...)` DSL entries — the cross-package step
# types (`.point`, `.proj`, …) register their own `dsl_build_step` at the
# package that owns them. The kernel keeps only the built-in navigation and
# `::T` type-checkpoint syntax.

# Wrap a value so it can stand in as a ReferencePath: pass paths through,
# wrap steps into a one-element path.
_splice(p::ReferenceModule.ReferencePath) = p
_splice(s::ReferenceModule.ReferenceStep) =
    ReferenceModule.ConcreteReferencePath(s, ReferenceModule.EmptyReferencePath())

# Concatenate two paths via the canonical, type-preserving `concat_references`
# (ReferenceModule), so an already-folded spliced sub-path keeps its node types
# even when it is not the last segment (e.g. `^(expr).field`). The `_concat` name
# is kept because the generated code below emits `ReferenceModule._concat`.
const _concat = ReferenceModule.concat_references

# Wrap a built (possibly TypeReference-bearing) path expression in the runtime
# fold pass only when the literal carries a `::T` checkpoint — a plain navigation
# skeleton needs no folding (its node types stay `nothing`, filled later by
# `set_selection!`), so the common case allocates nothing extra.
_maybe_fold(expr, steps) =
    any(s -> s isa BSType, steps) ? :(ReferenceModule.fold_reference_types($expr)) : expr

function _gen_build_path(steps::Vector{BuildStep})
    # No steps → empty path.
    if isempty(steps)
        return :(ReferenceModule.EmptyReferencePath())
    end

    # Fast path: no splices at all.
    if !any(s -> s isa BSPathSplice, steps)
        stepexprs = [_gen_build_step(s) for s in steps]
        return _maybe_fold(:(ReferenceModule.ReferencePath($(stepexprs...))), steps)
    end

    # Slice the chain at every splice and emit a `_concat` chain of literal
    # `ReferencePath(...)` segments interleaved with `_splice(...)` of the
    # spliced runtime values. Fold afterwards so `::T` checkpoints in the literal
    # segments become node types, while already-folded spliced sub-paths are kept.
    return _maybe_fold(_gen_concat_chain(steps), steps)
end

function _gen_concat_chain(steps::Vector{BuildStep})
    if isempty(steps)
        return :(ReferenceModule.EmptyReferencePath())
    end
    if steps[1] isa BSPathSplice
        head = :(ReferenceModule._splice($(_gen_build_step(steps[1]))))
        tail = _gen_concat_chain(steps[2:end])
        # _concat needs an EmptyReferencePath base case to short-circuit when
        # there's nothing after the splice.
        return :(ReferenceModule._concat($head, $tail))
    end
    # Gather a run of non-splice steps into a single literal ReferencePath.
    i = findfirst(s -> s isa BSPathSplice, steps)
    cutoff = i === nothing ? length(steps) + 1 : i
    prefix = steps[1:cutoff-1]
    prefix_expr = :(ReferenceModule.ReferencePath($([_gen_build_step(s) for s in prefix]...)))
    if cutoff > length(steps)
        return prefix_expr
    end
    tail = _gen_concat_chain(steps[cutoff:end])
    return :(ReferenceModule._concat($prefix_expr, $tail))
end

"""
    @reference()
    @reference(path)

Build a `ReferencePath` from the construction DSL. `@reference()` is the empty
path (terminates at the current node); `@reference(path)` parses a rootless chain
of steps, left = outermost:

- `a.b`               — `FieldReference` steps (`.a` then `.b`)
- `xs[i]`             — 1-based `ElementReference` (a single-element range)
- `xs{k}` / `xs{s:e}` — 0-based `PositionReference` (cursor) / `RangeReference`
- `.field(e)`         — a field whose name is the runtime value of `e`
- `.point(x, y)`      — a `PointReference` at pixel `(x, y)`
- `.proj(p, sub)`     — a `ProjectionReference` into projection `p`'s output `sub`
- `x::T`              — a `TypeReference(T)` checkpoint after `x` (folded onto the node)
- `^(expr)`           — splice a runtime `ReferencePath`/`ReferenceStep` into the literal

Inside `[]`, `{}`, `field(...)`, `point(...)`, `proj(...)` the arguments are
ordinary Julia expressions evaluated at runtime; bare symbols in *path* position
are literal field names. See `@reference_case` for the matching counterpart.
"""
macro reference()
    return _gen_build_path(BuildStep[])
end

macro reference(ex)
    steps = _parse_build_path(ex)
    return _gen_build_path(steps)
end

"""
    @step(expr)

Build a single `ReferenceStep` from a one-step DSL expression (the same step
grammar as `@reference`, e.g. `xs[i]`, `xs{k}`, `c.point(x, y)`, or a bare
`value` for a field). Useful for passing varargs to `append_reference`, or any
API that takes raw steps rather than whole paths. Unlike `@reference`, a leading
identifier before an operator (`xs[i]`) is a placeholder, not a field name; only
a bare symbol (`value`) is taken as a field name.
"""
macro step(ex)
    return _gen_build_step(_parse_step(ex))
end

# Parse a single-step expression. Unlike `_parse_build_path`, a leading
# identifier in front of an operator (`xs[i]`, `xs{k}`, `c.point(x, y)`) is
# treated as a placeholder; only when the whole expression is a bare symbol
# (`value`) is it taken as a field name.
function _parse_step(ex)
    if ex isa Symbol
        return BSField(String(ex))
    elseif ex isa Expr && ex.head == :ref
        if length(ex.args) == 2
            return BSIndex(ex.args[2])
        elseif length(ex.args) == 3
            return BSRange(ex.args[2], ex.args[3])
        else
            error("indexing supports 1 or 2 dimensions in @step: $ex")
        end
    elseif ex isa Expr && ex.head == :curly
        length(ex.args) == 2 || error("only one-dimensional position is supported in @step: $ex")
        return _braces_step(ex.args[2], ex)
    elseif ex isa Expr && ex.head == :vect
        if length(ex.args) == 1
            return BSIndex(ex.args[1])
        elseif length(ex.args) == 2
            return BSRange(ex.args[1], ex.args[2])
        else
            error("vector syntax supports 1 or 2 elements in @step: $ex")
        end
    elseif ex isa Expr && ex.head == :braces
        length(ex.args) == 1 || error("braces syntax supports exactly one element in @step: $ex")
        return _braces_step(ex.args[1], ex)
    elseif ex isa Expr && ex.head == :call
        f = ex.args[1]
        if f isa Expr && f.head == :. && f.args[2] isa QuoteNode
            opname = f.args[2].value
            if opname == :field
                length(ex.args) == 2 || error(".field(name) expects exactly one argument in @step: $ex")
                return BSField(ex.args[2])
            else
                # Dispatch through the extension seam — a higher-package step
                # type (e.g. `.point(x, y)` in visual/graphics) can register
                # its own DSL entry at its own site.
                return BSExtension(opname, Any[ex.args[2:end]...])
            end
        else
            error("unsupported call form in @step: $ex")
        end
    else
        error("unsupported @step syntax: $ex")
    end
end
