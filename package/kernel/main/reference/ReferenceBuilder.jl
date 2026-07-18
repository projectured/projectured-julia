# Fragment of `ReferenceModule` — the `@reference` / `@reference_step` construction DSL: the
# compact surface syntax for building `Reference`s / `ReferenceStep`s.
#
# This fragment is a **lowering**, not a parser. The surface grammar is parsed once by
# `ReferenceSyntax.jl` into the shared `RefStep` AST; everything here turns that AST into
# constructor expressions. The pattern-matching counterpart, `@reference_case` in
# `ReferenceCase.jl`, lowers the very same AST into match branches.
#
# Extension steps owned by higher packages are reached through the `build_reference_step` /
# `get_reference_step_subpath_args` seams declared in `ReferenceInterface.jl`, so this fragment names no step
# type it does not own.

# ------------------------------------------------------------
# Code generation — RefStep → constructor expression
# ------------------------------------------------------------

_gen_build_step(step::RefField) =
    :(ReferenceModule.FieldReferenceStep(String($(QuoteNode(step.name)))))

_gen_build_step(step::RefFieldExpr) =
    :(ReferenceModule.FieldReferenceStep(String($(esc(step.expr)))))

_gen_build_step(step::RefIndex) =
    :(ReferenceModule.ElementReferenceStep(Int($(esc(step.expr)))))

_gen_build_step(step::RefPosition) =
    :(ReferenceModule.PositionReferenceStep(Int($(esc(step.expr)))))

_gen_build_step(step::RefRange) =
    :(ReferenceModule.RangeReferenceStep(Int($(esc(step.startexpr))), Int($(esc(step.stopexpr)))))

_gen_build_step(step::RefSplice) = esc(step.expr)

_gen_build_step(step::RefType) =
    :(ReferenceModule.TypeReferenceStep($(esc(step.expr))))

# `name...` binds a path's remaining tail — a *matching* concept. There is nothing to
# construct from it, so the shared grammar's tail-bind node is rejected here rather than
# silently lowered to something else.
_gen_build_step(step::RefTailBind) =
    error("`$(step.name)...` (tail binding) is only valid inside @reference_case, not @reference/@reference_step")

# Extension-registered `.name(args...)` DSL entries dispatch through
# `build_reference_step(::Val{name}, escaped_args...)`. A subpath argument (declared via
# `get_reference_step_subpath_args`) is parsed with the *construction* subpath rule and lowered to
# its path expression; every other argument is an escaped Julia expression. So no step
# type is named here.
function _gen_build_step(step::RefExtension)
    args = Any[a isa RefArgSubPath ? _gen_build_path(_build_subpath(a.expr)) : esc(a.expr)
               for a in step.args]
    return build_reference_step(Val(step.name), args...)
end

# The seam's answer for a name no package registered: this DSL is where an unknown
# `.name(…)` is first reachable, so this is where it is reported.
build_reference_step(::Val{n}, args...) where {n} =
    error("no `build_reference_step(::Val{$(QuoteNode(n))}, …)` method registered — `.$(n)(…)` is not a known @reference step")

# The construction reading of a subpath argument: `^(expr)` splices an already-computed
# `Reference` directly; anything else is an ordinary path. (The matcher reads a bare
# symbol here as a whole-path *binder* instead — the one place the two DSLs genuinely
# disagree about the same syntax, which is why the shared grammar keeps the argument raw.)
function _build_subpath(ex)
    if ex isa Expr && ex.head == :call && ex.args[1] == :(^)
        length(ex.args) == 2 || error("^(expr) expects exactly one argument: $ex")
        return RefStep[RefSplice(ex.args[2])]
    end
    return parse_reference_path(ex)
end

# Wrap a value so it can stand in as a Reference: pass paths through,
# wrap steps into a one-element path.
_splice(p::ReferenceModule.Reference) = p
_splice(s::ReferenceModule.ReferenceStep) =
    ReferenceModule.ConcreteReference(s, ReferenceModule.EmptyReference())

# Concatenate two paths via the canonical, type-preserving `concat_references`
# (ReferenceModule), so an already-folded spliced sub-path keeps its node types
# even when it is not the last segment (e.g. `^(expr).field`). The `_concat` name
# is kept because the generated code below emits `ReferenceModule._concat`.
const _concat = ReferenceModule.concat_references

# Wrap a built (possibly TypeReferenceStep-bearing) path expression in the runtime
# fold pass only when the literal carries a `::T` type step — a plain navigation
# skeleton needs no folding (its node types stay `nothing`, filled in later when
# the skeleton is annotated against a document), so the common case allocates
# nothing extra.
_maybe_fold(expr, steps) =
    any(s -> s isa RefType, steps) ? :(ReferenceModule.fold_reference_types($expr)) : expr

function _gen_build_path(steps::Vector{RefStep})
    # No steps → empty path.
    if isempty(steps)
        return :(ReferenceModule.EmptyReference())
    end

    # Fast path: no splices at all.
    if !any(s -> s isa RefSplice, steps)
        stepexprs = [_gen_build_step(s) for s in steps]
        return _maybe_fold(:(ReferenceModule.Reference($(stepexprs...))), steps)
    end

    # Slice the chain at every splice and emit a `_concat` chain of literal
    # `Reference(...)` segments interleaved with `_splice(...)` of the
    # spliced runtime values. Fold afterwards so `::T` type steps in the literal
    # segments become node types, while already-folded spliced sub-paths are kept.
    return _maybe_fold(_gen_concat_chain(steps), steps)
end

function _gen_concat_chain(steps::Vector{RefStep})
    if isempty(steps)
        return :(ReferenceModule.EmptyReference())
    end
    if steps[1] isa RefSplice
        head = :(ReferenceModule._splice($(_gen_build_step(steps[1]))))
        tail = _gen_concat_chain(steps[2:end])
        # _concat needs an EmptyReference base case to short-circuit when
        # there's nothing after the splice.
        return :(ReferenceModule._concat($head, $tail))
    end
    # Gather a run of non-splice steps into a single literal Reference.
    i = findfirst(s -> s isa RefSplice, steps)
    cutoff = i === nothing ? length(steps) + 1 : i
    prefix = steps[1:cutoff-1]
    prefix_expr = :(ReferenceModule.Reference($([_gen_build_step(s) for s in prefix]...)))
    if cutoff > length(steps)
        return prefix_expr
    end
    tail = _gen_concat_chain(steps[cutoff:end])
    return :(ReferenceModule._concat($prefix_expr, $tail))
end

"""
    @reference(path)
    @reference(document, path)

Build a `Reference` from the construction DSL. `@reference(path)` parses a
rootless chain of steps, left = outermost:

- `a.b`               — `FieldReferenceStep` steps (`.a` then `.b`)
- `xs[i]`             — 1-based `ElementReferenceStep` (a single-element range)
- `xs{k}` / `xs{s:e}` — 0-based `PositionReferenceStep` (cursor) / `RangeReferenceStep`
- `.field(e)`         — a field whose name is the runtime value of `e`
- `.name(args...)`    — an extension step registered by a higher package (its
                        owning package documents each one)
- `x::T`              — a node type checkpoint after `x` (folded onto the node)
- `^(expr)`           — splice a runtime `Reference`/`ReferenceStep` into the literal

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
in scope. See `@reference_case` for the matching counterpart, which reads the
same grammar.
"""
macro reference()
    return _gen_build_path(RefStep[])
end

macro reference(ex)
    steps = parse_reference_path(ex)
    expr = _gen_build_path(steps)
    return :(ReferenceModule._strict_check($expr, $(QuoteNode(__source__))))
end

macro reference(document, ex)
    steps = parse_reference_path(ex)
    plain = _gen_build_path(steps)
    return :(ReferenceModule.annotate_reference_types($(esc(document)), $plain))
end

"""
    @reference_step(expr)

Build a single `ReferenceStep` from a one-step DSL expression (the same step
grammar as `@reference`, e.g. `xs[i]`, `xs{k}`, a `.name(...)` extension step, or
a bare `value` for a field). Useful for passing varargs to `extend_reference`, or any
API that takes raw steps rather than whole paths. Unlike `@reference`, a leading
identifier before an operator (`xs[i]`) is a placeholder, not a field name; only
a bare symbol (`value`) is taken as a field name.
"""
macro reference_step(ex)
    return _gen_build_step(parse_reference_step(ex))
end
