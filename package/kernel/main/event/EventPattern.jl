"""
    EventPatternModule

The **event pattern language**: one surface syntax for saying "this kind of event,
with these field values and these modifiers held", and two ways to use it.

- Reified — an [`EventPattern`](@ref) is *data* that answers two questions about an
  event: [`matches`](@ref)`(pattern, event)` (would this event fire it?) and
  [`describe`](@ref)`(pattern)` (how is it written for a human, e.g. `"Ctrl+."`).
  A pattern that can be shown is a pattern that can be listed, so whatever is
  matched can also be documented.
- Compiled — [`@event_case`](@ref) compiles a table of `pattern => result` rules to
  plain `isa`/field tests, first match wins, falling through to `nothing`.

Both ride on one parser, exported here as a macro-authoring API
([`parse_event_rule`](@ref), [`event_pattern_expr`](@ref),
[`event_field_bindings`](@ref)) so that any DSL binding events to something can
reuse the surface syntax rather than re-implement it.

Every event type is matchable, and the field table is *derived* from the event
structs themselves — a new event needs no entry here, and no pattern can go stale
against the struct it matches.

# Pattern syntax

Patterns mirror the event constructors:

- The constructor name selects the event type: any concrete `Event` — `KeyDown`,
  `KeyPress`, `MousePress`, `MouseScroll`, `WindowClose`, … A bare type name
  (`MouseScroll`) is a type-only match.
- Positional args match or bind the struct's **non-modifier** fields, in declared
  order: a literal (`:period`, `'a'`, `42`) is an equality test, a bare identifier
  (`k`, `x`) binds that field, `_` ignores it, and `^(expr)` (or any other
  expression) is compared `==` to the runtime value.
- Modifier flags after `;` (`ctrl`, `shift`, `alt`, `meta`) are matched **exactly**:
  every listed flag must be held and every unlisted flag must be absent. Omitting
  the `;` block leaves modifiers unconstrained, so `KeyPress(c)` still matches a
  shifted capital letter.
- `when(pattern, condition)` adds a boolean guard; bound variables are in scope in
  the condition.
- `_` on its own is the catch-all (`@event_case` only).

Positional slots are the event struct's fields, minus `modifiers` (always given via
`;`, never positionally): `KeyDown(key, repeat)`, `KeyPress(char, text)`,
`MousePress(button, x, y, count)`, `MouseScroll(dx, dy, x, y)`, and so on.
"""
module EventPatternModule

using ..EventModule

export EventPattern,
       KeyPressPattern, KeyDownPattern, KeyUpPattern,
       MouseDownPattern, MouseUpPattern, MousePressPattern,
       MouseMovePattern, MouseEnterPattern, MouseLeavePattern, MouseScrollPattern,
       matches, describe,
       EventRule, parse_event_rule, event_pattern_expr, event_field_bindings,
       var"@event_case"

# ─────────────────────────────────────────────────────────────────────────
# The event table
#
# Derived from `EVENT_TYPES`: every concrete event, mapped to the ordered list of
# fields a positional pattern argument may bind or match. `modifiers` is never
# positional — it is written after the `;` — so it is excluded.
#
# Deriving rather than declaring is what keeps a pattern from going stale against
# the struct it matches: an event type is matchable the moment the event layer
# exports it, with the fields it actually has.
# ─────────────────────────────────────────────────────────────────────────

const _EVENT_TYPES = Dict{Symbol,Tuple{Type,Vector{Symbol}}}(
    nameof(T) => (T, Symbol[f for f in fieldnames(T) if f !== :modifiers])
    for T in EVENT_TYPES)

const _MODIFIER_FLAGS = (:ctrl, :shift, :alt, :meta)

# ─────────────────────────────────────────────────────────────────────────
# The reified pattern
# ─────────────────────────────────────────────────────────────────────────

"""
    EventPattern{E<:Event}(fields, modifiers, guard)

A reified input pattern: an event type `E`, the subset of its fields that are
*constrained* to a value (a `NamedTuple`; an absent field matches anything), the
modifier constraint (`nothing` = unconstrained, or a `Vector{Symbol}` matched
exactly — every listed flag held, every unlisted flag absent), an optional
`guard(event) -> Bool` for a condition the fields cannot express, and an optional
`label` overriding how the pattern is written for a human (a guard has no rendering
of its own: a digits-only `KeyPress` reads better as `"0-9"` than as `"character"`).

It answers [`matches`](@ref) and [`describe`](@ref). One type covers every event:
the per-event constructors below (`KeyDownPattern`, `MousePressPattern`, …) are
conveniences that name the type and its first field.
"""
struct EventPattern{E<:Event}
    fields::NamedTuple
    modifiers::Union{Vector{Symbol},Nothing}
    guard::Union{Function,Nothing}
    label::Union{String,Nothing}
end
EventPattern{E}(fields, modifiers, guard) where {E<:Event} =
    EventPattern{E}(fields, modifiers, guard, nothing)

"""
    matches(pattern::EventPattern, event) -> Bool

Would `event` fire `pattern`? The event must be of the pattern's type, every
constrained field must be equal, the modifiers must match, and the guard (if any)
must hold. An unconstrained field matches any value.
"""
function matches(pattern::EventPattern{E}, event) where {E}
    event isa E || return false
    for (name, value) in pairs(pattern.fields)
        getfield(event, name) == value || return false
    end
    _mods_match(pattern.modifiers, get_modifiers(event)) || return false
    return pattern.guard === nothing || pattern.guard(event)
end

# Exact modifier test. `nothing` = don't care.
function _mods_match(modifiers::Union{Vector{Symbol},Nothing}, held::Modifiers)
    modifiers === nothing && return true
    for flag in _MODIFIER_FLAGS
        (getfield(held, flag) === (flag in modifiers)) || return false
    end
    return true
end

# ── Per-event constructors. Each names the type and its most-constrained field;
#    `nothing` leaves that field (and so the pattern) unconstrained.

_constrained(name::Symbol, value) = value === nothing ? NamedTuple() : NamedTuple{(name,)}((value,))

KeyPressPattern(char, guard = nothing, label = nothing) =
    EventPattern{KeyPress}(_constrained(:char, char), nothing, guard, label)
KeyDownPattern(key, modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{KeyDown}(_constrained(:key, key), modifiers, guard, label)
KeyUpPattern(key, modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{KeyUp}(_constrained(:key, key), modifiers, guard, label)
MouseDownPattern(button, modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{MouseDown}(_constrained(:button, button), modifiers, guard, label)
MouseUpPattern(button, modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{MouseUp}(_constrained(:button, button), modifiers, guard, label)
MousePressPattern(button, modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{MousePress}(_constrained(:button, button), modifiers, guard, label)
MouseMovePattern(modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{MouseMove}(NamedTuple(), modifiers, guard, label)
MouseEnterPattern(modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{MouseEnter}(NamedTuple(), modifiers, guard, label)
MouseLeavePattern(modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{MouseLeave}(NamedTuple(), modifiers, guard, label)
MouseScrollPattern(modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{MouseScroll}(NamedTuple(), modifiers, guard, label)

# ─────────────────────────────────────────────────────────────────────────
# Describing a pattern
# ─────────────────────────────────────────────────────────────────────────

"""
    describe(pattern::EventPattern) -> String

How the pattern's input is written for a human — `"n"`, `"Ctrl+."`, `"Left click"`,
`"scroll"`. The pattern's own `label` wins when it has one; otherwise it is phrased
from the event type and the constrained fields, falling back to the type name for an
event with no phrasing of its own.
"""
describe(pattern::EventPattern{E}) where {E} =
    pattern.label === nothing ? _describe(E, pattern) : pattern.label

# Human prefix for a modifier set ("Ctrl+", "Ctrl+Alt+", "").
function _mod_prefix(modifiers::Union{Vector{Symbol},Nothing})
    (modifiers === nothing || isempty(modifiers)) && return ""
    labels = Dict(:ctrl => "Ctrl", :shift => "Shift", :alt => "Alt", :meta => "Meta")
    join((labels[f] for f in _MODIFIER_FLAGS if f in modifiers), "+") * "+"
end

_key_label(::Nothing) = "key"
function _key_label(key::Symbol)
    special = Dict(:period => ".", :space => "Space", :tab => "Tab", :return => "Return",
                   :home => "Home", :end => "End", :backspace => "Backspace",
                   :delete => "Delete", :escape => "Esc", :up => "↑", :down => "↓",
                   :left => "←", :right => "→", :page_up => "PgUp", :page_down => "PgDn")
    get(special, key, uppercasefirst(string(key)))
end

_button_label(::Nothing) = "click"
_button_label(button::Symbol) = button === :left ? "Left click" :
                                button === :right ? "Right click" :
                                button === :middle ? "Middle click" : "$(button) click"

_field(pattern::EventPattern, name::Symbol) = get(pattern.fields, name, nothing)

_key_phrase(p) = _mod_prefix(p.modifiers) * _key_label(_field(p, :key))
_button_phrase(p) = _mod_prefix(p.modifiers) * _button_label(_field(p, :button))

_describe(::Type{KeyDown}, p) = _key_phrase(p)
_describe(::Type{KeyUp}, p) = "release " * _key_phrase(p)
_describe(::Type{KeyPress}, p) =
    (c = _field(p, :char); c === nothing ? "character" : string(c))
_describe(::Type{KeyChord}, p) = "key chord"
_describe(::Type{MousePress}, p) = _button_phrase(p)
_describe(::Type{MouseDown}, p) = "press " * _button_phrase(p)
_describe(::Type{MouseUp}, p) = "release " * _button_phrase(p)
_describe(::Type{MouseMove}, p) = _mod_prefix(p.modifiers) * "move pointer"
_describe(::Type{MouseEnter}, p) = _mod_prefix(p.modifiers) * "pointer enters"
_describe(::Type{MouseLeave}, p) = _mod_prefix(p.modifiers) * "pointer leaves"
_describe(::Type{MouseScroll}, p) = _mod_prefix(p.modifiers) * "scroll"
# Any event with no phrasing of its own (the window events, and anything added
# later) is described by its type name rather than going unnamed.
_describe(::Type{E}, p) where {E<:Event} = lowercase(string(nameof(E)))

# ─────────────────────────────────────────────────────────────────────────
# The parser — shared by `@event_case` and by any DSL that binds events
# ─────────────────────────────────────────────────────────────────────────

# One positional field of a pattern.
abstract type FieldPattern end
struct WildcardField   <: FieldPattern end
struct BoundField      <: FieldPattern; name::Symbol; end
struct LiteralField    <: FieldPattern; value; end
struct ExpressionField <: FieldPattern; expr; end

"""
    EventRule(type, fields, modifiers, guard, result)

One parsed `pattern => result` rule. `type` is the event's constructor name
(`nothing` for the catch-all `_`), `fields` the positional field patterns in
declared order, `modifiers` the exact modifier set (`nothing` = unconstrained),
`guard` the `when(pattern, condition)` condition expression (or `nothing`), and
`result` the right-hand side, unevaluated.

Produced by [`parse_event_rule`](@ref) and consumed by [`event_pattern_expr`](@ref)
and [`event_field_bindings`](@ref); a macro building on the event pattern syntax
needs no other view of it.
"""
struct EventRule
    type::Union{Symbol,Nothing}
    fields::Vector{FieldPattern}
    modifiers::Union{Vector{Symbol},Nothing}
    guard::Any
    result::Any
end

function _parse_field(ex)
    if ex === :_
        WildcardField()
    elseif ex isa Symbol
        BoundField(ex)
    elseif ex isa QuoteNode
        LiteralField(ex.value)
    elseif ex isa Bool || ex isa Int || ex isa Char || ex isa String
        LiteralField(ex)
    elseif ex isa Expr && ex.head == :call && ex.args[1] == :(^)
        length(ex.args) == 2 || error("event pattern: ^(expr) expects exactly one argument: $ex")
        ExpressionField(ex.args[2])
    else
        ExpressionField(ex)
    end
end

function _parse_modifiers(params::Expr)
    modifiers = Symbol[]
    for p in params.args
        p isa Symbol ||
            error("event pattern: modifier flags must be bare names (e.g. `; ctrl, alt`), got `$p`")
        p in _MODIFIER_FLAGS ||
            error("event pattern: unknown modifier `$p`; expected one of $(_MODIFIER_FLAGS)")
        push!(modifiers, p)
    end
    modifiers
end

# Returns (type, fields, modifiers); `type === nothing` is the catch-all `_`.
function _parse_pattern(ex)
    if ex === :_
        return (nothing, FieldPattern[], nothing)
    elseif ex isa Symbol
        haskey(_EVENT_TYPES, ex) ||
            error("event pattern: unknown event type `$ex` (use `_` for catch-all)")
        return (ex, FieldPattern[], nothing)
    elseif ex isa Expr && ex.head == :call
        name = ex.args[1]
        (name isa Symbol && haskey(_EVENT_TYPES, name)) ||
            error("event pattern: unknown event type in pattern `$ex`")
        rest = ex.args[2:end]
        modifiers = nothing
        if !isempty(rest) && rest[1] isa Expr && rest[1].head == :parameters
            modifiers = _parse_modifiers(rest[1])
            rest = rest[2:end]
        end
        fields = FieldPattern[_parse_field(a) for a in rest]
        declared = _EVENT_TYPES[name][2]
        length(fields) <= length(declared) ||
            error("event pattern: $name takes at most $(length(declared)) positional field(s) " *
                  "$(declared), got $(length(fields))")
        return (name, fields, modifiers)
    else
        error("event pattern: unsupported pattern `$ex`")
    end
end

"""
    parse_event_rule(expr) -> EventRule

Parse one `pattern => result` rule (or `when(pattern, condition) => result`) of the
event pattern syntax. Throws with a message naming the offending expression when the
pattern is not one of the known event types.
"""
function parse_event_rule(ex)
    (ex isa Expr && ex.head == :call && ex.args[1] == :(=>)) ||
        error("event pattern: expected `pattern => result`, got `$ex`")
    lhs, rhs = ex.args[2], ex.args[3]
    if lhs isa Expr && lhs.head == :call && lhs.args[1] == :when
        length(lhs.args) == 3 ||
            error("event pattern: when(pattern, condition) expects exactly two arguments")
        type, fields, modifiers = _parse_pattern(lhs.args[2])
        return EventRule(type, fields, modifiers, lhs.args[3], rhs)
    else
        type, fields, modifiers = _parse_pattern(lhs)
        return EventRule(type, fields, modifiers, nothing, rhs)
    end
end

# A constrained field's required value; a bound or wildcard field constrains nothing.
_is_constrained(p::FieldPattern) = p isa LiteralField || p isa ExpressionField
_constraint_expr(p::LiteralField) = QuoteNode(p.value)
_constraint_expr(p::ExpressionField) = esc(p.expr)

"""
    event_pattern_expr(rule::EventRule, guard_expr) -> Expr

The expression constructing `rule`'s reified [`EventPattern`](@ref), with `guard_expr`
(a `(event) -> Bool` closure expression, or `:nothing`) as its guard. The event type
is spliced in as a value, so the expression resolves in any module.
"""
function event_pattern_expr(rule::EventRule, guard_expr)
    rule.type === nothing && error("event pattern: `_` catch-all has no reified pattern")
    type, declared = _EVENT_TYPES[rule.type]
    names, values = Symbol[], Any[]
    for i in eachindex(rule.fields)
        _is_constrained(rule.fields[i]) || continue
        push!(names, declared[i])
        push!(values, _constraint_expr(rule.fields[i]))
    end
    fields = :($(NamedTuple{Tuple(names)})(($(values...),)))
    modifiers = rule.modifiers === nothing ? :nothing :
                Expr(:vect, QuoteNode.(rule.modifiers)...)
    :($(EventPattern{type})($fields, $modifiers, $guard_expr))
end

"""
    event_field_bindings(rule::EventRule, event_symbol, body) -> Expr

Wrap `body` in the `let` bindings for `rule`'s bound positional fields, read off
`event_symbol` — so a rule's guard and result can name a field (`KeyPress(c)` binds
`c`) without knowing the event's field order.
"""
function event_field_bindings(rule::EventRule, event_symbol, body)
    declared = _EVENT_TYPES[rule.type][2]
    for i in length(rule.fields):-1:1
        p = rule.fields[i]
        if p isa BoundField
            body = :(let $(esc(p.name)) = $event_symbol.$(declared[i]); $body end)
        end
    end
    body
end

# ─────────────────────────────────────────────────────────────────────────
# @event_case — the compiled dispatch table
# ─────────────────────────────────────────────────────────────────────────

# Each generated rule evaluates to the (escaped) result on a full match, or to the
# `_nomatch` sentinel otherwise.

_gen_field_match(accessor, ::WildcardField, success) = success
_gen_field_match(accessor, p::BoundField, success) =
    :(let $(esc(p.name)) = $accessor; $success end)
_gen_field_match(accessor, p::LiteralField, success) =
    :($accessor == $(QuoteNode(p.value)) ? $success : _nomatch)
_gen_field_match(accessor, p::ExpressionField, success) =
    :($accessor == $(esc(p.expr)) ? $success : _nomatch)

# Exact modifier test: each of the four flags must equal its membership in
# `modifiers` (listed => must be held, unlisted => must be absent).
function _gen_mod_test(event, modifiers::Vector{Symbol})
    tests = Any[:($event.modifiers.$flag === $(flag in modifiers)) for flag in _MODIFIER_FLAGS]
    foldr((a, b) -> :($a && $b), tests)
end

function _gen_rule(event, rule::EventRule)
    success = rule.guard === nothing ? esc(rule.result) :
              :($(esc(rule.guard)) ? $(esc(rule.result)) : _nomatch)

    # Catch-all `_` matches any event.
    rule.type === nothing && return success

    type, declared = _EVENT_TYPES[rule.type]

    # Wrap field matches from last to first so all binds are in scope for the
    # result and the guard.
    body = success
    for i in length(rule.fields):-1:1
        body = _gen_field_match(:($event.$(declared[i])), rule.fields[i], body)
    end

    if rule.modifiers !== nothing
        body = :($(_gen_mod_test(event, rule.modifiers)) ? $body : _nomatch)
    end

    return quote
        if $event isa $type
            $body
        else
            _nomatch
        end
    end
end

"""
    @event_case event begin
        KeyDown(:period; ctrl)                                 => ToggleCollapseOperation()
        when(KeyDown(k; alt), k in (:up, :down))               => TreeNavigateOperation(k)
        KeyPress(c)                                            => insert_char(c)
        MousePress(:left, x, y)                                => select_at(x, y)
        _                                                      => nothing
    end

A first-match-wins dispatch table over the input events, compiled to plain
`isa`/field tests. Rules are tried top to bottom; when none matches, the expression
evaluates to `nothing`, so a reader body can simply
`return @event_case event begin … end`. The pattern surface is documented on
[`EventPatternModule`](@ref).
"""
macro event_case(scrutinee, block)
    entries = block isa Expr && block.head == :block ? block.args : [block]
    rules = [parse_event_rule(e) for e in entries if !(e isa LineNumberNode)]

    event = gensym(:event)

    chain = :nothing
    for rule in reverse(rules)
        rule_expr = _gen_rule(event, rule)
        chain = quote
            let _m = $rule_expr
                _m === _nomatch ? $chain : _m
            end
        end
    end

    return quote
        let $event = $(esc(scrutinee)), _nomatch = Base.RefValue{Any}()
            $chain
        end
    end
end

end # module
