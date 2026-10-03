# Fragment of `ReferenceModule` — the `@reference` / `@reference_step` construction DSL: the
# compact surface syntax for building `Reference`s / `ReferenceStep`s.
#
# This fragment is a **lowering**, not a parser. The surface grammar is parsed once by
# `ReferenceSyntax.jl` into the shared `ReferenceSyntaxStep` AST; everything here turns that AST into
# constructor expressions. The pattern-matching counterpart, `@reference_case` in
# `ReferenceCase.jl`, lowers the very same AST into match branches.
#
# Extension steps owned by higher packages are reached through the `build_reference_step` /
# `get_reference_step_subpath_args` seams declared in `ReferenceInterface.jl`, so this fragment names no step
# type it does not own.

# ------------------------------------------------------------
# Code generation — ReferenceSyntaxStep → constructor expression
# ------------------------------------------------------------

# `_` and `__` are wildcards in the *matching* reading of the shared grammar, and reach
# it as ordinary field names. There is nothing to construct from either — a path being
# built has to say which step it means — so they are rejected here rather than silently
# lowered to a field with a peculiar name, which is what a builder would otherwise emit
# for `@reference(a.__.b)`.
function _gen_build_step(step::ReferenceSyntaxField)
    step.name in (REFERENCE_GAP_NAME, REFERENCE_LAZY_GAP_NAME) &&
        error("`$(step.name)` (any run of steps) is only valid inside @reference_case / " *
              "@reference_rules, not @reference/@reference_step — a path being built names its steps")
    step.name == REFERENCE_STEP_NAME &&
        error("`_` (any one step) is only valid inside @reference_case / @reference_rules, " *
              "not @reference/@reference_step — a path being built names its steps")
    :(ReferenceModule.FieldReferenceStep(String($(QuoteNode(step.name)))))
end

_gen_build_step(step::ReferenceSyntaxFieldExpression) =
    :(ReferenceModule.FieldReferenceStep(String($(esc(step.expr)))))

_gen_build_step(step::ReferenceSyntaxIndex) =
    :(ReferenceModule.ElementReferenceStep(Int($(esc(step.expr)))))

_gen_build_step(step::ReferenceSyntaxPosition) =
    :(ReferenceModule.PositionReferenceStep(Int($(esc(step.expr)))))

# A step counts gaps between elements, from 0, so only the `[i, j]` spelling has
# a conversion to make — the same one `ElementReferenceStep` makes for `xs[i]`.
function _gen_build_step(step::ReferenceSyntaxRange)
    start = :(Int($(esc(step.startexpr))))
    step.numbering === :element && (start = :($start - 1))
    :(ReferenceModule.RangeReferenceStep($start, Int($(esc(step.stopexpr)))))
end

_gen_build_step(step::ReferenceSyntaxSplice) = esc(step.expr)

_gen_build_step(step::ReferenceSyntaxType) =
    :(ReferenceModule.TypeReferenceStep($(esc(step.expr))))

# `name...` binds a path's remaining tail — a *matching* concept. There is nothing to
# construct from it, so the shared grammar's tail-bind node is rejected here rather than
# silently lowered to something else.
_gen_build_step(step::ReferenceSyntaxTailBind) =
    error("`$(step.name)...` (tail binding) is only valid inside @reference_case, not @reference/@reference_step")

# The bound spellings `__(name)` / `__ʔ(name)` reach here as extension steps, and are
# refused for the same reason as the bare ones rather than being reported as an
# unregistered step type.
function _gen_build_step(step::ReferenceSyntaxExtension)
    String(step.name) in (REFERENCE_GAP_NAME, REFERENCE_LAZY_GAP_NAME) &&
        error("`$(step.name)(name)` (binding a run of steps) is only valid inside " *
              "@reference_case / @reference_rules, not @reference/@reference_step")
    step.name === :any &&
        error("`any(path, …)` (alternation) is only valid inside @reference_case / " *
              "@reference_rules, not @reference/@reference_step — a path being built " *
              "names one route, not a choice of them")
    _gen_build_extension_step(step)
end

# Extension-registered `.name(args...)` DSL entries dispatch through
# `build_reference_step(::Val{name}, escaped_args...)`. A subpath argument (declared via
# `get_reference_step_subpath_args`) is parsed with the *construction* subpath rule and lowered to
# its path expression; every other argument is an escaped Julia expression. So no step
# type is named here.
function _gen_build_extension_step(step::ReferenceSyntaxExtension)
    args = Any[a isa ReferenceSyntaxArgumentSubPath ? _gen_build_path(_build_subpath(a.expr)) : esc(a.expr)
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
        return ReferenceSyntaxStep[ReferenceSyntaxSplice(ex.args[2])]
    end
    return parse_reference_path(ex)
end

_splice(p::ReferenceModule.Reference) = p
_splice(s::ReferenceModule.ReferenceStep) =
    ReferenceModule.ConcreteReference(s, ReferenceModule.EmptyReference())

# Wrap a built (possibly TypeReferenceStep-bearing) path expression in the runtime
# fold pass only when the literal carries a `::T` type step — a plain navigation
# skeleton needs no folding (its node types stay `nothing`, filled in later when
# the skeleton is annotated against a document), so the common case allocates
# nothing extra.
_maybe_fold(expr, steps) =
    any(s -> s isa ReferenceSyntaxType, steps) ? :(ReferenceModule.fold_reference_types($expr)) : expr

function _gen_build_path(steps::Vector{ReferenceSyntaxStep})
    if isempty(steps)
        return :(ReferenceModule.EmptyReference())
    end

    # Fast path: no splices at all.
    if !any(s -> s isa ReferenceSyntaxSplice, steps)
        stepexprs = [_gen_build_step(s) for s in steps]
        return _maybe_fold(:(ReferenceModule.Reference($(stepexprs...))), steps)
    end

    # Slice the chain at every splice and emit a `concat_references` chain of literal
    # `Reference(...)` segments interleaved with `_splice(...)` of the
    # spliced runtime values. Fold afterwards so `::T` type steps in the literal
    # segments become node types, while already-folded spliced sub-paths are kept.
    return _maybe_fold(_gen_concat_chain(steps), steps)
end

function _gen_concat_chain(steps::Vector{ReferenceSyntaxStep})
    if isempty(steps)
        return :(ReferenceModule.EmptyReference())
    end
    if steps[1] isa ReferenceSyntaxSplice
        head = :(ReferenceModule._splice($(_gen_build_step(steps[1]))))
        tail = _gen_concat_chain(steps[2:end])
        # `concat_references` needs an EmptyReference base case to short-circuit
        # when there's nothing after the splice.
        return :(ReferenceModule.concat_references($head, $tail))
    end
    # Gather a run of non-splice steps into a single literal Reference.
    i = findfirst(s -> s isa ReferenceSyntaxSplice, steps)
    cutoff = i === nothing ? length(steps) + 1 : i
    prefix = steps[1:cutoff-1]
    prefix_expr = :(ReferenceModule.Reference($([_gen_build_step(s) for s in prefix]...)))
    if cutoff > length(steps)
        return prefix_expr
    end
    tail = _gen_concat_chain(steps[cutoff:end])
    return :(ReferenceModule.concat_references($prefix_expr, $tail))
end

"""
    @reference(path)
    @reference(document, path)

Build a `Reference` from the construction DSL.

Use it to name a place in a document — a field, an element, a range, or a
typed node — so a caller can read it, write it, or hold it for later. A
caller that already holds a path to a container extends it with
`concat_references` to reach a part further inside.

# Example

    @document struct Point
        x::Int
        y::Int
    end

    point = Point(1, 2)
    path = @reference(point, x)
    evaluate_reference(point, path)   # 1

`@reference(path)` parses a rootless chain of steps, left = outermost:

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

A type step takes a bare type name. A name that starts with a capital letter
after a type step reads as a qualified type name, and the parser throws an error:
`::JsonObject.Name` throws. So a field whose name starts with a capital letter can
not follow a type step.

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

See also [`@reference_step`](@ref), which builds a single step, and
[`@reference_case`](@ref), which matches the same grammar.
"""
macro reference()
    return _gen_build_path(ReferenceSyntaxStep[])
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
