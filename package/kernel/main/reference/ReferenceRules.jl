# Fragment of `ReferenceModule` — the `@reference_rules` DSL, the third reading of the
# reference grammar: `@reference` builds a path, `@reference_case` matches one where it
# stands, and `@reference_rules` keeps a block of `pattern => answer` arms as a **value**
# that can be stored, compared, printed and applied later.
#
# The grammar and its matching vocabulary are not re-invented here: `ReferenceSyntax.jl`
# parses the surface into the shared `RefStep` AST and `ReferenceCase.jl` lowers that AST
# into the `PatStep`/`PatValue` pattern AST. This fragment reuses that lowering and then
# does the two things a compiled case cannot:
#
#   - it **quotes the pattern as data** — every `^(…)`, every `::T` and every typed
#     binder's type is evaluated at the construction site and its *value* stored, so a
#     stored pattern holds no unevaluated expression and two rule sets compare;
#   - it **interprets** the pattern instead of emitting a match branch, because a rules
#     object may be built where no macro ran (read from a configuration, edited in the
#     editor).
#
# Interpreting a second time is the standing risk: the semantics in `_gen_path_match` /
# `_gen_above_match` and the semantics in `_consume` / `_match_above` below are one
# thing implemented twice, and the conformance corpus in `ReferenceRulesTest.jl` — the
# same corpus written once as `@reference_case` and once as rules, asserted equal — is
# what holds them together.
#
# Extension steps owned by higher packages are reached through the
# `match_reference_step_value` seam declared below, the interpreted sibling of
# `ReferenceCase.jl`'s codegen `match_reference_step`, so this fragment names no step
# type it does not own.

# `at(…)`, `below(…)`, `at_or_below(…)`, `above(…)`, `at_or_above(…)` and `when(…)` are
# surface-syntax keywords the `@reference_rules` macro recognizes *by symbol* (see
# `_parse_rules_arm`) and consumes at macroexpand time — they are never evaluated as
# functions, so the layer defines and exports nothing for them. Writing any of them
# outside `@reference_rules` is a plain `UndefVarError`.

# ------------------------------------------------------------
# The arm vocabulary
# ------------------------------------------------------------

# The five arm words are `REFERENCE_RULE_MODES`, declared in `ReferenceCase.jl` beside
# the pattern AST both matching DSLs share — `@reference_case` and `@reference_rules`
# speak one vocabulary. What this fragment adds is the **leftover** each form hands to
# a rules answer, which a compiled case has no equivalent of:
#
#   `P` / `at(P)`      the input IS P                       leftover `∅`
#   `below(P)`         the input is strictly deeper          the leftover, non-empty
#   `at_or_below(P)`   P or deeper                           the leftover, possibly `∅`
#   `above(P)`         the input is strictly shallower       leftover `∅`
#   `at_or_above(P)`   P or shallower                        leftover `∅`

# ------------------------------------------------------------
# Rules as data
# ------------------------------------------------------------

"""
    ReferenceRuleAnswer(expr)

The right-hand side of a rule, or a `when(…)` guard: an **expression**, evaluated
against what the match bound and nothing else.

The expression is the identity — it is what `==` compares, what `show` prints and what
a serializer writes. `compiled` is a cache *of* that expression, one entry per set of
binding names it has been asked to run against (a nested rule set cannot know those
names until it is applied), and is never part of what the answer *is*. What it holds is
a **name**, not code: the compiled form lives in this module's method table under a key
derived from the expression, so nothing compiled travels with the object.

An expression that is not an `Expr` or a `Symbol` — a literal, or a value spliced in
with `^(…)` at construction — is its own value and never reaches the compiler.
"""
mutable struct ReferenceRuleAnswer
    expr::Any
    compiled::Dict{Vector{Symbol}, Symbol}
end

ReferenceRuleAnswer(expr) = ReferenceRuleAnswer(expr, Dict{Vector{Symbol}, Symbol}())

"""
    ReferenceRule(mode, pattern, guard, answer)

One arm. `mode` is one of [`REFERENCE_RULE_MODES`](@ref) and says where the input must
sit relative to `pattern` (a `Vector{PatStep}`); `guard` is a `ReferenceRuleAnswer`
evaluated after a match, or `nothing`; `answer` is a `ReferenceRuleAnswer` or a nested
`ReferenceRules` that takes the leftover the mode computed.
"""
struct ReferenceRule
    mode::Symbol
    pattern::Vector{PatStep}
    guard::Union{Nothing, ReferenceRuleAnswer}
    answer::Any
end

"""
    ReferenceRules(rules)

An ordered set of [`ReferenceRule`](@ref)s, applied with [`apply_reference_rules`](@ref).

**First match wins**, in written order, and no match answers `nothing` — so appending
one set to another leaves the first in charge, and a set that must override is
prepended. Ordinary concatenation is therefore the whole override mechanism; there is
no merge operation and none is wanted.
"""
struct ReferenceRules
    rules::Vector{ReferenceRule}
end

ReferenceRules(rules::ReferenceRule...) = ReferenceRules(collect(ReferenceRule, rules))

Base.length(r::ReferenceRules) = length(r.rules)
Base.isempty(r::ReferenceRules) = isempty(r.rules)
Base.iterate(r::ReferenceRules, state...) = iterate(r.rules, state...)
Base.eltype(::Type{ReferenceRules}) = ReferenceRule

# Concatenation is the override mechanism (see the `ReferenceRules` docstring), so it is
# spelled with the operator every Julia reader already knows.
Base.vcat(a::ReferenceRules, b::ReferenceRules) = ReferenceRules(vcat(a.rules, b.rules))

# ------------------------------------------------------------
# Equality over the pattern AST
#
# A pattern is data now, so two rule sets built the same way must compare equal. Julia's
# default `==` is `===`, which separates two `PatValueLiteral("name")`s holding equal but
# distinct strings, so the pattern vocabulary gets structural equality here — beside the
# fragment that needs it, in the namespace that defines it.
# ------------------------------------------------------------

_fields_equal(a::T, b::T) where {T} = all(i -> getfield(a, i) == getfield(b, i), 1:fieldcount(T))

_fields_hash(x::T, h::UInt) where {T} =
    foldl((acc, i) -> hash(getfield(x, i), acc), 1:fieldcount(T); init = hash(T, h))

Base.:(==)(a::PatValue, b::PatValue) = typeof(a) === typeof(b) && _fields_equal(a, b)
Base.:(==)(a::PatStep, b::PatStep) = typeof(a) === typeof(b) && _fields_equal(a, b)

Base.hash(x::PatValue, h::UInt) = _fields_hash(x, h)
Base.hash(x::PatStep, h::UInt) = _fields_hash(x, h)

Base.:(==)(a::ReferenceRuleAnswer, b::ReferenceRuleAnswer) = a.expr == b.expr
Base.hash(a::ReferenceRuleAnswer, h::UInt) = hash(a.expr, hash(:ReferenceRuleAnswer, h))

Base.:(==)(a::ReferenceRule, b::ReferenceRule) =
    a.mode === b.mode && a.pattern == b.pattern && a.guard == b.guard && a.answer == b.answer
Base.hash(r::ReferenceRule, h::UInt) = _fields_hash(r, h)

Base.:(==)(a::ReferenceRules, b::ReferenceRules) = a.rules == b.rules
Base.hash(r::ReferenceRules, h::UInt) = hash(r.rules, hash(:ReferenceRules, h))

# ------------------------------------------------------------
# The extension-step seam
# ------------------------------------------------------------

"""
    match_reference_step_value(::Val{name}, step, argpats, bindings,
                               match_value, match_path) -> bindings | nothing

Match a `.name(patterns...)` pattern against an actual `step` value, for the
`@reference_rules` interpreter. The **interpreted sibling** of
[`match_reference_step`](@ref), which generates a match branch for `@reference_case`
instead: an interpreter cannot use a codegen seam, so a step type that wants to appear
in a rules pattern registers both.

`argpats` is the vector of parsed patterns (a `PatValue` for a value argument, a
`Vector{PatStep}` for a subpath argument) and `bindings` the `Dict{Symbol,Any}`
accumulated so far. Return the bindings (updated in place is fine) on a match, or
`nothing`. `match_value` and `match_path` are the callbacks so extension methods match
value and subpath patterns without reaching into kernel internals:

    match_value(value, pat, bindings)      -> bindings | nothing
    match_path(path, patsteps, bindings)   -> bindings | nothing

Each package registers a `::Val{:name}` method for its own step types; none live in the
kernel's reference layer. An unregistered name is an error the matcher raises.
"""
function match_reference_step_value end

# The seam's answer for a name whose owner registered only the codegen half: this DSL is
# where the gap is first reachable, so this is where it is reported.
match_reference_step_value(::Val{n}, step, argpats, bindings, mv, mp) where {n} =
    error("no `match_reference_step_value(::Val{$(QuoteNode(n))}, …)` method registered — " *
          "`.$(n)(…)` has a `@reference_case` matcher but no `@reference_rules` one")

# ------------------------------------------------------------
# The pattern interpreter
#
# The mirror of `_gen_path_match` / `_gen_above_match` / `_gen_step_match` /
# `_gen_value_match` in `ReferenceCase.jl`: the same semantics, executed rather than
# emitted. Every function answers the updated bindings (or the leftover path) on a
# match and `nothing` on a failure. Matching never backtracks — a step either matches or
# fails the whole arm — so bindings accumulate into one dict that is discarded whole
# when the arm fails.
# ------------------------------------------------------------

const ReferenceRuleBindings = Dict{Symbol, Any}

# A pattern binder named `_` is written to be unreadable (`@reference_case` binds it in
# a `let` no expression can name), so it is not recorded at all.
function _rule_bind!(bindings::ReferenceRuleBindings, name::Symbol, value)
    name === :_ || (bindings[name] = value)
    bindings
end

_match_value(value, pat::PatValueWildcard, b::ReferenceRuleBindings) = b

_match_value(value, pat::PatValueLiteral, b::ReferenceRuleBindings) =
    value == pat.value ? b : nothing

# A repeated binder is an equality check against what it already holds, exactly as the
# compiled matcher's `bound` set makes it.
_match_value(value, pat::PatValueBind, b::ReferenceRuleBindings) =
    haskey(b, pat.name) ? (value == b[pat.name] ? b : nothing) : _rule_bind!(b, pat.name, value)

_match_value(value, pat::PatValueGlob, b::ReferenceRuleBindings) =
    (value isa AbstractString && glob_matches(pat.pattern, value)) ? b : nothing

_match_value(value, pat::PatValueRange, b::ReferenceRuleBindings) =
    (value isa Number && pat.lo <= value <= pat.hi) ? b : nothing

# Alternatives are tried in order and the first that matches wins, so an alternation
# binds whatever its winning branch bound. A spliced collection stands for its elements:
# `any(^(allowed))` is the form that exists because the alternatives may only be known at
# run time, and comparing a value to a whole collection would never match anything.
function _match_value(value, pat::PatValueAny, b::ReferenceRuleBindings)
    for alt in pat.alternatives
        matched = _match_alternative(value, alt, b)
        matched === nothing || return matched
    end
    nothing
end

_match_alternative(value, alt::PatValue, b::ReferenceRuleBindings) = _match_value(value, alt, b)

_match_alternative(value, alt::PatValueLiteral, b::ReferenceRuleBindings) =
    _is_alternative_set(alt.value) ? (value in alt.value ? b : nothing) :
    (value == alt.value ? b : nothing)

# What counts as "a collection of alternatives" rather than one value. A string is a
# value: `any(^("abc"))` means the name `abc`, not one of three letters.
_is_alternative_set(x) = (x isa AbstractVector || x isa Tuple || x isa AbstractSet ||
                          x isa AbstractRange)

_match_value(value, pat::PatValueTypedBind, b::ReferenceRuleBindings) =
    !(value isa pat.ty) ? nothing :
    haskey(b, pat.name) ? (value == b[pat.name] ? b : nothing) : _rule_bind!(b, pat.name, value)

# `^(e)` is evaluated at construction and stored as a `PatValueLiteral`, so an interp
# node in a *stored* pattern is a pattern that was built by hand and left unfinished.
_match_value(value, pat::PatValueInterp, b::ReferenceRuleBindings) =
    error("a stored @reference_rules pattern still holds an unevaluated ^($(pat.expr)) — " *
          "interpolation is evaluated at construction, so store the value")

_match_step(h, step::PatStepField, b::ReferenceRuleBindings) =
    h isa FieldReferenceStep ? _match_value(h.name, step.namepat, b) : nothing

_match_step(h, step::PatStepIndex, b::ReferenceRuleBindings) =
    (h isa RangeReferenceStep && is_element_reference_step(h)) ?
    _match_value(h.start + 1, step.idxpat, b) : nothing

_match_step(h, step::PatStepPosition, b::ReferenceRuleBindings) =
    (h isa RangeReferenceStep && is_position_reference_step(h)) ?
    _match_value(h.start, step.idxpat, b) : nothing

function _match_step(h, step::PatStepRange, b::ReferenceRuleBindings)
    h isa RangeReferenceStep || return nothing
    b1 = _match_value(h.start, step.startpat, b)
    b1 === nothing ? nothing : _match_value(h.stop, step.stoppat, b1)
end

# `_` — one step, whatever it is. The caller has already established there is one.
_match_step(h, ::PatStepAny, b::ReferenceRuleBindings) = b

_match_step(h, step::PatStepExtension, b::ReferenceRuleBindings) =
    match_reference_step_value(Val(step.name), h, step.argpats, b, _match_value, _match_subpath)

# The subpath callback handed to an extension step: a whole subpath pattern, matched
# exactly (the codegen seam's `gen_path_match` continues with the rest, which in direct
# style is just "the outer walk carries on").
_match_subpath(path, steps::Vector{PatStep}, b::ReferenceRuleBindings) =
    _consume(path, steps, b, _accept_exhausted) === nothing ? nothing : b

# What an arm word asks of the leftover, as a predicate. It is threaded *into* the walk
# rather than applied to its answer, because a gap has to search: a gap that consumed
# the wrong amount can leave an unacceptable leftover where a different amount would
# have left an acceptable one, and only the arm word knows the difference.
_accept_exhausted(leftover::Reference) = leftover isa EmptyReference
_accept_deeper(leftover::Reference) = leftover isa ConcreteReference
_accept_anything(leftover::Reference) = true

_leftover_acceptor(mode::Symbol) =
    mode === :at ? _accept_exhausted :
    mode === :below ? _accept_deeper :
    _accept_anything          # :at_or_below

"""
    _consume(path, steps, bindings, accept) -> leftover::Reference | nothing

Match `steps` against a **leading segment** of `path`, answering the part of `path` left
over — but only a leftover `accept` holds for. This is the primitive behind `at`
(exhausted), `below` (non-empty) and `at_or_below` (anything).
"""
function _consume(path::Reference, steps::Vector{PatStep}, b::ReferenceRuleBindings,
                  accept::Function)
    isempty(steps) && return accept(path) ? path : nothing
    step = steps[1]
    rest = steps[2:end]

    # `any(P, Q, …)` — the alternatives are tried in order, each followed by whatever
    # comes after the alternation, so a branch is judged by whether the *whole* pattern
    # goes through. Each attempt gets its own bindings, since a failed branch must leave
    # nothing behind.
    if step isa PatStepAlt
        for alternative in step.alternatives
            attempt = copy(b)
            leftover = _consume(path, vcat(alternative, rest), attempt, accept)
            if leftover !== nothing
                empty!(b)
                merge!(b, attempt)
                return leftover
            end
        end
        return nothing
    end

    # `__` — any run of steps. The one step whose match is a search, and the reason
    # `accept` is carried this far down. Greedy takes the longest run first and lazy
    # (`__ʔ`) the shortest; either way the first run whose remainder matches wins, so a
    # gap changes which member of the pattern's set is the witness, never whether one
    # exists. Each attempt gets its own bindings, since a failed one must leave nothing
    # behind.
    if step isa PatStepGap
        depth = length(path)
        for taken in (step.lazy ? (0:depth) : (depth:-1:0))
            attempt = copy(b)
            skipped = _drop_navigation_steps(path, taken)
            skipped === nothing && continue
            step.name === nothing || _rule_bind!(attempt, step.name, _take_leading_steps(path, taken))
            leftover = _consume(skipped, rest, attempt, accept)
            if leftover !== nothing
                empty!(b)
                merge!(b, attempt)
                return leftover
            end
        end
        return nothing
    end

    # A `::T` checkpoint is non-navigating and **narrowing**: where the path records a
    # node type it must be `<: T`, where it records none the step says nothing. The rule
    # is `_type_step_matches`, the same predicate `ReferenceCase.jl`'s codegen calls, so
    # the compiled and interpreted readings cannot drift. Matching continues on the SAME
    # path for a folded node (the type is a field, consuming no step) and past an
    # unfolded `TypeReferenceStep` *step* if one is present.
    if step isa PatStepType
        if path isa ConcreteReference && head(path) isa TypeReferenceStep
            return _type_step_matches(head(path).type, step.typeexpr) ?
                   _consume(tail(path), rest, b, accept) : nothing
        end
        return _type_step_matches(_type_step_node_type(path), step.typeexpr) ?
               _consume(path, rest, b, accept) : nothing
    end

    # `::t` binds the node's folded `type` field and continues on the same path. Both
    # reference types carry a `type` field.
    if step isa PatStepTypeBind
        _rule_bind!(b, step.name, path.type)
        return _consume(path, rest, b, accept)
    end

    # `name...` (and the `_` arm) binds the entire remaining path and consumes it.
    if step isa PatStepWholePathBind
        isempty(rest) ||
            error("`$(step.name)...` binds the remaining path, so it must be the last step of a pattern")
        _rule_bind!(b, step.name, path)
        return accept(EmptyReference()) ? EmptyReference() : nothing
    end

    # `^(p)` interpolates a whole path, so it is only meaningful as the sole step. The
    # comparison is shape-only — both sides stripped — so a canonical path matches a
    # plain skeleton; the leftover keeps the input's folded types.
    if step isa PatStepPathInterp
        isempty(rest) ||
            error("^(path) interpolation is only valid as the sole step of an @reference_rules pattern")
        leftover = _consume_path(path, step.expr)
        return (leftover !== nothing && accept(leftover)) ? leftover : nothing
    end

    path isa ConcreteReference || return nothing
    stepped = _match_step(head(path), step, b)
    stepped === nothing && return nothing
    _consume(tail(path), rest, stepped, accept)
end

# Consume an interpolated path `sub` from the front of `path`, shape-only. The step walk
# is over the stripped forms (so an unfolded checkpoint step on either side is
# invisible), and the leftover is taken from `path` itself so folded node types survive
# into a delegated rule set.
function _consume_path(path::Reference, sub)
    sub isa Reference ||
        error("^(path) in an @reference_rules pattern must interpolate a Reference, got $(typeof(sub))")
    stripped_path = strip_reference_types(path)
    stripped_sub = strip_reference_types(sub)
    consumed = 0
    while stripped_sub isa ConcreteReference
        stripped_path isa ConcreteReference || return nothing
        head(stripped_path) == head(stripped_sub) || return nothing
        stripped_path = tail(stripped_path)
        stripped_sub = tail(stripped_sub)
        consumed += 1
    end
    _drop_navigation_steps(path, consumed)
end

# Drop `n` navigation steps from the front of `path`, stepping over any unfolded
# checkpoint step on the way (those are invisible to the shape walk above).
function _drop_navigation_steps(path::Reference, n::Int)
    while n > 0
        path isa ConcreteReference || return nothing
        head(path) isa TypeReferenceStep || (n -= 1)
        path = tail(path)
    end
    while path isa ConcreteReference && head(path) isa TypeReferenceStep
        path = tail(path)
    end
    path
end

# The mirror of `_drop_navigation_steps`: the first `n` navigation steps as a path of
# their own, folded node types and all. What a bound gap (`__(owner)`) is given.
function _take_leading_steps(path::Reference, n::Int)
    n == 0 && return EmptyReference(path.type)
    path isa ConcreteReference || return EmptyReference()
    taken = head(path) isa TypeReferenceStep ? n : n - 1
    ConcreteReference(path.type, head(path), _take_leading_steps(tail(path), taken))
end

"""
    _match_above(path, steps, bindings) -> Bool

True when `path` runs out **inside** `steps` — the input is strictly shallower than the
pattern. The mirror of `_gen_above_match`, down to the order its branches are tried in,
because that order is observable: a leading `::T` is consulted before the path is tested
for emptiness.
"""
function _match_above(path::Reference, steps::Vector{PatStep}, b::ReferenceRuleBindings)
    isempty(steps) && return false
    step = steps[1]
    rest = steps[2:end]

    # Reaching a gap settles it. A gap is unbounded, so whatever is left of the input can
    # be absorbed by it and the pattern still has a member that continues past — which is
    # exactly "the input is a proper prefix of some member". Nothing after the gap needs
    # examining, and a bound gap has nothing well-defined to bind here, since the run it
    # would name is the part of a member the input never reached.
    if step isa PatStepAlt
        for alternative in step.alternatives
            attempt = copy(b)
            if _match_above(path, vcat(alternative, rest), attempt)
                empty!(b)
                merge!(b, attempt)
                return true
            end
        end
        return false
    end

    if step isa PatStepGap
        # A named gap binds what it covered — which here is whatever is left of the
        # input, since that is the part of the member the input reached before running
        # out. Without this a bound gap under an above-arm would leave its name unbound
        # and the answer would fail reading it.
        step.name === nothing || _rule_bind!(b, step.name, path)
        return true
    end

    if step isa PatStepType
        if path isa ConcreteReference && head(path) isa TypeReferenceStep
            return _type_step_matches(head(path).type, step.typeexpr) &&
                   _match_above(tail(path), rest, b)
        end
        return _type_step_matches(_type_step_node_type(path), step.typeexpr) &&
               _match_above(path, rest, b)
    end

    if step isa PatStepTypeBind
        _rule_bind!(b, step.name, path.type)
        return _match_above(path, rest, b)
    end

    if step isa PatStepPathInterp
        isempty(rest) ||
            error("^(path) interpolation is only valid as the sole step of an @reference_rules pattern")
        step.expr isa Reference ||
            error("^(path) in an @reference_rules pattern must interpolate a Reference, got $(typeof(step.expr))")
        return is_reference_prefix(strip_reference_types(path), strip_reference_types(step.expr))
    end

    # A whole-path bind is a pattern of unbounded length, so every input runs out inside
    # it.
    if step isa PatStepWholePathBind
        _rule_bind!(b, step.name, path)
        return true
    end

    path isa EmptyReference && return true
    path isa ConcreteReference || return false
    stepped = _match_step(head(path), step, b)
    stepped === nothing && return false
    _match_above(tail(path), rest, stepped)
end

# Match one arm, answering `(bindings, leftover)` or `nothing`. The leftover is what a
# rules answer is applied to; every above-form leaves nothing of the input over.
function _match_rule(rule::ReferenceRule, path::Reference)
    _match_pattern(rule.mode, rule.pattern, path)
end

# Match one arm's pattern, answering `(bindings, leftover)` or `nothing`. Every
# above-form leaves nothing of the input over.
function _match_pattern(mode::Symbol, pattern::Vector{PatStep}, path::Reference)
    b = ReferenceRuleBindings()
    if mode === :above || mode === :at_or_above
        _match_above(path, pattern, b) && return (b, EmptyReference())
        mode === :above && return nothing
        b = ReferenceRuleBindings()
        leftover = _consume(path, pattern, b, _accept_exhausted)
        return leftover === nothing ? nothing : (b, leftover)
    end
    leftover = _consume(path, pattern, b, _leftover_acceptor(mode))
    leftover === nothing ? nothing : (b, leftover)
end

"""
    match_reference_pattern(mode, pattern, reference) -> bindings | nothing

Match one arm's `pattern` against `reference` under an arm word (`:at`, `:below`,
`:at_or_below`, `:above`, `:at_or_above`), answering the `Dict{Symbol,Any}` the match
bound, or `nothing`.

This is the **one matcher both DSLs use**. `@reference_rules` reaches it through
[`apply_reference_rules`](@ref); `@reference_case` compiles the patterns it can into
straight-line branches and calls this for the ones whose match is a search, then reopens
the bindings as ordinary locals for its own escaped result expression. So a pattern
means one thing, whichever DSL it is written in and whichever way it is executed.
"""
function match_reference_pattern(mode::Symbol, pattern::Vector{PatStep}, reference::Reference)
    matched = _match_pattern(mode, pattern, reference)
    matched === nothing ? nothing : matched[1]
end

match_reference_pattern(::Symbol, ::Vector{PatStep}, ::Nothing) = nothing

# ------------------------------------------------------------
# Answer evaluation
#
# An answer is evaluated against what its own pattern bound and what the arms above it
# bound, and nothing else: it is compiled in this module, so a free name resolves here
# rather than at the site the rules were written. Anything from that site travels by
# `^(…)`, which is evaluated at construction — that is what keeps the object closed.
# ------------------------------------------------------------

# The compiled form of an answer: one method of this generic per (expression, binding
# names) pair, keyed by a `Val` of a name derived from that pair. The **method table is
# the cache**, and the key is content-addressed rather than minted from a counter, so a
# rule set that crossed a process boundary — or a `serialize`/`deserialize` round trip —
# looks its own key up, finds no method, and compiles it again. Nothing compiled ever
# travels with the object; caching a function *in* the answer would put a closure type
# on the wire, which no other process can read back.
function _run_reference_rule_answer end

_answer_key(expr, names::Vector{Symbol}) = Symbol(repr(expr), "|", join(names, ","))

_answer_method(key::Symbol, expr, names::Vector{Symbol}) =
    :(function _run_reference_rule_answer(::Val{$(QuoteNode(key))}, __bindings)
          $(Expr(:let,
                 Expr(:block, (:($n = __bindings[$(QuoteNode(n))]) for n in names)...),
                 Expr(:block, expr)))
      end)

function _evaluate_answer(answer::ReferenceRuleAnswer, b::ReferenceRuleBindings)
    expr = answer.expr
    # A quoted symbol is the commonest answer of all (`=> :hit`) and is its own value.
    expr isa QuoteNode && return expr.value
    # A literal, or a value spliced in with `^(…)`: its own value, never compiled.
    (expr isa Expr || expr isa Symbol) || return expr
    expr isa Symbol && haskey(b, expr) && return b[expr]
    names = sort!(collect(keys(b)))
    key = get!(() -> _answer_key(expr, names), answer.compiled, names)
    hasmethod(_run_reference_rule_answer, Tuple{Val{key}, ReferenceRuleBindings}) ||
        Core.eval(@__MODULE__, _answer_method(key, expr, names))
    # The method may have been defined in this very world, so calling it from a method
    # compiled earlier is the world-age error waiting to happen.
    Base.invokelatest(_run_reference_rule_answer, Val(key), b)
end

# ------------------------------------------------------------
# Applying
# ------------------------------------------------------------

"""
    apply_reference_rules(rules::ReferenceRules, reference) -> answer | nothing

Answer what `rules` says about `reference`: the first arm whose form, pattern and guard
all hold, with its answer evaluated against the bindings the match produced. `nothing`
when no arm matches — and when `reference` is `nothing`, since a rule set says nothing
about the absence of a selection.

An arm whose answer is a nested `ReferenceRules` delegates: the leftover its own form
computed is asked of them, with the bindings so far still in scope, so a set written
about one place can be applied at several places.

    rules = @reference_rules begin
        buckets[2].capacity => 20
        buckets[i].capacity => 10 * i          # i is bound by the match
    end

    apply_reference_rules(rules, reference)
"""
apply_reference_rules(rules::ReferenceRules, reference::Reference) =
    _apply_reference_rules(rules, reference, ReferenceRuleBindings())

apply_reference_rules(::ReferenceRules, ::Nothing) = nothing

function _apply_reference_rules(rules::ReferenceRules, reference::Reference,
                                outer::ReferenceRuleBindings)
    for rule in rules.rules
        matched = _match_rule(rule, reference)
        matched === nothing && continue
        bindings, leftover = matched
        # An arm's own bindings shadow the ones the arms above it made.
        isempty(outer) || (bindings = merge(outer, bindings))
        if rule.guard !== nothing
            held = _evaluate_answer(rule.guard, bindings)
            held isa Bool ||
                error("a when(…) guard must answer a Bool, got $(typeof(held))")
            held || continue
        end
        answer = rule.answer
        answer isa ReferenceRules && return _apply_reference_rules(answer, leftover, bindings)
        return _evaluate_answer(answer, bindings)
    end
    nothing
end

# ------------------------------------------------------------
# Display — the surface syntax the object was written in
# ------------------------------------------------------------

function Base.show(io::IO, rules::ReferenceRules)
    _show_rules(io, rules, "")
end

function _show_rules(io::IO, rules::ReferenceRules, indent::String)
    if isempty(rules.rules)
        print(io, "@reference_rules begin end")
        return
    end
    println(io, "@reference_rules begin")
    inner = indent * "    "
    for rule in rules.rules
        print(io, inner)
        _show_rule(io, rule, inner)
        println(io)
    end
    print(io, indent, "end")
end

function _show_rule(io::IO, rule::ReferenceRule, indent::String)
    guarded = rule.guard !== nothing
    guarded && print(io, "when(")
    if rule.mode === :at
        _show_pattern(io, rule.pattern)
    else
        print(io, rule.mode, "(")
        _show_pattern(io, rule.pattern)
        print(io, ")")
    end
    if guarded
        print(io, ", ")
        _show_answer(io, rule.guard)
        print(io, ")")
    end
    print(io, " => ")
    if rule.answer isa ReferenceRules
        _show_rules(io, rule.answer, indent)
    else
        _show_answer(io, rule.answer)
    end
end

# An expression prints as itself; anything else is a value that reached the object by
# `^(…)` or as a literal, and prints as the value it is.
function _show_answer(io::IO, answer::ReferenceRuleAnswer)
    expr = answer.expr
    if expr isa QuoteNode
        show(io, expr.value)
    elseif expr isa Expr || expr isa Symbol
        print(io, expr)
    else
        show(io, expr)
    end
end

function _show_pattern(io::IO, steps::Vector{PatStep})
    isempty(steps) && return print(io, "∅")
    for (i, step) in enumerate(steps)
        _show_pat_step(io, step, i == 1)
    end
end

function _show_pat_step(io::IO, step::PatStepField, first::Bool)
    if step.namepat isa PatValueLiteral && step.namepat.value isa AbstractString
        first || print(io, ".")
        print(io, step.namepat.value)
    else
        print(io, ".field(")
        _show_pat_value(io, step.namepat)
        print(io, ")")
    end
end

_show_pat_step(io::IO, step::PatStepIndex, first::Bool) =
    (print(io, "["); _show_pat_value(io, step.idxpat); print(io, "]"))

_show_pat_step(io::IO, step::PatStepPosition, first::Bool) =
    (print(io, "{"); _show_pat_value(io, step.idxpat); print(io, "}"))

_show_pat_step(io::IO, step::PatStepRange, first::Bool) =
    (print(io, "{"); _show_pat_value(io, step.startpat); print(io, ":");
     _show_pat_value(io, step.stoppat); print(io, "}"))

_show_pat_step(io::IO, step::PatStepType, first::Bool) =
    print(io, "::", step.typeexpr isa Type ? nameof(step.typeexpr) : step.typeexpr)

_show_pat_step(io::IO, step::PatStepTypeBind, first::Bool) = print(io, "::", step.name)

_show_pat_step(io::IO, step::PatStepWholePathBind, first::Bool) =
    step.name === :_ ? print(io, "_") : print(io, first ? "" : ".", step.name, "...")

_show_pat_step(io::IO, ::PatStepAny, first::Bool) = print(io, first ? "" : ".", "_")

function _show_pat_step(io::IO, step::PatStepAlt, first::Bool)
    print(io, first ? "" : ".", "any(")
    for (i, alternative) in enumerate(step.alternatives)
        i == 1 || print(io, ", ")
        _show_pattern(io, alternative)
    end
    print(io, ")")
end

function _show_pat_step(io::IO, step::PatStepGap, first::Bool)
    print(io, first ? "" : ".", "__", step.lazy ? "ʔ" : "")
    step.name === nothing || print(io, "(", step.name, ")")
end

_show_pat_step(io::IO, step::PatStepPathInterp, first::Bool) =
    (print(io, first ? "" : ".", "^("); show(io, step.expr); print(io, ")"))

function _show_pat_step(io::IO, step::PatStepExtension, first::Bool)
    print(io, first ? "" : ".", step.name, "(")
    for (i, arg) in enumerate(step.argpats)
        i == 1 || print(io, ", ")
        arg isa PatValue ? _show_pat_value(io, arg) : _show_pattern(io, arg)
    end
    print(io, ")")
end

_show_pat_value(io::IO, pat::PatValueWildcard) = print(io, "_")
_show_pat_value(io::IO, pat::PatValueBind) = print(io, pat.name)
_show_pat_value(io::IO, pat::PatValueTypedBind) =
    print(io, pat.name, "::", pat.ty isa Type ? nameof(pat.ty) : pat.ty)
_show_pat_value(io::IO, pat::PatValueLiteral) = show(io, pat.value)
_show_pat_value(io::IO, pat::PatValueInterp) = print(io, "^(", pat.expr, ")")
_show_pat_value(io::IO, pat::PatValueRange) = print(io, pat.lo, "..", pat.hi)
_show_pat_value(io::IO, pat::PatValueGlob) = print(io, "glob\"", pat.pattern, "\"")
function _show_pat_value(io::IO, pat::PatValueAny)
    print(io, "any(")
    for (i, alt) in enumerate(pat.alternatives)
        i == 1 || print(io, ", ")
        _show_pat_value(io, alt)
    end
    print(io, ")")
end

# ------------------------------------------------------------
# Quoting a pattern as data
#
# The macro's other half. `ReferenceCase.jl`'s lowering answers a pattern AST whose
# interpolation slots hold *expressions* for a macro to escape; a rules object must hold
# *values*, so each `_quote_*` below emits the code that builds its node, with every
# `^(…)`, every `::T` and every typed binder's type escaped so the construction site
# evaluates it exactly once. The type objects are interpolated directly, so the emitted
# code needs no name in scope at the call site.
# ------------------------------------------------------------

_quote_pattern(steps::Vector{PatStep}) = :($PatStep[$(map(_quote_pat_step, steps)...)])

_quote_pat_step(step::PatStepField) = :($PatStepField($(_quote_pat_value(step.namepat))))
_quote_pat_step(step::PatStepIndex) = :($PatStepIndex($(_quote_pat_value(step.idxpat))))
_quote_pat_step(step::PatStepPosition) = :($PatStepPosition($(_quote_pat_value(step.idxpat))))
_quote_pat_step(step::PatStepRange) =
    :($PatStepRange($(_quote_pat_value(step.startpat)), $(_quote_pat_value(step.stoppat))))
_quote_pat_step(step::PatStepType) = :($PatStepType($(esc(step.typeexpr))))
_quote_pat_step(step::PatStepTypeBind) = :($PatStepTypeBind($(QuoteNode(step.name))))
_quote_pat_step(step::PatStepWholePathBind) = :($PatStepWholePathBind($(QuoteNode(step.name))))
_quote_pat_step(::PatStepAny) = :($PatStepAny())
_quote_pat_step(step::PatStepAlt) =
    :($PatStepAlt(Vector{$PatStep}[$(map(_quote_pattern, step.alternatives)...)]))
_quote_pat_step(step::PatStepGap) = :($PatStepGap($(QuoteNode(step.name)), $(step.lazy)))
_quote_pat_step(step::PatStepPathInterp) = :($PatStepPathInterp($(esc(step.expr))))
_quote_pat_step(step::PatStepExtension) =
    :($PatStepExtension($(QuoteNode(step.name)), Any[$(map(_quote_pat_arg, step.argpats)...)]))

_quote_pat_arg(arg::PatValue) = _quote_pat_value(arg)
_quote_pat_arg(arg::Vector{PatStep}) = _quote_pattern(arg)

_quote_pat_value(pat::PatValueWildcard) = :($PatValueWildcard())
_quote_pat_value(pat::PatValueBind) = :($PatValueBind($(QuoteNode(pat.name))))
_quote_pat_value(pat::PatValueTypedBind) =
    :($PatValueTypedBind($(QuoteNode(pat.name)), $(esc(pat.ty))))
_quote_pat_value(pat::PatValueLiteral) = :($PatValueLiteral($(QuoteNode(pat.value))))
# Both bounds are evaluated at the construction site, like every other interpolation.
_quote_pat_value(pat::PatValueGlob) = :($PatValueGlob($(pat.pattern)))
_quote_pat_value(pat::PatValueRange) = :($PatValueRange($(esc(pat.lo)), $(esc(pat.hi))))
_quote_pat_value(pat::PatValueAny) =
    :($PatValueAny($PatValue[$(map(_quote_pat_value, pat.alternatives)...)]))
# `^(e)` in a pattern is a value to compare against, so the construction site evaluates
# it and the object stores the value — the pattern keeps no expression.
_quote_pat_value(pat::PatValueInterp) = :($PatValueLiteral($(esc(pat.expr))))

# ------------------------------------------------------------
# Quoting an answer as data
# ------------------------------------------------------------

# Build the code that reconstructs `ex` as data at the construction site, with every
# `^(e)` replaced by the *value* of `e` there. Line numbers are dropped: they are not
# part of what an answer is, and they would separate two answers written the same.
function _quote_answer_expr(ex)
    if ex isa Expr && ex.head === :call && length(ex.args) == 2 && ex.args[1] === :(^)
        return esc(ex.args[2])
    elseif ex isa Expr
        args = [_quote_answer_expr(a) for a in ex.args if !(a isa LineNumberNode)]
        return :($Expr($(QuoteNode(ex.head)), $(args...)))
    else
        return QuoteNode(ex)
    end
end

# A spliced rule set is an answer that delegates; anything else is an expression.
_make_reference_rule_answer(value::ReferenceRules) = value
_make_reference_rule_answer(value) = ReferenceRuleAnswer(value)

# ------------------------------------------------------------
# Arm parsing
# ------------------------------------------------------------

# The pattern of an arm, in the matching reading of the shared grammar, plus the two
# whole-path forms that have no path syntax of their own.
function _rules_pattern(ex)
    if ex === :∅
        # A path that terminates *at* the element — a whole-element selection. The empty
        # pattern consumes nothing, so `at(∅)` holds exactly for an `EmptyReference`.
        return PatStep[]
    elseif ex isa Expr && ex.head === :(::) && length(ex.args) == 2 && ex.args[1] === :∅
        return PatStep[_pat_type_step(ex.args[2])]
    end
    _parse_path(ex)
end

function _parse_rules_arm(ex)
    ex isa Expr && ex.head === :call && ex.args[1] == :(=>) ||
        error("expected `pattern => answer`, got: $ex")

    lhs, rhs = ex.args[2], ex.args[3]
    guard = nothing

    if lhs isa Expr && lhs.head === :call && lhs.args[1] === :when
        length(lhs.args) == 3 || error("when(pattern, cond) expects exactly two arguments")
        guard = lhs.args[3]
        lhs = lhs.args[2]
    end

    # A bare `_` arm is the retired catch-all, so it raises rather than quietly
    # becoming "any one-step path". Only the un-worded arm is guarded: `at(_)` says
    # one step deliberately, and is how the new meaning is written meanwhile.
    lhs === :_ && error(REFERENCE_RETIRED_CATCH_ALL)

    mode = :at
    if lhs isa Expr && lhs.head === :call && lhs.args[1] in REFERENCE_RULE_MODES
        length(lhs.args) == 2 ||
            error("$(lhs.args[1])(path) expects exactly one argument")
        mode = lhs.args[1]
        lhs = lhs.args[2]
    elseif lhs isa Expr && lhs.head === :call && lhs.args[1] === :prefix
        error("`prefix(…)` is not an arm word — write `above(…)` for \"the input stops " *
              "inside the pattern\", or `at_or_below(…)` to match a leading segment of " *
              "the input")
    end

    (mode, _rules_pattern(lhs), guard, rhs)
end

function _quote_rule(arm)
    mode, pattern, guard, answer = arm
    guardex = guard === nothing ? :nothing :
              :($ReferenceRuleAnswer($(_quote_answer_expr(guard))))
    :($ReferenceRule($(QuoteNode(mode)), $(_quote_pattern(pattern)), $guardex,
                     $_make_reference_rule_answer($(_quote_answer_expr(answer)))))
end

# ------------------------------------------------------------
# Macro entry point
# ------------------------------------------------------------

"""
    @reference_rules begin
        pattern => answer
        ...
    end

Build a [`ReferenceRules`](@ref) — the same block of arms `@reference_case` would match
with, kept as a **value** that can be stored, compared, printed and applied later with
[`apply_reference_rules`](@ref). A configuration is a set of rules about things that do
not exist yet, which is what a compiled case cannot be.

    rules = @reference_rules begin
        buckets[2].capacity => 20
        buckets[i].capacity => 10 * i          # i is bound by the match
    end

Patterns use the step grammar of `@reference` and the matching conventions of
`@reference_case`: bare symbols in *path* position are field names and in *value*
position **bind**; `_` is a wildcard, `name::T` binds only if the value `isa T`, `^(expr)`
interpolates a value to compare against, `name...` binds the remaining path, `∅` matches
the whole-element (empty) path, and `when(pattern, cond)` adds a guard. A capitalised
`::T` in *path* position **narrows**: where the input records a node type it must be
`<: T`, and where it records none the step says nothing.

Each arm says where the **input** sits relative to its pattern `P`:

| arm | holds when | leftover a rules answer receives |
| --- | --- | --- |
| `P` / `at(P)` | the input **is** `P` | `∅` |
| `below(P)` | the input is strictly deeper | the leftover |
| `at_or_below(P)` | `P` or deeper | the leftover, possibly `∅` |
| `above(P)` | the input is strictly shallower | `∅` |
| `at_or_above(P)` | `P` or shallower | `∅` |

The same five words say the same five things in `@reference_case`; what only a rules
object has is the leftover column, which a nested rule set is applied to.

**First match wins** and no match answers `nothing`, so concatenating two sets leaves the
first in charge and prepending is how a set overrides another.

An answer that is a rule set **delegates**: it is asked the leftover the arm computed,
with the bindings so far still in scope, so one set can be applied at several places.

    node = @reference_rules begin
        queue.capacity => 100
    end

    @reference_rules begin
        at_or_below(hosts[_]::WirelessHost) => ^(node)     # by kind, not by place
    end

The object is **closed**: an answer is evaluated against what the match bound and
nothing else, and its free names resolve in `ReferenceModule`, not at the site the rules
were written. `^(…)` is the one channel from that site — on the left of `=>` it
interpolates a value to compare against, on the right it evaluates at construction and
splices the value in, nested rule sets included.
"""
macro reference_rules(block)
    entries = block isa Expr && block.head === :block ? block.args : [block]
    arms = [_parse_rules_arm(e) for e in entries if !(e isa LineNumberNode)]
    :($ReferenceRules($ReferenceRule[$(map(_quote_rule, arms)...)]))
end
