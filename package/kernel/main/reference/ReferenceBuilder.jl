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
#   rendered.name(args...)   — extension steps registered by higher packages
#
# Splicing:
#   ^(expr)              — splice a ReferencePath or ReferenceStep at the front
#   value.^(expr)        — splice at the end of a chain (parses as .^ broadcast)
#   ^(expr).field        — splice followed by more steps
#
# Semantics:
#   - top-level bare symbols in path position are literal field names
#   - inside [expr], field(expr), and extension calls, arguments are
#     ordinary Julia expressions that get evaluated at runtime
# ------------------------------------------------------------

abstract type BuildStep end

struct BuildStepField <: BuildStep
    nameexpr
end

struct BuildStepIndex <: BuildStep
    idxexpr
end

struct BuildStepPosition <: BuildStep
    idxexpr
end

struct BuildStepRange <: BuildStep
    startexpr
    stopexpr
end

struct BuildStepPathSplice <: BuildStep
    expr
end

# A `.name(args...)` DSL entry whose step type is registered by dispatch on
# `dsl_build_step(::Val{name}, escaped_args...)`. The cross-package step types
# (`.point`, `.proj`, …) register their own `dsl_build_step` in the packages that
# own them; none is kernel-registered here.
struct BuildStepExtension <: BuildStep
    name::Symbol
    args::Vector{Any}
end

# A first-class type checkpoint step: `f::T` emits the steps of `f` and then a
# TypeReference(T) — "f first then T".
struct BuildStepType <: BuildStep
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
        push!(steps, BuildStepField(String(ex)))
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
        push!(steps, BuildStepField(String(ex.args[2].value)))
        return steps

    elseif ex isa Expr && ex.head == :ref
        # base[idx] — ElementReference (1-based), or base[i, j] — RangeReference
        if length(ex.args) == 2
            _parse_build_path!(steps, ex.args[1])
            push!(steps, BuildStepIndex(ex.args[2]))
        elseif length(ex.args) == 3
            _parse_build_path!(steps, ex.args[1])
            push!(steps, BuildStepRange(ex.args[2], ex.args[3]))
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

        if f == :(^)
            # ^(expr) at path position — splice
            length(ex.args) == 2 || error("^(expr) expects exactly one argument: $ex")
            push!(steps, BuildStepPathSplice(ex.args[2]))
            return steps

        elseif f == :.^ && length(ex.args) == 3
            # base.^(expr) — Julia parses `base.^(expr)` as binary broadcast
            # `.^`; we use it as "path-tail splice at the end of the chain"
            _parse_build_path!(steps, ex.args[2])
            push!(steps, BuildStepPathSplice(ex.args[3]))
            return steps

        elseif f isa Symbol
            # Top-level extension step `name(args...)` with no preceding path.
            push!(steps, _build_extension_step(f, ex.args[2:end]))
            return steps

        elseif f isa Expr && f.head == :. && f.args[2] isa QuoteNode
            opname = f.args[2].value
            _parse_build_path!(steps, f.args[1])

            if opname == :field
                length(ex.args) == 2 || error(".field(name) expects exactly one argument")
                push!(steps, BuildStepField(ex.args[2]))
                return steps
            else
                # A mid-path extension step, dispatched through the seam.
                push!(steps, _build_extension_step(opname, ex.args[2:end]))
                return steps
            end
        else
            error("unsupported call form in @reference: $ex")
        end

    elseif ex isa Expr && ex.head == :vect
        # [i] as a relative subpath — ElementReference (1-based), or [i, j] — RangeReference
        if length(ex.args) == 1
            push!(steps, BuildStepIndex(ex.args[1]))
        elseif length(ex.args) == 2
            push!(steps, BuildStepRange(ex.args[1], ex.args[2]))
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

# Split a type-checkpoint base into its `BuildStepType` and any trailing `.field`
# steps. A bare `Type` yields just the type; a `Type.a.b` chain (which Julia
# parses as `getfield` on the type value) is read as the checkpoint `Type`
# followed by field steps `.a`, `.b` — so a mid-path `::T.field` needs no
# parens. Mirrors `_build_leading_type!`.
function _push_type_and_fields!(steps::Vector{BuildStep}, base)
    fields = String[]
    cur = base
    while cur isa Expr && cur.head == :. && cur.args[2] isa QuoteNode
        pushfirst!(fields, String(cur.args[2].value))
        cur = cur.args[1]
    end
    cur isa Symbol ||
        error("@reference: type checkpoint must start with a type name: $base")
    push!(steps, BuildStepType(cur))
    for f in fields
        push!(steps, BuildStepField(f))
    end
end

# `x::T` type suffix: a bare `T` is a checkpoint; `T{i}` / `T[i]` (which Julia
# parses as a parametric/indexed type) is the checkpoint `T` followed by a
# position/range/element step (`value::Leaf{s:e}` needs no parens); `T.field`
# is the checkpoint `T` followed by field steps (`entries[i]::Entry.key`).
function _build_type_suffix!(steps::Vector{BuildStep}, T)
    if T isa Expr && T.head == :curly
        _push_type_and_fields!(steps, T.args[1])
        push!(steps, _braces_step(T.args[2], T))
    elseif T isa Expr && T.head == :ref
        _push_type_and_fields!(steps, T.args[1])
        if length(T.args) == 2
            push!(steps, BuildStepIndex(T.args[2]))
        elseif length(T.args) == 3
            push!(steps, BuildStepRange(T.args[2], T.args[3]))
        else
            error("type suffix index supports 1 or 2 dimensions: $T")
        end
    else
        _push_type_and_fields!(steps, T)
    end
end

# Leading `::X`: a bare symbol is just the checkpoint; a chain like
# `Node.value{s:e}` (which Julia parses entirely under the `::`) is read as
# checkpoint `Node` followed by the `.value{s:e}` steps — so no parens.
function _build_leading_type!(steps::Vector{BuildStep}, X)
    if X isa Symbol
        push!(steps, BuildStepType(X))
    else
        n = length(steps)
        _parse_build_path!(steps, X)
        root = steps[n + 1]
        (root isa BuildStepField && root.nameexpr isa String) ||
            error("leading ::T must start with a type name: $X")
        steps[n + 1] = BuildStepType(Symbol(root.nameexpr))
    end
end

# Lower the inner expression of `{...}` to either a position or range step.
function _braces_step(inner, ctx)
    if inner isa Expr && inner.head == :call && length(inner.args) == 3 && inner.args[1] == :(:)
        return BuildStepRange(inner.args[2], inner.args[3])
    end
    return BuildStepPosition(inner)
end

function _parse_build_subpath(ex)
    # ^(expr) splices an already-computed ReferencePath directly
    if ex isa Expr && ex.head == :call && ex.args[1] == :(^)
        length(ex.args) == 2 || error("^(expr) expects exactly one argument: $ex")
        return BuildStep[BuildStepPathSplice(ex.args[2])]
    end
    return _parse_build_path(ex)
end

# A `.name(args...)` / `name(args...)` extension step. Arguments the step declares
# as subpaths (via `dsl_step_subpath_args`) are parsed into `Vector{BuildStep}`;
# the rest stay raw Julia expressions (escaped at codegen). So the parser names no
# specific step type — `.proj`'s subpath argument is discovered through the seam.
function _build_extension_step(name::Symbol, args)
    subpaths = dsl_step_subpath_args(Val(name))
    bargs = Any[(i in subpaths ? _parse_build_subpath(a) : a)
                for (i, a) in enumerate(args)]
    return BuildStepExtension(name, bargs)
end

# ------------------------------------------------------------
# Code generation
# ------------------------------------------------------------

function _gen_build_step(step::BuildStepField)
    nameex = step.nameexpr isa String ? QuoteNode(step.nameexpr) : esc(step.nameexpr)
    return :(ReferenceModule.FieldReference(String($nameex)))
end

function _gen_build_step(step::BuildStepIndex)
    return :(ReferenceModule.ElementReference(Int($(esc(step.idxexpr)))))
end

function _gen_build_step(step::BuildStepPosition)
    return :(ReferenceModule.PositionReference(Int($(esc(step.idxexpr)))))
end

function _gen_build_step(step::BuildStepRange)
    return :(ReferenceModule.RangeReference(Int($(esc(step.startexpr))), Int($(esc(step.stopexpr)))))
end

function _gen_build_step(step::BuildStepPathSplice)
    return esc(step.expr)
end

function _gen_build_step(step::BuildStepType)
    return :(ReferenceModule.TypeReference($(esc(step.typeexpr))))
end

# Extension-registered `.name(args...)` DSL entries dispatch through
# `dsl_build_step(::Val{name}, escaped_args...)`. A subpath argument — which the
# parser stored as a `Vector{BuildStep}` (see `dsl_step_subpath_args`) — is
# lowered to its path expression; every other argument is an escaped Julia
# expression. So no step type is named here.
function _gen_build_step(step::BuildStepExtension)
    args = Any[a isa Vector{BuildStep} ? _gen_build_path(a) : esc(a) for a in step.args]
    return dsl_build_step(Val(step.name), args...)
end

"""
    dsl_build_step(::Val{name}, escaped_args...) -> Expr

Return the expression that constructs the step type mapped to `.name(args...)`
in the `@reference` DSL. `escaped_args` are `esc`'d Julia expressions ready
to splice into the returned constructor call. Each package registers a
`::Val{:name}` method for its own step types; none live in the kernel's reference
layer (`.point` / `.proj` register in the packages that own them).
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
# skeleton needs no folding (its node types stay `nothing`, filled in later when
# the skeleton is annotated against a document), so the common case allocates
# nothing extra.
_maybe_fold(expr, steps) =
    any(s -> s isa BuildStepType, steps) ? :(ReferenceModule.fold_reference_types($expr)) : expr

function _gen_build_path(steps::Vector{BuildStep})
    # No steps → empty path.
    if isempty(steps)
        return :(ReferenceModule.EmptyReferencePath())
    end

    # Fast path: no splices at all.
    if !any(s -> s isa BuildStepPathSplice, steps)
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
    if steps[1] isa BuildStepPathSplice
        head = :(ReferenceModule._splice($(_gen_build_step(steps[1]))))
        tail = _gen_concat_chain(steps[2:end])
        # _concat needs an EmptyReferencePath base case to short-circuit when
        # there's nothing after the splice.
        return :(ReferenceModule._concat($head, $tail))
    end
    # Gather a run of non-splice steps into a single literal ReferencePath.
    i = findfirst(s -> s isa BuildStepPathSplice, steps)
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
    @reference(path)
    @reference(document, path)

Build a `ReferencePath` from the construction DSL. `@reference(path)` parses a
rootless chain of steps, left = outermost:

- `a.b`               — `FieldReference` steps (`.a` then `.b`)
- `xs[i]`             — 1-based `ElementReference` (a single-element range)
- `xs{k}` / `xs{s:e}` — 0-based `PositionReference` (cursor) / `RangeReference`
- `.field(e)`         — a field whose name is the runtime value of `e`
- `.name(args...)`    — an extension step registered by a higher package (its
                        owning package documents each one)
- `x::T`              — a node type checkpoint after `x` (folded onto the node)
- `^(expr)`           — splice a runtime `ReferencePath`/`ReferenceStep` into the literal

Inside `[]`, `{}`, `field(...)`, and extension calls the arguments are ordinary
Julia expressions evaluated at runtime; bare symbols in *path* position are
literal field names.

**Two ways to get a fully-typed path.** Either spell every node's type inline
(`@reference ::JsonObject.entries::CellVector[1]::JsonObjectEntry.value::Document`),
or hand the path a **document** and let it fill the types:
`@reference(document, entries[1].value)` builds the plain navigation skeleton
and annotates it against `document` (via
[`annotate_reference_types`](@ref)), so the result carries the exact types the
live document has at each node — no inline `::T` needed, and the types are
correct by construction rather than by hand. Use this whenever the document is
in scope. See `@reference_case` for the matching counterpart.
"""
macro reference()
    return _gen_build_path(BuildStep[])
end

macro reference(ex)
    steps = _parse_build_path(ex)
    expr = _gen_build_path(steps)
    return :(ReferenceModule._strict_check($expr, $(QuoteNode(__source__))))
end

macro reference(document, ex)
    steps = _parse_build_path(ex)
    plain = _gen_build_path(steps)
    return :(ReferenceModule.annotate_reference_types($(esc(document)), $plain))
end

"""
    @step(expr)

Build a single `ReferenceStep` from a one-step DSL expression (the same step
grammar as `@reference`, e.g. `xs[i]`, `xs{k}`, a `.name(...)` extension step, or
a bare `value` for a field). Useful for passing varargs to `append_reference`, or any
API that takes raw steps rather than whole paths. Unlike `@reference`, a leading
identifier before an operator (`xs[i]`) is a placeholder, not a field name; only
a bare symbol (`value`) is taken as a field name.
"""
macro step(ex)
    return _gen_build_step(_parse_step(ex))
end

# Parse a single-step expression. Unlike `_parse_build_path`, a leading
# identifier in front of an operator (`xs[i]`, `xs{k}`, `c.name(...)`) is
# treated as a placeholder; only when the whole expression is a bare symbol
# (`value`) is it taken as a field name.
function _parse_step(ex)
    if ex isa Symbol
        return BuildStepField(String(ex))
    elseif ex isa Expr && ex.head == :ref
        if length(ex.args) == 2
            return BuildStepIndex(ex.args[2])
        elseif length(ex.args) == 3
            return BuildStepRange(ex.args[2], ex.args[3])
        else
            error("indexing supports 1 or 2 dimensions in @step: $ex")
        end
    elseif ex isa Expr && ex.head == :curly
        length(ex.args) == 2 || error("only one-dimensional position is supported in @step: $ex")
        return _braces_step(ex.args[2], ex)
    elseif ex isa Expr && ex.head == :vect
        if length(ex.args) == 1
            return BuildStepIndex(ex.args[1])
        elseif length(ex.args) == 2
            return BuildStepRange(ex.args[1], ex.args[2])
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
                return BuildStepField(ex.args[2])
            else
                # A `.name(...)` extension step, dispatched through the seam.
                return _build_extension_step(opname, ex.args[2:end])
            end
        else
            error("unsupported call form in @step: $ex")
        end
    else
        error("unsupported @step syntax: $ex")
    end
end
