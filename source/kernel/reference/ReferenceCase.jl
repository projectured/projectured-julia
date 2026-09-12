# Fragment of `ReferenceModule` — the `@reference_case` pattern-matching DSL, the
# destructuring counterpart of the `@reference` construction DSL
# (`ReferenceBuilder.jl`).
#
# This fragment is a **lowering**, not a parser: the surface grammar both DSLs accept is
# parsed once by `ReferenceSyntax.jl` into the shared `ReferenceSyntaxStep` AST, and everything here
# turns that AST into match branches. What makes the matching reading its own thing is the
# *value* vocabulary below (`PatValue`: wildcards, binders, typed binders, interpolation)
# — a bare symbol binds here where it would name a field in the builder.
#
# Extension steps owned by higher packages are reached through the `match_reference_step` /
# `get_reference_step_subpath_args` seams declared in `ReferenceInterface.jl`, so this fragment names no step
# type it does not own.

# `when(pattern, cond)` and the five arm words below are surface-syntax keywords the
# `@reference_case` macro recognizes *by symbol* (see `_parse_rule`) and consumes at
# macroexpand time — they are never evaluated as functions, so the layer defines and
# exports nothing for them. Writing any of them outside `@reference_case` (or
# `@reference_rules`) is a plain `UndefVarError`. See the `@reference_case` docstring
# for what they mean.

# ------------------------------------------------------------
# The arm vocabulary
# ------------------------------------------------------------

# Where the **input** sits relative to the pattern `P`. The five forms are the whole
# lattice of prefix relations between a path and a pattern:
#
#   `P` / `at(P)`      the input IS P
#   `below(P)`         the input is strictly deeper
#   `within(P)`   P or deeper
#   `above(P)`         the input is strictly shallower — it runs out *inside* P
#   `toward(P)`   P or shallower
#
# One word cannot carry both directions, which is why there is no `prefix(…)`: it
# named `above(…)` while reading as though it meant `within(…)`.
#
# The constant lives here, beside the `PatStep` AST both matching DSLs lower to, and
# `ReferenceRules.jl` reads it from here — the two vocabularies are one vocabulary.
const REFERENCE_RULE_MODES = (:at, :below, :within, :above, :toward)

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

# `lo..hi` — a number within an inclusive range, the reading an ini file's `{38..47}`
# has. Both bounds are evaluated at the construction site, so a stored pattern holds
# values rather than expressions (as `^(…)` and `::T` do).
#
# The syntax already parsed: a value slot keeps its Julia expression raw, so `xs[0..3]`
# reached the matcher as an interpolation and was compared against an `Int`, which never
# matched. This gives the slot its meaning rather than adding syntax.
struct PatValueRange <: PatValue
    lo
    hi
end

# `glob"host*"` — a **character** pattern over one step's name, which is what an ini
# key says with `host*` or `mac{a-c}`. See `glob_matches` for the language.
struct PatValueGlob <: PatValue
    pattern::String
end

# `any(a, b, …)` — the value matches any one of the alternatives, tried in order. An
# alternative that is a spliced collection (`any(^(allowed))`) contributes each of its
# elements, which is the whole point: *N* arms cannot be written when *N* is a runtime
# value, so the alternatives have to be able to arrive as data.
struct PatValueAny <: PatValue
    alternatives::Vector{PatValue}
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

# `numbering` is the surface bracket the pattern was written with, and it decides
# what `startpat` is matched against: `:element` (`xs[i, j]`) reads the 1-based
# first element, `start + 1`, and `:gap` (`xs{s:e}`) reads the step's own 0-based
# `start`. `stoppat` reads `stop` either way, because the last element's 1-based
# index and the gap after it are the same number.
struct PatStepRange <: PatStep
    startpat::PatValue
    stoppat::PatValue
    numbering::Symbol
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

# `__` — **any run of steps, possibly none**, the counterpart of an ini file's `**`.
# It is what makes a pattern denote a *set* of paths rather than one path, and it is
# the only step whose match is a search: everything else either matches the step in
# front of it or fails.
#
# `name` is the run's binder (`__(owner)`) or `nothing`; `lazy` reverses this one gap's
# preference (`__ʔ`). A gap is **greedy** by default — it takes as much as it can while
# letting the rest of the pattern match — which agrees with "the deepest match wins".
# Greediness never decides *whether* an arm matches, only which member of the set was
# the witness, and so which bindings come out.
struct PatStepGap <: PatStep
    name::Union{Nothing, Symbol}
    lazy::Bool
end

PatStepGap() = PatStepGap(nothing, false)

# `_` — **exactly one step**, of any kind: a field, an index, a position, an extension
# step. It is the counterpart of an ini file's `*` used as a whole path component, and
# unlike a gap it needs no search, since it consumes exactly one thing — so it compiles
# to what every other step compiles to and never reaches the interpreter.
#
# "Any kind" is literal: on a transitional path that still carries an unfolded
# `TypeReferenceStep`, `_` consumes that step like any other. A gap differs here, since
# its length arithmetic is shared with the stripped shape walk `^(p)` uses and so counts
# navigation steps only. Neither is observable on a canonical path, where type
# checkpoints are folded into the nodes and there are no checkpoint steps to count.
struct PatStepAny <: PatStep end

# `any(P, Q, …)` in **path** position — any one of the alternative subpaths, tried in
# order. Where the value-position `any` chooses between values, this chooses between
# runs of steps, and a bare symbol inside it reads as a field name because each
# alternative is parsed as a path. `any(queue, buffer)` is the spelling an ini file's
# `{queue,buffer}` would want, and the one a reader expects.
#
# Its match branches, so it is interpreted rather than compiled.
struct PatStepAlt <: PatStep
    alternatives::Vector{Vector{PatStep}}
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

# The last component of a macro name, so `glob"…"` is recognized however it is
# qualified at the call site.
_macro_basename(x) =
    x isa Symbol ? x :
    x isa GlobalRef ? x.name :
    x isa Expr && x.head === :. && x.args[2] isa QuoteNode ? x.args[2].value : nothing

# Every alternative of an alternation must bind the same names. Otherwise which names
# exist depends on which branch won, and an answer reading one of them fails only for
# the inputs that took the other branch — a defect that shows up late and rarely. It is
# decidable from the pattern, so it is refused where it is written.
function _check_alternatives_agree(names_per_branch, what::AbstractString)
    length(names_per_branch) <= 1 && return nothing
    first_names = Set(names_per_branch[1])
    for names in names_per_branch[2:end]
        Set(names) == first_names ||
            error("every alternative of $what must bind the same names, got " *
                  "$(sort(collect(first_names))) and $(sort(collect(Set(names))))")
    end
    nothing
end

function _parse_value(ex)
    if ex === :_
        return PatValueWildcard()
    elseif ex isa Symbol
        return PatValueBind(ex)
    elseif ex isa Expr && ex.head == :call && ex.args[1] == :(^)
        return PatValueInterp(ex.args[2])
    elseif ex isa Expr && ex.head === :macrocall &&
           _macro_basename(ex.args[1]) === Symbol("@glob_str")
        return PatValueGlob(String(ex.args[end]))
    elseif ex isa Expr && ex.head == :call && ex.args[1] == :(..) && length(ex.args) == 3
        return PatValueRange(ex.args[2], ex.args[3])
    elseif ex isa Expr && ex.head == :call && ex.args[1] === :any
        length(ex.args) > 1 || error("any(value, …) expects at least one alternative")
        alts = PatValue[_parse_value(a) for a in ex.args[2:end]]
        _check_alternatives_agree([_value_binder_names!(Symbol[], a) for a in alts],
                                  "any(value, …)")
        return PatValueAny(alts)
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
# `ReferenceSyntaxStep` AST. This is where the *matching* reading of that AST is applied — the
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

# `_` and `__` reach the shared grammar as ordinary field names — the parser names no
# pattern concept, and needs to name none for either. The *matching* reading of those
# names is a step wildcard and a gap, which is why the surface syntax needed nothing
# added to it. They mirror an ini file's `*` and `**`, and unlike those they are legal
# Julia identifiers in path position.
# The migration guard's message, shared so the two DSLs cannot word it differently.
const REFERENCE_RETIRED_CATCH_ALL =
    "`_` is no longer the catch-all arm — write `__` for \"any path\". `_` now matches " *
    "exactly one step, so `a._.b` is a path of three; write `at(_)` for a one-step arm."

const REFERENCE_STEP_NAME = "_"
const REFERENCE_GAP_NAME = "__"

# `__ʔ` (`\glst`+Tab) — the same run, taken shortest-first. `ʔ` is a *letter*, so the
# parser reads `__ʔ` as one identifier; a literal `?` is the ternary operator and never
# reaches us. It renders as a dotless question mark, which is what a lazy quantifier is
# spelled with everywhere else.
const REFERENCE_LAZY_GAP_NAME = "__ʔ"

_to_pat(s::ReferenceSyntaxField)     = s.name == REFERENCE_GAP_NAME ? PatStepGap() :
                           s.name == REFERENCE_LAZY_GAP_NAME ? PatStepGap(nothing, true) :
                           s.name == REFERENCE_STEP_NAME ? PatStepAny() :
                           PatStepField(PatValueLiteral(s.name))
_to_pat(s::ReferenceSyntaxFieldExpression) = PatStepField(_parse_value(s.expr))
_to_pat(s::ReferenceSyntaxIndex)     = PatStepIndex(_parse_value(s.expr))
_to_pat(s::ReferenceSyntaxPosition)  = PatStepPosition(_parse_value(s.expr))
_to_pat(s::ReferenceSyntaxRange)     = PatStepRange(_parse_value(s.startexpr), _parse_value(s.stopexpr),
                                         s.numbering)
_to_pat(s::ReferenceSyntaxType)      = _pat_type_step(s.expr)
_to_pat(s::ReferenceSyntaxSplice)    = PatStepPathInterp(s.expr)
_to_pat(s::ReferenceSyntaxTailBind)  = PatStepWholePathBind(s.name)
# `__(owner)` and `__ʔ(owner)` name the run a gap takes. They reach the shared grammar
# as extension steps — the parser has no gap concept and needs none — so the *matching*
# reading of those two names is where the binder is read off.
function _to_pat(s::ReferenceSyntaxExtension)
    if s.name === :any
        isempty(s.args) && error("any(path, …) expects at least one alternative")
        alts = Vector{PatStep}[_to_pat_steps(parse_reference_path(a.expr)) for a in s.args]
        _check_alternatives_agree(map(_pattern_binder_names, alts), "any(path, …)")
        return PatStepAlt(alts)
    end
    if String(s.name) in (REFERENCE_GAP_NAME, REFERENCE_LAZY_GAP_NAME)
        length(s.args) == 1 && s.args[1] isa ReferenceSyntaxArgumentValue && s.args[1].expr isa Symbol ||
            error("$(s.name)(name) binds the run a gap takes and expects one bare name")
        return PatStepGap(s.args[1].expr, String(s.name) == REFERENCE_LAZY_GAP_NAME)
    end
    PatStepExtension(s.name, Any[_to_pat_arg(a) for a in s.args])
end

_to_pat_arg(a::ReferenceSyntaxArgumentValue)   = _parse_value(a.expr)
_to_pat_arg(a::ReferenceSyntaxArgumentSubPath) = _case_subpath(a.expr)

_to_pat_steps(steps::Vector{ReferenceSyntaxStep}) = PatStep[_to_pat(s) for s in steps]

# Parse a path pattern: the shared grammar, then the matching reading of it.
_parse_path(ex) = _to_pat_steps(parse_reference_path(ex))

# ------------------------------------------------------------
# Reading a pattern as data
#
# Both readings of the AST need to know two things about a pattern without generating
# any code for it: which names it binds, and whether it can be compiled at all. Both are
# pure functions of the `PatStep` vector, so they serve the compiled and interpreted
# sides alike — and the first of them is what lets a rule that falls back to the
# interpreter hand its bindings to an answer that is ordinary escaped code.
# ------------------------------------------------------------

# A binder named `_` is written to be unreadable, so it is not a name anything can want.
_add_binder!(names::Vector{Symbol}, name::Symbol) =
    (name === :_ || name in names || push!(names, name); names)

_value_binder_names!(names::Vector{Symbol}, ::PatValue) = names
_value_binder_names!(names::Vector{Symbol}, p::PatValueBind) = _add_binder!(names, p.name)
_value_binder_names!(names::Vector{Symbol}, p::PatValueTypedBind) = _add_binder!(names, p.name)

function _value_binder_names!(names::Vector{Symbol}, p::PatValueAny)
    for alt in p.alternatives
        _value_binder_names!(names, alt)
    end
    names
end

_step_binder_names!(names::Vector{Symbol}, ::PatStep) = names
_step_binder_names!(names::Vector{Symbol}, s::PatStepField) = _value_binder_names!(names, s.namepat)
_step_binder_names!(names::Vector{Symbol}, s::PatStepIndex) = _value_binder_names!(names, s.idxpat)
_step_binder_names!(names::Vector{Symbol}, s::PatStepPosition) = _value_binder_names!(names, s.idxpat)
_step_binder_names!(names::Vector{Symbol}, s::PatStepRange) =
    _value_binder_names!(_value_binder_names!(names, s.startpat), s.stoppat)
_step_binder_names!(names::Vector{Symbol}, s::PatStepWholePathBind) = _add_binder!(names, s.name)
_step_binder_names!(names::Vector{Symbol}, s::PatStepTypeBind) = _add_binder!(names, s.name)
function _step_binder_names!(names::Vector{Symbol}, s::PatStepAlt)
    # Every branch binds the same names (checked where the alternation is written), so
    # the first one answers for all of them.
    isempty(s.alternatives) || _pattern_binder_names!(names, s.alternatives[1])
    names
end

_step_binder_names!(names::Vector{Symbol}, s::PatStepGap) =
    s.name === nothing ? names : _add_binder!(names, s.name)

function _step_binder_names!(names::Vector{Symbol}, s::PatStepExtension)
    for arg in s.argpats
        arg isa PatValue ? _value_binder_names!(names, arg) : _pattern_binder_names!(names, arg)
    end
    names
end

function _pattern_binder_names!(names::Vector{Symbol}, steps::Vector{PatStep})
    for step in steps
        _step_binder_names!(names, step)
    end
    names
end

"""
    _pattern_binder_names(steps) -> Vector{Symbol}

Every name `steps` binds, in the order it is written. A pure function of the pattern —
which is what makes it usable where no code is being generated.
"""
_pattern_binder_names(steps::Vector{PatStep}) = _pattern_binder_names!(Symbol[], steps)

# A gap is the one step whose match is a *search*: every other step either matches what
# is in front of it or fails. The generators below are straight-line by construction, so
# a pattern holding a gap is handed to the interpreter instead (see `_gen_rule`) — the
# search is implemented once, where a rule set built at run time already needs it.
_step_has_gap(::PatStep) = false
_step_has_gap(::PatStepGap) = true
_step_has_gap(s::PatStepExtension) =
    any(arg -> arg isa PatValue ? false : _pattern_has_gap(arg), s.argpats)

_pattern_has_gap(steps::Vector{PatStep}) = any(_step_has_gap, steps)

# The full question `_gen_rule` asks: is there anything here the straight-line generators
# cannot emit? A gap searches; an alternation branches in a way a single `bound` set
# cannot follow. Everything else compiles.
_value_needs_interpreter(::PatValue) = false
_value_needs_interpreter(::PatValueAny) = true

_step_needs_interpreter(s::PatStep) = _step_has_gap(s)
_step_needs_interpreter(::PatStepAlt) = true
_step_needs_interpreter(s::PatStepField) = _value_needs_interpreter(s.namepat)
_step_needs_interpreter(s::PatStepIndex) = _value_needs_interpreter(s.idxpat)
_step_needs_interpreter(s::PatStepPosition) = _value_needs_interpreter(s.idxpat)
_step_needs_interpreter(s::PatStepRange) =
    _value_needs_interpreter(s.startpat) || _value_needs_interpreter(s.stoppat)
_step_needs_interpreter(s::PatStepExtension) =
    any(arg -> arg isa PatValue ? _value_needs_interpreter(arg) : _pattern_needs_interpreter(arg),
        s.argpats)

_pattern_needs_interpreter(steps::Vector{PatStep}) = any(_step_needs_interpreter, steps)

# The same question with gaps set aside, since a gap may still be compilable — see
# `_computed_gap_split`. An alternation never is.
_value_or_alt_needs_interpreter(::PatStep) = false
_value_or_alt_needs_interpreter(::PatStepAlt) = true
_value_or_alt_needs_interpreter(s::PatStepField) = _value_needs_interpreter(s.namepat)
_value_or_alt_needs_interpreter(s::PatStepIndex) = _value_needs_interpreter(s.idxpat)
_value_or_alt_needs_interpreter(s::PatStepPosition) = _value_needs_interpreter(s.idxpat)
_value_or_alt_needs_interpreter(s::PatStepRange) =
    _value_needs_interpreter(s.startpat) || _value_needs_interpreter(s.stoppat)
_value_or_alt_needs_interpreter(s::PatStepExtension) =
    any(arg -> arg isa PatValue ? _value_needs_interpreter(arg) :
               any(_value_or_alt_needs_interpreter, arg), s.argpats)

# ------------------------------------------------------------
# The computed gap
#
# A gap searches in general. It does not have to when the pattern is anchored at the
# tail and everything after the gap consumes exactly one step: then the run's length is
# `however many steps are left` minus `however many the rest needs`, which is arithmetic,
# not a search. `__.queue.capacity` against a five-step path fixes the gap at three and
# makes one attempt.
#
# That is the shape of nearly every configuration key, so it is worth compiling rather
# than handing to the interpreter. Greediness cannot be observed here — with only one
# candidate split there is nothing to prefer — which is why a lazy gap qualifies too.
#
# The conformance corpus is what keeps this honest: a gap pattern is compiled on the
# `@reference_case` side and interpreted on the rules side, so every corpus entry
# holding a gap now compares the two implementations against each other directly.
# ------------------------------------------------------------

# A step that consumes exactly one navigation step, whatever it is. `::T` and `::t` do
# not (they are non-navigating, and `::T` steps over an unfolded checkpoint), nor does
# anything of variable length.
_step_consumes_one(::PatStep) = false
_step_consumes_one(::PatStepField) = true
_step_consumes_one(::PatStepIndex) = true
_step_consumes_one(::PatStepPosition) = true
_step_consumes_one(::PatStepRange) = true
_step_consumes_one(::PatStepAny) = true
_step_consumes_one(s::PatStepExtension) = !_step_has_gap(s)

"""
    _computed_gap_split(pattern, mode) -> (prefix, gap, suffix) | nothing

The split that lets a gap's length be computed instead of searched, or `nothing` when
this pattern is not of that shape. The conditions are exactly what `_gen_path_match`'s
gap branch relies on, and are kept here so the two cannot answer differently.
"""
function _computed_gap_split(pattern::Vector{PatStep}, mode::Symbol)
    # Only an `at` arm is anchored at the tail. `below` and `within` leave the leftover
    # free, so the run's length is not implied and the gap searches again.
    mode === :at || return nothing

    gaps = findall(s -> s isa PatStepGap, pattern)
    length(gaps) == 1 || return nothing
    at = gaps[1]

    prefix = pattern[1:at - 1]
    suffix = pattern[at + 1:end]

    # The prefix is walked by the ordinary generator, so it may hold anything that
    # generator emits — but not a step that only has a reading as the sole one.
    all(s -> !(s isa PatStepWholePathBind || s isa PatStepPathInterp), prefix) || return nothing
    _pattern_has_gap(prefix) && return nothing

    all(_step_consumes_one, suffix) || return nothing

    (prefix, pattern[at], suffix)
end


# ------------------------------------------------------------
# Rule parsing
# ------------------------------------------------------------

# The pattern side of one arm, minus any `when(…)`: answers `(mode, patsteps)`.
# A bare pattern is `at(…)`; the five arm words say where the input sits relative
# to it.
# Arm words that were renamed, and what they are now. They raise where they are written
# rather than being quietly accepted, so a block written against the old vocabulary is a
# message and not a mystery. `prefix` is here too: it named `above` while reading as
# though it meant `within`, which is why it went.
const REFERENCE_RETIRED_ARMS = Dict(
    :at_or_below => "within",
    :at_or_above => "toward")

_retired_arm_message(name::Symbol) =
    "`$(name)(path)` is no longer an arm word — write `$(REFERENCE_RETIRED_ARMS[name])(path)`; " *
    "an arm word spells one relation, not a disjunction of two"

function _parse_arm_pattern(lhs)
    if lhs isa Expr && lhs.head == :call && lhs.args[1] === :prefix
        # `prefix(P)` named `above(P)` while reading as though it meant
        # `within(P)`; the word is gone rather than left to mislead.
        error("`prefix(path)` is no longer an @reference_case arm — write `above(path)` " *
              "for \"the input runs out inside path\", or `within(path)` for " *
              "\"the input is path or deeper\"")
    elseif lhs isa Expr && lhs.head == :call && haskey(REFERENCE_RETIRED_ARMS, lhs.args[1])
        error(_retired_arm_message(lhs.args[1]))
    elseif lhs isa Expr && lhs.head == :call && lhs.args[1] in REFERENCE_RULE_MODES
        mode = lhs.args[1]
        length(lhs.args) == 2 || error("$mode(path) expects exactly one argument")
        return (mode, _parse_path(lhs.args[2]))
    elseif lhs isa Expr && lhs.head === :macrocall &&
           _macro_basename(lhs.args[1]) === Symbol("@ref_str")
        # The string spelling of a pattern, as an arm. It parses to the same data, so it
        # is read here rather than expanded and then re-read.
        return (:at, parse_reference_pattern(lhs.args[end]))
    elseif lhs === :_
        # `_` used to be the catch-all and now matches exactly one step, so a bare `_`
        # arm would quietly change from "anything" to "any one-step path". It is an
        # error rather than a silent reinterpretation. Only the un-worded arm is
        # guarded: `at(_)` is caught by the arm-word branch above and says one step
        # deliberately, which is how the new meaning is written meanwhile.
        error(REFERENCE_RETIRED_CATCH_ALL)
    elseif lhs === :∅
        # Empty-path pattern: matches a reference that terminates *at* the
        # element itself — a whole-element ("tree") selection. Compiles to a
        # zero-step `at` match (`_ref_input isa EmptyReference`). This only
        # adds a writable pattern; the no-match fallthrough is still `nothing`.
        return (:at, PatStep[])
    elseif lhs isa Expr && lhs.head == :(::) && length(lhs.args) == 2 && lhs.args[1] === :∅
        # `∅::t` / `∅::T` — a whole-element selection whose terminal type is
        # bound (`::t`) or narrowed (`::T`). Matches an `EmptyReference`
        # and reads its `type` field. The empty-path match falls out of the
        # single type step operating on an EmptyReference.
        return (:at, PatStep[_pat_type_step(lhs.args[2])])
    else
        return (:at, _parse_path(lhs))
    end
end

function _parse_rule(ex)
    ex isa Expr && ex.head == :call && ex.args[1] == :(=>) ||
        error("expected `pattern => result`, got: $ex")

    lhs, rhs = ex.args[2], ex.args[3]

    if lhs isa Expr && lhs.head == :call && lhs.args[1] == :when
        length(lhs.args) == 3 || error("when(pattern, cond) expects exactly two arguments")
        mode, pat = _parse_arm_pattern(lhs.args[2])
        return (mode, pat, lhs.args[3], rhs)
    else
        mode, pat = _parse_arm_pattern(lhs)
        return (mode, pat, nothing, rhs)
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

function _gen_value_match(valex, pat::PatValueGlob, success, bound::Set{Symbol})
    return :(($valex isa AbstractString &&
              ReferenceModule.glob_matches($(pat.pattern), $valex)) ?
             $success : _nomatch), bound
end

function _gen_value_match(valex, pat::PatValueRange, success, bound::Set{Symbol})
    lo, hi = esc(pat.lo), esc(pat.hi)
    return :(($valex isa Number && $lo <= $valex <= $hi) ? $success : _nomatch), bound
end

# An alternation never reaches codegen: `_gen_rule` routes a pattern holding one to the
# interpreter, because its branches may bind different names and threading a `bound` set
# through them has no straight-line shape.
_gen_value_match(valex, pat::PatValueAny, success, bound::Set{Symbol}) =
    error("`any(…)` is matched by the interpreter, not compiled — `_gen_rule` should " *
          "have routed this pattern to `_gen_interpreted_rule`")

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
# `_gen_path_match` / `_gen_above_match` (which apply the narrowing type
# assertion) before per-step dispatch is ever reached, so a step method would be
# dead code. Every step reaches position 1 in the recursion, so this holds for
# `PatStepType` anywhere in a pattern.

# The narrowing rule a `::T` pattern step applies. It lives here, beside the
# `PatStepType` it interprets, and is the single answer all four readings of that
# step call — this fragment's compiled `_gen_path_match` / `_gen_above_match` and
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
    startexpr = step.numbering === :element ? :($hex.start + 1) : :($hex.start)
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
# *sole* step of a pattern — `_gen_path_match` / `_gen_above_match` intercept it there.
# Reaching per-step dispatch means it was written mid-chain (`a.^(p).b`, `a.b.^(p)`), which
# has no matching reading. Say so, rather than failing with a `MethodError` on this method
# not existing.
_gen_step_match(hex, tex, step::PatStepPathInterp, rest_success, bound::Set{Symbol}) =
    error("^(expr) path interpolation is only valid as the sole step of an @reference_case pattern: ^($(step.expr))")

# `_` matches whatever step it is handed: reaching per-step dispatch already means the
# path had one. It binds nothing and tests nothing, so the rest of the pattern is the
# whole of its code.
_gen_step_match(hex, tex, step::PatStepAny, rest_success, bound::Set{Symbol}) =
    (rest_success, bound)

# A gap never reaches codegen: `_gen_rule` routes a pattern holding one to the
# interpreter before either generator is entered. This says so out loud, so that a
# future generator gains its gap case deliberately rather than by `MethodError`.
_gen_step_match(hex, tex, step::PatStepAlt, rest_success, bound::Set{Symbol}) =
    error("`any(path, …)` is matched by the interpreter, not compiled — `_gen_rule` " *
          "should have routed this pattern to `_gen_interpreted_rule`")

_gen_step_match(hex, tex, step::PatStepGap, rest_success, bound::Set{Symbol}) =
    error("a `__` gap is matched by the interpreter, not compiled — `_gen_rule` should " *
          "have routed this pattern to `_gen_interpreted_rule`")

# The `at` / `below` / `within` family: consume the pattern from the front of
# the path, then judge what is left over. `terminal` is which of the three is being
# asked, and it is only ever read when the pattern runs out — the walk itself is one
# walk. The extension-step seam calls this with four arguments, which is `:at`: a
# subpath argument must match its subpath exactly.
function _gen_path_match(path_ex, steps::Vector{PatStep}, success, bound::Set{Symbol}=Set{Symbol}(),
                         terminal::Symbol=:at)
    # Folded references expose a navigation step directly as `head` (the type is a
    # node field), so patterns written against the navigation skeleton match the
    # path as-is — there are no interleaved checkpoint steps to skip.
    if isempty(steps)
        # The pattern is spent; the leftover decides.
        terminal === :within && return success, bound
        test = terminal === :below ?
               :($path_ex isa ReferenceModule.ConcreteReference) :
               :($path_ex isa ReferenceModule.EmptyReference)
        return :($test ? $success : _nomatch), bound
    end

    # A gap whose length is arithmetic rather than a search — see `_computed_gap_split`,
    # which decides whether this branch is reachable at all.
    if steps[1] isa PatStepGap
        gap = steps[1]
        suffix = steps[2:end]
        p = gensym(:p)
        taken = gensym(:taken)
        skipped = gensym(:skipped)

        inner_bound = gap.name === nothing ? bound : union(bound, Set([gap.name]))
        rest, bound1 = _gen_path_match(skipped, suffix, success, inner_bound, terminal)
        # A named gap is handed the run it took, which is the front of the path.
        gap.name === nothing ||
            (rest = :(let $(esc(gap.name)) = ReferenceModule._take_leading_steps($p, $taken)
                          $rest
                      end))

        ex = quote
            let $p = $path_ex
                let $taken = ReferenceModule._navigation_length($p) - $(length(suffix))
                    if $taken < 0
                        _nomatch
                    else
                        let $skipped = ReferenceModule._drop_navigation_steps($p, $taken)
                            $skipped === nothing ? _nomatch : $rest
                        end
                    end
                end
            end
        end
        return ex, bound1
    end

    if length(steps) == 1 && steps[1] isa PatStepWholePathBind
        # A tail bind swallows whatever remains, so the leftover is empty by
        # construction — which `below` can never satisfy.
        name = steps[1].name
        terminal === :below && return :(_nomatch), union(bound, Set([name]))
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
        rest_on_tail, b1 = _gen_path_match(:(ReferenceModule.tail($sp)), steps[2:end], success, bound, terminal)
        rest_on_same, b2 = _gen_path_match(sp, steps[2:end], success, bound, terminal)
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
        rest, b = _gen_path_match(sp, steps[2:end], success, union(bound, Set([name])), terminal)
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
        # canonical path matches a plain interpolated skeleton. The interpolated
        # path is the whole pattern, so the leftover test is the prefix relation.
        a = :(ReferenceModule.strip_reference_types($path_ex))
        b = :(ReferenceModule.strip_reference_types($expr))
        test = terminal === :at ? :($a == $b) :
               terminal === :below ? :(ReferenceModule.is_reference_prefix($b, $a)) :
               :($a == $b || ReferenceModule.is_reference_prefix($b, $a))
        return :($test ? $success : _nomatch), bound
    end

    p = gensym(:p)
    h = gensym(:h)
    t = gensym(:t)

    rest_success, bound1 = _gen_path_match(t, steps[2:end], success, bound, terminal)
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

# The `above` / `toward` family: the input runs out *inside* the pattern. The
# two differ only in what happens when both run out together — `above` wants the
# input strictly shallower, `toward` also accepts equal — so one walk with a
# flag covers them, and `toward` is exactly `above ∪ at`.
function _gen_above_match(path_ex, steps::Vector{PatStep}, success, bound::Set{Symbol}=Set{Symbol}(),
                          include_at::Bool=false)
    if isempty(steps)
        # The pattern is spent, so the input was not strictly shallower. It is `at`
        # if the input is spent too, which only `toward` accepts.
        include_at || return :(_nomatch), bound
        return :(($path_ex isa ReferenceModule.EmptyReference) ? $success : _nomatch), bound
    end

    if length(steps) == 1 && steps[1] isa PatStepPathInterp
        expr = esc(steps[1].expr)
        # Shape-only prefix check: both sides stripped first.
        a = :(ReferenceModule.strip_reference_types($path_ex))
        b = :(ReferenceModule.strip_reference_types($expr))
        test = include_at ?
               :(ReferenceModule.is_reference_prefix($a, $b) || $a == $b) :
               :(ReferenceModule.is_reference_prefix($a, $b))
        return :($test ? $success : _nomatch), bound
    end

    # A leading `::T` is a non-navigating **narrowing** type assertion (the same
    # `_type_step_matches` rule as in `_gen_path_match`, so the two cannot drift):
    # a recorded node type must be `<: T`, an absent one says nothing. It advances
    # past an unfolded `TypeReferenceStep` *step* if present, else matches on the
    # same path.
    if steps[1] isa PatStepType
        ty = esc(steps[1].typeexpr)
        sp = gensym(:sp)
        rest_on_tail, b1 = _gen_above_match(:(ReferenceModule.tail($sp)), steps[2:end], success, bound, include_at)
        rest_on_same, b2 = _gen_above_match(sp, steps[2:end], success, bound, include_at)
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

    # `::t` binds the matched node's type, then continues the above-match on the
    # same path (mirrors the `_gen_path_match` binder).
    if steps[1] isa PatStepTypeBind
        name = steps[1].name
        sp = gensym(:sp)
        rest, b = _gen_above_match(sp, steps[2:end], success, union(bound, Set([name])), include_at)
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

    rest_match, bound1 = _gen_above_match(t, steps[2:end], success, bound, include_at)
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

    # A lone anonymous gap is the catch-all arm — by far the commonest arm there is, and
    # on the hot path of every mapper and reader. It holds a gap but needs no search: a
    # run that may be any length, with nothing before or after it to line up against,
    # answers the same for every input. Compiling it keeps that arm free, where handing
    # it to the interpreter would cost a materialized pattern and a bindings dict on
    # every evaluation.
    if length(pat) == 1 && pat[1] isa PatStepGap && pat[1].name === nothing
        # `below` is the one form that looks at the input at all: the gap may decline to
        # take anything, leaving the whole input over, so "strictly deeper" reduces to
        # "the input is not empty".
        mode === :below || return body
        return :(_ref_input isa ReferenceModule.ConcreteReference ? $body : _nomatch)
    end

    # A gap whose length is arithmetic compiles like everything else.
    if !any(_value_or_alt_needs_interpreter, pat) && _computed_gap_split(pat, mode) !== nothing
        ex, _ = _gen_path_match(:_ref_input, pat, body, Set{Symbol}(), mode)
        return ex
    end

    # Any other pattern whose match is a search is handed to the interpreter rather than
    # compiled, so the search exists once in the codebase (see `_gen_interpreted_rule`).
    _pattern_needs_interpreter(pat) && return _gen_interpreted_rule(mode, pat, body)

    # Two generators cover the five arm words: the above-family walks until the
    # input runs out inside the pattern, the rest consume the pattern and judge the
    # leftover.
    ex, _ = mode === :above || mode === :toward ?
            _gen_above_match(:_ref_input, pat, body, Set{Symbol}(), mode === :toward) :
            _gen_path_match(:_ref_input, pat, body, Set{Symbol}(), mode)
    return ex
end

# ------------------------------------------------------------
# The interpreted rule
#
# The seam that makes one matcher serve both DSLs. `match_reference_pattern`
# (`ReferenceRules.jl`) answers the bindings a match produced; this reopens them as
# ordinary local variables so the arm's guard and result stay what they have always
# been — **escaped user code that closes over the call site**, with its locals, its
# `return`, its everything.
#
# That is why the fallback calls the matcher and not `apply_reference_rules`: a rules
# answer is deliberately closed and compiled in this module, and a `@reference_case`
# answer is deliberately open. The two DSLs share matching; neither shares answer
# evaluation.
#
# The binder names come from the pattern (`_pattern_binder_names`), so they are known
# here even though the values are not. A name the match never reached raises on read,
# as it does in compiled code — a pattern whose guard reads a binding its input never
# arrived at is a defect either way.
# ------------------------------------------------------------

function _gen_interpreted_rule(mode, pat::Vector{PatStep}, body)
    bindings = gensym(:bindings)
    lets = [:($(esc(name)) = $bindings[$(QuoteNode(name))])
            for name in _pattern_binder_names(pat)]
    quote
        let $bindings = ReferenceModule.match_reference_pattern($(QuoteNode(mode)),
                                                                $(_quote_pattern(pat)),
                                                                _ref_input)
            if $bindings === nothing
                _nomatch
            else
                let $(lets...)
                    $body
                end
            end
        end
    end
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
  read the pattern's bindings); `name...` binds the entire remaining tail; `∅`
  matches the empty (whole-element) path.

Each arm says where the **input** sits relative to its pattern `P` — the same five
words `@reference_rules` uses:

| arm | holds when |
| --- | --- |
| `P` / `at(P)` | the input **is** `P` |
| `below(P)` | the input is strictly deeper |
| `within(P)` | `P` or deeper |
| `above(P)` | the input is strictly shallower — it runs out *inside* `P` |
| `toward(P)` | `P` or shallower |

There is no `prefix(…)`: it named `above(…)` while reading as though it meant
`within(…)`, so writing it is an error that says which one to pick.

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