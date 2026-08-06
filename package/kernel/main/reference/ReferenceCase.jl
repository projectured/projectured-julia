# Fragment of `ReferenceModule` — the `@reference_case` pattern-matching DSL, the
# destructuring counterpart of the `@reference` construction DSL
# (`ReferenceBuilder.jl`).
#
# This fragment is a **lowering**, not a parser: the surface grammar both DSLs accept is
# parsed once by `ReferenceSyntax.jl` into the shared `RefStep` AST, and everything here
# turns that AST into match branches. What makes the matching reading its own thing is the
# *value* vocabulary below (`PatValue`: wildcards, binders, typed binders, interpolation)
# — a bare symbol binds here where it would name a field in the builder.
#
# Extension steps owned by higher packages are reached through the `match_reference_step` /
# `get_reference_step_subpath_args` seams declared in `ReferenceInterface.jl`, so this fragment names no step
# type it does not own.

# `when(pattern, cond)` and `prefix(path)` are surface-syntax keywords the
# `@reference_case` macro recognizes *by symbol* (see `_parse_rule`) and consumes at
# macroexpand time — they are never evaluated as functions, so the layer defines and
# exports nothing for them. Writing either outside `@reference_case` is a plain
# `UndefVarError`. See the `@reference_case` docstring for what they mean.

# ------------------------------------------------------------
# Pattern representation
# ------------------------------------------------------------

abstract type PatValue end

struct PatValueWildcard <: PatValue end

struct PatValueBind <: PatValue
    name::Symbol
end

struct PatValueTypedBind <: PatValue
    name::Symbol
    ty
end

struct PatValueLiteral <: PatValue
    value
end

struct PatValueInterp <: PatValue
    expr
end

abstract type PatStep end

struct PatStepField <: PatStep
    namepat::PatValue   # matches FieldReferenceStep.name[] :: String
end

struct PatStepIndex <: PatStep
    idxpat::PatValue    # matches a single-element RangeReferenceStep; 1-based index = start + 1
end

struct PatStepPosition <: PatStep
    idxpat::PatValue    # matches a zero-width RangeReferenceStep (a cursor position); 0-based = start
end

struct PatStepRange <: PatStep
    startpat::PatValue
    stoppat::PatValue
end

# A `.name(patterns...)` DSL pattern whose match code is registered by dispatch
# on `match_reference_step(::Val{name}, hex, argpats, rest_success, bound)`. The
# cross-package step types (`.point`, `.proj`, …) register their own
# `match_reference_step` in the package that owns them; none is kernel-registered here.
struct PatStepExtension <: PatStep
    name::Symbol
    argpats::Vector{Any}   # per-arg PatValue or Vector{PatStep} (subpath)
end

struct PatStepWholePathBind <: PatStep
    name::Symbol
end

# A type assertion in a pattern: `f::T` matches `f`'s steps, then requires the
# folded `type` field of the node reached to be a subtype of `T` (non-navigating).
# It narrows the match — a path standing on some other kind of node falls through
# to the next rule. A path that records no type (`nothing`) still matches; see
# `_type_step_matches`.
struct PatStepType <: PatStep
    typeexpr
end

# `::t` where `t` is a lowercase identifier binds the matched node's folded
# `type` field to `t` (the pattern dual of construction, where `::t` splices
# `t`'s runtime type value). A capitalized `::T` stays a `PatStepType` assertion, so
# every existing typed pattern is unchanged.
struct PatStepTypeBind <: PatStep
    name::Symbol
end

struct PatStepPathInterp <: PatStep
    expr
end

# A bare identifier that begins with a lowercase letter — the bind/assert
# discriminator for `::x` in a pattern (mirrors the value-pattern convention
# where a bare lowercase symbol binds).
_is_type_bind_symbol(x) =
    x isa Symbol && (s = string(x); !isempty(s) && islowercase(first(s)))

# ------------------------------------------------------------
# Value-pattern parsing
# ------------------------------------------------------------

function _parse_value(ex)
    if ex === :_
        return PatValueWildcard()
    elseif ex isa Symbol
        return PatValueBind(ex)
    elseif ex isa Expr && ex.head == :call && ex.args[1] == :(^)
        return PatValueInterp(ex.args[2])
    elseif ex isa Expr && ex.head == :(::) && ex.args[1] isa Symbol
        return PatValueTypedBind(ex.args[1], ex.args[2])
    elseif ex isa QuoteNode
        return PatValueLiteral(ex.value)
    elseif ex isa String || ex isa Int || ex isa Bool || ex isa Char
        return PatValueLiteral(ex)
    else
        # Fall back to interpolation for arbitrary expressions.
        return PatValueInterp(ex)
    end
end

# ------------------------------------------------------------
# Step-AST lowering
#
# The surface grammar is parsed once, by `ReferenceSyntax.jl`, into the shared
# `RefStep` AST. This is where the *matching* reading of that AST is applied — the
# three places the matcher reads the same syntax differently from the builder:
#
#   - every raw leaf expression becomes a `PatValue` (`_parse_value`): a bare symbol
#     in value position BINDS, `_` is a wildcard, `^(e)` interpolates a comparison;
#   - a `::T` step asserts the node type, but a lowercase `::t` BINDS it;
#   - a bare symbol as a subpath argument binds the whole subpath, where the
#     construction DSL would read it as a field name.
#
# `ReferenceBuilder.jl` lowers the very same AST into constructor calls.
# ------------------------------------------------------------

# A `::x` type step in a pattern: a lowercase identifier binds the node type,
# any other form asserts it.
_pat_type_step(x) = _is_type_bind_symbol(x) ? PatStepTypeBind(x) : PatStepType(x)

# The matching reading of a subpath argument: a bare symbol binds the entire subpath.
# (The construction DSL reads a bare symbol here as a field name instead — which is
# exactly why the shared grammar keeps subpath arguments raw rather than pre-parsing
# them.)
_case_subpath(ex) =
    ex isa Symbol ? PatStep[PatStepWholePathBind(ex)] : _to_pat_steps(parse_reference_path(ex))

_to_pat(s::RefField)     = PatStepField(PatValueLiteral(s.name))
_to_pat(s::RefFieldExpr) = PatStepField(_parse_value(s.expr))
_to_pat(s::RefIndex)     = PatStepIndex(_parse_value(s.expr))
_to_pat(s::RefPosition)  = PatStepPosition(_parse_value(s.expr))
_to_pat(s::RefRange)     = PatStepRange(_parse_value(s.startexpr), _parse_value(s.stopexpr))
_to_pat(s::RefType)      = _pat_type_step(s.expr)
_to_pat(s::RefSplice)    = PatStepPathInterp(s.expr)
_to_pat(s::RefTailBind)  = PatStepWholePathBind(s.name)
_to_pat(s::RefExtension) = PatStepExtension(s.name, Any[_to_pat_arg(a) for a in s.args])

_to_pat_arg(a::RefArgValue)   = _parse_value(a.expr)
_to_pat_arg(a::RefArgSubPath) = _case_subpath(a.expr)

_to_pat_steps(steps::Vector{RefStep}) = PatStep[_to_pat(s) for s in steps]

# Parse a path pattern: the shared grammar, then the matching reading of it.
_parse_path(ex) = _to_pat_steps(parse_reference_path(ex))

# ------------------------------------------------------------
# Rule parsing
# ------------------------------------------------------------

function _parse_rule(ex)
    ex isa Expr && ex.head == :call && ex.args[1] == :(=>) ||
        error("expected `pattern => result`, got: $ex")

    lhs, rhs = ex.args[2], ex.args[3]

    if lhs isa Expr && lhs.head == :call && lhs.args[1] == :when
        length(lhs.args) == 3 || error("when(pattern, cond) expects exactly two arguments")
        inner_lhs = lhs.args[2]
        cond = lhs.args[3]
        if inner_lhs isa Expr && inner_lhs.head == :call && inner_lhs.args[1] == :prefix
            length(inner_lhs.args) == 2 || error("prefix(path) expects exactly one argument")
            pat = _parse_path(inner_lhs.args[2])
            return (:prefix, pat, cond, rhs)
        else
            pat = _parse_path(inner_lhs)
            return (:exact, pat, cond, rhs)
        end
    elseif lhs isa Expr && lhs.head == :call && lhs.args[1] == :prefix
        length(lhs.args) == 2 || error("prefix(path) expects exactly one argument")
        pat = _parse_path(lhs.args[2])
        return (:prefix, pat, nothing, rhs)
    elseif lhs === :_
        pat = PatStep[PatStepWholePathBind(:_)]
        return (:exact, pat, nothing, rhs)
    elseif lhs === :∅
        # Empty-path pattern: matches a reference that terminates *at* the
        # element itself — a whole-element ("tree") selection. Compiles to a
        # zero-step exact match (`_ref_input isa EmptyReference`). This only
        # adds a writable pattern; the no-match fallthrough is still `nothing`.
        return (:exact, PatStep[], nothing, rhs)
    elseif lhs isa Expr && lhs.head == :(::) && length(lhs.args) == 2 && lhs.args[1] === :∅
        # `∅::t` / `∅::T` — a whole-element selection whose terminal type is
        # bound (`::t`) or asserted (`::T`). Matches an `EmptyReference`
        # and reads its `type` field. The empty-path match falls out of the
        # single type step operating on an EmptyReference.
        return (:exact, PatStep[_pat_type_step(lhs.args[2])], nothing, rhs)
    else
        pat = _parse_path(lhs)
        return (:exact, pat, nothing, rhs)
    end
end

# ------------------------------------------------------------
# Code generation helpers
# ------------------------------------------------------------

# Returns (expr, boundnames)
#
# `expr` evaluates either to `success` or to `_nomatch`.
function _gen_value_match(valex, pat::PatValueWildcard, success, bound::Set{Symbol})
    return success, bound
end

function _gen_value_match(valex, pat::PatValueLiteral, success, bound::Set{Symbol})
    lit = pat.value
    return :($valex == $(QuoteNode(lit)) ? $success : _nomatch), bound
end

function _gen_value_match(valex, pat::PatValueInterp, success, bound::Set{Symbol})
    return :($valex == $(esc(pat.expr)) ? $success : _nomatch), bound
end

function _gen_value_match(valex, pat::PatValueBind, success, bound::Set{Symbol})
    name = pat.name
    if name in bound
        return :($valex == $(esc(name)) ? $success : _nomatch), bound
    else
        return :(let $(esc(name)) = $valex
                     $success
                 end), union(bound, Set([name]))
    end
end

function _gen_value_match(valex, pat::PatValueTypedBind, success, bound::Set{Symbol})
    name = pat.name
    ty = esc(pat.ty)
    if name in bound
        return :(($valex isa $ty && $valex == $(esc(name))) ? $success : _nomatch), bound
    else
        return :(if $valex isa $ty
                     let $(esc(name)) = $valex
                         $success
                     end
                 else
                     _nomatch
                 end), union(bound, Set([name]))
    end
end

# No `_gen_step_match(::PatStepType, …)`: a `PatStepType` is always intercepted at the top of
# `_gen_path_match` / `_gen_prefix_match` (which apply the narrowing type
# assertion) before per-step dispatch is ever reached, so a step method would be
# dead code. Every step reaches position 1 in the recursion, so this holds for
# `PatStepType` anywhere in a pattern.

# The narrowing rule a `::T` pattern step applies. It lives here, beside the
# `PatStepType` it interprets, and is the single answer all four readings of that
# step call — this fragment's compiled `_gen_path_match` / `_gen_prefix_match` and
# `ReferenceRules.jl`'s interpreted `_consume` / `_match_above` — so the two DSLs
# cannot drift on what a type in a pattern means.
#
# It NARROWS where the path knows what it stands on: a recorded node type must be
# a subtype of `T`, so `queue::PacketQueue.capacity` speaks of the capacity of
# every `PacketQueue` rather than of every capacity at a queue-shaped place, and a
# stale or cross-domain path stops matching a pattern it has no business matching.
#
# It stays SILENT where the path records nothing. A `nothing` type matches: a
# plain `@reference` skeleton, a skip-bound recursion tail, and the nodes
# `reroot_reference` prepends to a child selection (built with the two-arg
# `ConcreteReference`, which records no type) are all untyped, and failing those
# would reject paths that never claimed a type rather than paths that claim the
# wrong one. A recorded value that is not a `Type` is tolerated for the same
# reason — `<:` has no answer for it, so there is nothing to narrow on.
_type_step_matches(nodetype, T) =
    nodetype === nothing || !(nodetype isa Type) || nodetype <: T

# The node type a `::T` step reads at this point in the path: the folded `type`
# field of the node reached, or `nothing` when the matcher was handed something
# that is not a `Reference` at all (the continuation rejects it on its own).
_type_step_node_type(p::Reference) = p.type
_type_step_node_type(other) = nothing

function _gen_step_match(hex, tex, step::PatStepField, rest_success, bound::Set{Symbol})
    nameexpr = :($hex.name)
    inner, bound2 = _gen_value_match(nameexpr, step.namepat, rest_success, bound)

    ex = quote
        if $hex isa ReferenceModule.FieldReferenceStep
            $inner
        else
            _nomatch
        end
    end
    return ex, bound2
end

function _gen_step_match(hex, tex, step::PatStepIndex, rest_success, bound::Set{Symbol})
    idxexpr = :($hex.start + 1)
    inner, bound2 = _gen_value_match(idxexpr, step.idxpat, rest_success, bound)

    ex = quote
        if $hex isa ReferenceModule.RangeReferenceStep && ReferenceModule.is_element_reference_step($hex)
            $inner
        else
            _nomatch
        end
    end
    return ex, bound2
end

function _gen_step_match(hex, tex, step::PatStepPosition, rest_success, bound::Set{Symbol})
    idxexpr = :($hex.start)
    inner, bound2 = _gen_value_match(idxexpr, step.idxpat, rest_success, bound)

    ex = quote
        if $hex isa ReferenceModule.RangeReferenceStep && ReferenceModule.is_position_reference_step($hex)
            $inner
        else
            _nomatch
        end
    end
    return ex, bound2
end

function _gen_step_match(hex, tex, step::PatStepRange, rest_success, bound::Set{Symbol})
    startexpr = :($hex.start)
    stopexpr = :($hex.stop)

    inner2, bound2 = _gen_value_match(stopexpr, step.stoppat, rest_success, bound)
    inner1, bound1 = _gen_value_match(startexpr, step.startpat, inner2, bound2)

    ex = quote
        if $hex isa ReferenceModule.RangeReferenceStep
            $inner1
        else
            _nomatch
        end
    end
    return ex, bound1
end

function _gen_step_match(hex, tex, step::PatStepExtension, rest_success, bound::Set{Symbol})
    match_reference_step(Val(step.name), hex, step.argpats, rest_success, bound,
                   _gen_value_match, _gen_path_match)
end

# The seam's answer for a name no package registered: this DSL is where an unknown
# `.name(…)` pattern is first reachable, so this is where it is reported.
match_reference_step(::Val{n}, hex, argpats, rest_success, bound, gvm, gpm) where {n} =
    error("no `match_reference_step(::Val{$(QuoteNode(n))}, …)` method registered — `.$(n)(…)` is not a known @reference_case step")

# `^(expr)` interpolates a whole path to compare against, so it is only meaningful as the
# *sole* step of a pattern — `_gen_path_match` / `_gen_prefix_match` intercept it there.
# Reaching per-step dispatch means it was written mid-chain (`a.^(p).b`, `a.b.^(p)`), which
# has no matching reading. Say so, rather than failing with a `MethodError` on this method
# not existing.
_gen_step_match(hex, tex, step::PatStepPathInterp, rest_success, bound::Set{Symbol}) =
    error("^(expr) path interpolation is only valid as the sole step of an @reference_case pattern: ^($(step.expr))")

function _gen_path_match(path_ex, steps::Vector{PatStep}, success, bound::Set{Symbol}=Set{Symbol}())
    # Folded references expose a navigation step directly as `head` (the type is a
    # node field), so patterns written against the navigation skeleton match the
    # path as-is — there are no interleaved checkpoint steps to skip.
    if isempty(steps)
        return :(($path_ex isa ReferenceModule.EmptyReference) ? $success : _nomatch), bound
    end

    if length(steps) == 1 && steps[1] isa PatStepWholePathBind
        name = steps[1].name
        return :(let $(esc(name)) = $path_ex; $success end), union(bound, Set([name]))
    end

    # A leading `::T` is a non-navigating **narrowing** assertion: it consumes no
    # step, and where the path records a node type that type must be `<: T` or the
    # whole rule fails and the next arm gets its chance. Where the path records no
    # type it says nothing — see `_type_step_matches` for which paths those are and
    # why they are tolerated. Matching the rest stays on the SAME path for a folded
    # node (the type is a field) and advances past an unfolded `TypeReferenceStep`
    # *step* if one is present.
    if steps[1] isa PatStepType
        ty = esc(steps[1].typeexpr)
        sp = gensym(:sp)
        rest_on_tail, b1 = _gen_path_match(:(ReferenceModule.tail($sp)), steps[2:end], success, bound)
        rest_on_same, b2 = _gen_path_match(sp, steps[2:end], success, bound)
        ex = quote
            let $sp = $path_ex
                if $sp isa ReferenceModule.ConcreteReference && ReferenceModule.head($sp) isa ReferenceModule.TypeReferenceStep
                    ReferenceModule._type_step_matches(ReferenceModule.head($sp).type, $ty) ?
                        $rest_on_tail : _nomatch
                else
                    ReferenceModule._type_step_matches(ReferenceModule._type_step_node_type($sp), $ty) ?
                        $rest_on_same : _nomatch
                end
            end
        end
        return ex, union(b1, b2)
    end

    # `::t` binds the matched node's folded `type` field to `t`, then continues
    # matching the rest on the SAME path (a folded type consumes no step, the
    # dual of construction where `::t` splices `t`'s runtime type value). Both
    # `ConcreteReference` and `EmptyReference` carry a `type` field.
    if steps[1] isa PatStepTypeBind
        name = steps[1].name
        sp = gensym(:sp)
        rest, b = _gen_path_match(sp, steps[2:end], success, union(bound, Set([name])))
        ex = quote
            let $sp = $path_ex, $(esc(name)) = $sp.type
                $rest
            end
        end
        return ex, b
    end

    if length(steps) == 1 && steps[1] isa PatStepPathInterp
        expr = esc(steps[1].expr)
        # Shape-only comparison: both sides stripped of type checkpoints so a
        # canonical path matches a plain interpolated skeleton.
        return :((ReferenceModule.strip_reference_types($path_ex) ==
                  ReferenceModule.strip_reference_types($expr)) ?
                 $success : _nomatch), bound
    end

    p = gensym(:p)
    h = gensym(:h)
    t = gensym(:t)

    rest_success, bound1 = _gen_path_match(t, steps[2:end], success, bound)
    step_success, bound2 = _gen_step_match(h, t, steps[1], rest_success, bound1)

    ex = quote
        let $p = $path_ex
            if $p isa ReferenceModule.ConcreteReference
                let $h = ReferenceModule.head($p),
                    $t = ReferenceModule.tail($p)
                    $step_success
                end
            else
                _nomatch
            end
        end
    end

    return ex, bound2
end

function _gen_prefix_match(path_ex, steps::Vector{PatStep}, success, bound::Set{Symbol}=Set{Symbol}())
    if isempty(steps)
        return :(_nomatch), bound
    end

    if length(steps) == 1 && steps[1] isa PatStepPathInterp
        expr = esc(steps[1].expr)
        # Shape-only prefix check: both sides stripped first.
        return :(ReferenceModule.is_reference_prefix(
                    ReferenceModule.strip_reference_types($path_ex),
                    ReferenceModule.strip_reference_types($expr)) ?
                 $success : _nomatch), bound
    end

    # A leading `::T` is a non-navigating **narrowing** type assertion (the same
    # `_type_step_matches` rule as in `_gen_path_match`, so the two cannot drift):
    # a recorded node type must be `<: T`, an absent one says nothing. It advances
    # past an unfolded `TypeReferenceStep` *step* if present, else matches on the
    # same path.
    if steps[1] isa PatStepType
        ty = esc(steps[1].typeexpr)
        sp = gensym(:sp)
        rest_on_tail, b1 = _gen_prefix_match(:(ReferenceModule.tail($sp)), steps[2:end], success, bound)
        rest_on_same, b2 = _gen_prefix_match(sp, steps[2:end], success, bound)
        ex = quote
            let $sp = $path_ex
                if $sp isa ReferenceModule.ConcreteReference && ReferenceModule.head($sp) isa ReferenceModule.TypeReferenceStep
                    ReferenceModule._type_step_matches(ReferenceModule.head($sp).type, $ty) ?
                        $rest_on_tail : _nomatch
                else
                    ReferenceModule._type_step_matches(ReferenceModule._type_step_node_type($sp), $ty) ?
                        $rest_on_same : _nomatch
                end
            end
        end
        return ex, union(b1, b2)
    end

    # `::t` binds the matched node's type, then continues the prefix match on the
    # same path (mirrors the `_gen_path_match` binder).
    if steps[1] isa PatStepTypeBind
        name = steps[1].name
        sp = gensym(:sp)
        rest, b = _gen_prefix_match(sp, steps[2:end], success, union(bound, Set([name])))
        ex = quote
            let $sp = $path_ex, $(esc(name)) = $sp.type
                $rest
            end
        end
        return ex, b
    end

    p = gensym(:p)
    h = gensym(:h)
    t = gensym(:t)

    rest_match, bound1 = _gen_prefix_match(t, steps[2:end], success, bound)
    step_match, bound2 = _gen_step_match(h, t, steps[1], rest_match, bound1)

    ex = quote
        let $p = $path_ex
            if $p isa ReferenceModule.EmptyReference
                $success
            elseif $p isa ReferenceModule.ConcreteReference
                let $h = ReferenceModule.head($p),
                    $t = ReferenceModule.tail($p)
                    $step_match
                end
            else
                _nomatch
            end
        end
    end

    return ex, bound2
end

function _gen_rule(rule)
    mode, pat, cond, rhs = rule

    body =
        cond === nothing ?
        esc(rhs) :
        :(if $(esc(cond))
              $(esc(rhs))
          else
              _nomatch
          end)

    if mode == :prefix
        ex, _ = _gen_prefix_match(:_ref_input, pat, body, Set{Symbol}())
    else
        ex, _ = _gen_path_match(:_ref_input, pat, body, Set{Symbol}())
    end
    return ex
end

# ------------------------------------------------------------
# Macro entry point
# ------------------------------------------------------------

"""
    @reference_case ref begin
        pattern => result
        ...
    end

Match the reference path `ref` against each `pattern => result` rule in order and
return the `result` of the first that matches, or `nothing` if none do. Patterns
use the same step grammar as `@reference` (`a.b`, `xs[i]`, `xs{k}`, a leading/suffix
`::T` checkpoint, an `.name(...)` extension step, …), with these matching conventions:

- Bare symbols in *path* position are literal field names; bare symbols in *value*
  position (inside `[]`, `field(...)`, …) **bind** the matched value.
- `_` is a wildcard; `name::T` binds `name` only if the value `isa T`; `^(expr)`
  interpolates a value to compare against.
- `when(pattern, cond)` matches `pattern` then requires the guard `cond` (which may
  read the pattern's bindings); `prefix(pattern)` matches a leading prefix rather
  than the whole path; `name...` binds the entire remaining tail; `∅` matches the
  empty (whole-element) path.

A `::T` checkpoint **narrows** the match: where the path records a node type,
that type must be `<: T` or the rule falls through to the next one, so a pattern
can speak of every node of a kind rather than of every node at a place. Where the
path records no type — a plain skeleton, a skip-bound recursion tail, the nodes
`reroot_reference` prepends — it says nothing and the match proceeds. A lowercase
`::t` still binds the type instead of asserting it.
"""
macro reference_case(ref, block)
    entries =
        block isa Expr && block.head == :block ? block.args :
        [block]

    rules = [_parse_rule(e) for e in entries if !(e isa LineNumberNode)]

    chain = :nothing
    for rule in reverse(rules)
        rule_ex = _gen_rule(rule)
        chain = quote
            let _ref_input = $(esc(ref))
                let _m = $rule_ex
                    _m === _nomatch ? $chain : _m
                end
            end
        end
    end

    return quote
        let _nomatch = Base.RefValue{Any}()
            $chain
        end
    end
end