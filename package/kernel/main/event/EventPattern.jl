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

# Pattern syntax

Patterns mirror the event constructors:

- The constructor name selects the event type: `KeyDown`, `KeyUp`, `KeyPress`,
  `MouseDown`, `MouseUp`, `MousePress`, `MouseMove`, `MouseEnter`, `MouseLeave`,
  `MouseScroll`. A bare type name (`MouseScroll`) is a type-only match.
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

Per-event positional field order (modifiers always via `;`, never positional):

| Pattern                           | Positional slots    |
| --------------------------------- | ------------------- |
| `KeyDown(key, repeat)`            | key, repeat         |
| `KeyUp(key)`                      | key                 |
| `KeyPress(char, text)`            | char, text          |
| `MouseDown/Up(button, x, y)`      | button, x, y        |
| `MousePress(button, x, y, count)` | button, x, y, count |
| `MouseMove/Enter/Leave(x, y, buttons)` | x, y, buttons  |
| `MouseScroll(dx, dy, x, y)`       | dx, dy, x, y        |
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
# Maps the constructor name used in a pattern to its type expression and the
# ordered list of *non-modifier* fields that positional pattern arguments bind or
# match. Type expressions are emitted unescaped, so they resolve in this module's
# scope and a caller of `@event_case` needs no imports of its own.
# ─────────────────────────────────────────────────────────────────────────

const _EVENT_TYPES = Dict{Symbol,Tuple{Any,Vector{Symbol}}}(
    :KeyDown     => (:(EventModule.KeyDown),     [:key, :repeat]),
    :KeyUp       => (:(EventModule.KeyUp),       [:key]),
    :KeyPress    => (:(EventModule.KeyPress),    [:char, :text]),
    :MouseDown   => (:(EventModule.MouseDown),   [:button, :x, :y]),
    :MouseUp     => (:(EventModule.MouseUp),     [:button, :x, :y]),
    :MousePress  => (:(EventModule.MousePress),  [:button, :x, :y, :count]),
    :MouseMove   => (:(EventModule.MouseMove),   [:x, :y, :buttons]),
    :MouseEnter  => (:(EventModule.MouseEnter),  [:x, :y, :buttons]),
    :MouseLeave  => (:(EventModule.MouseLeave),  [:x, :y, :buttons]),
    :MouseScroll => (:(EventModule.MouseScroll), [:dx, :dy, :x, :y]),
)

const _MODIFIER_FLAGS = (:ctrl, :shift, :alt, :meta)

# ─────────────────────────────────────────────────────────────────────────
# Reified patterns
#
# A field constraint is either `nothing` (any value) or a required value. Modifier
# constraints are `nothing` (unconstrained) or a `Vector{Symbol}` matched exactly:
# every listed flag held, every unlisted flag absent. An optional `guard` adds an
# event-dependent predicate (e.g. `isdigit(char)`).
# ─────────────────────────────────────────────────────────────────────────

"""
    EventPattern

Abstract supertype of the reified input patterns. Each answers
[`matches`](@ref)`(pattern, event) -> Bool` and [`describe`](@ref)`(pattern) -> String`.
"""
abstract type EventPattern end

# Exact modifier test. `nothing` = don't care.
function _mods_match(mods::Union{Vector{Symbol},Nothing}, m::Modifiers)
    mods === nothing && return true
    for f in _MODIFIER_FLAGS
        (getfield(m, f) === (f in mods)) || return false
    end
    return true
end

# Human prefix for a modifier set ("Ctrl+", "Ctrl+Alt+", "").
function _mod_prefix(mods::Union{Vector{Symbol},Nothing})
    (mods === nothing || isempty(mods)) && return ""
    labels = Dict(:ctrl => "Ctrl", :shift => "Shift", :alt => "Alt", :meta => "Meta")
    join((labels[f] for f in _MODIFIER_FLAGS if f in mods), "+") * "+"
end

# Readable label for a KeyDown key symbol.
function _key_label(key::Symbol)
    special = Dict(:period => ".", :space => "Space", :tab => "Tab", :return => "Return",
                   :home => "Home", :end => "End", :backspace => "Backspace",
                   :delete => "Delete", :escape => "Esc", :up => "↑", :down => "↓",
                   :left => "←", :right => "→", :page_up => "PgUp", :page_down => "PgDn")
    get(special, key, uppercasefirst(string(key)))
end

_button_label(b::Symbol) = b === :left ? "Left click" :
                           b === :right ? "Right click" :
                           b === :middle ? "Middle click" : "$(b) click"

"""
    matches(pattern::EventPattern, event) -> Bool

Would `event` fire `pattern`? Compares the constrained fields, the modifiers, and
the optional guard; an unconstrained field matches any value.
"""
function matches end

"""
    describe(pattern::EventPattern) -> String

How the pattern's input is written for a human — `"n"`, `"Tab"`, `"Ctrl+."`,
`"Left click"`.
"""
function describe end

# ── KeyPress: a character was typed. Modifiers are *not* matched — the OS has
#    already folded Shift into the character, and Ctrl-combinations arrive as
#    KeyDown, not KeyPress. An optional guard narrows a bound character (digits).
struct KeyPressPattern <: EventPattern
    char::Union{Char,Nothing}
    guard::Union{Function,Nothing}
    label::String
end
KeyPressPattern(char, guard) =
    KeyPressPattern(char, guard, char === nothing ? "character" : string(char))
KeyPressPattern(char) = KeyPressPattern(char, nothing)
matches(p::KeyPressPattern, e) =
    e isa KeyPress && (p.char === nothing || e.char == p.char) &&
    (p.guard === nothing || p.guard(e))
describe(p::KeyPressPattern) = p.label

# ── Keys: a physical key (chords, navigation). Modifiers matched exactly.
for (Pat, Ev, verb) in ((:KeyDownPattern, :KeyDown, ""),
                        (:KeyUpPattern, :KeyUp, "release "))
    @eval begin
        struct $Pat <: EventPattern
            key::Union{Symbol,Nothing}
            mods::Union{Vector{Symbol},Nothing}
            guard::Union{Function,Nothing}
        end
        matches(p::$Pat, e) =
            e isa $Ev && (p.key === nothing || e.key == p.key) &&
            _mods_match(p.mods, e.modifiers) && (p.guard === nothing || p.guard(e))
        describe(p::$Pat) =
            $verb * _mod_prefix(p.mods) * (p.key === nothing ? "key" : _key_label(p.key))
    end
end

# ── Mouse buttons. Position is never matched (it is geometry); only the button
#    and the modifiers are.
for (Pat, Ev, verb) in ((:MousePressPattern, :MousePress, ""),
                        (:MouseDownPattern, :MouseDown, "press "),
                        (:MouseUpPattern, :MouseUp, "release "))
    @eval begin
        struct $Pat <: EventPattern
            button::Union{Symbol,Nothing}
            mods::Union{Vector{Symbol},Nothing}
            guard::Union{Function,Nothing}
        end
        matches(p::$Pat, e) =
            e isa $Ev && (p.button === nothing || e.button == p.button) &&
            _mods_match(p.mods, e.modifiers) && (p.guard === nothing || p.guard(e))
        describe(p::$Pat) =
            $verb * _mod_prefix(p.mods) *
            (p.button === nothing ? "click" : _button_label(p.button))
    end
end

# ── Pointer motion and crossings. Position is never matched.
for (Pat, Ev, label) in ((:MouseMovePattern, :MouseMove, "move pointer"),
                         (:MouseEnterPattern, :MouseEnter, "pointer enters"),
                         (:MouseLeavePattern, :MouseLeave, "pointer leaves"),
                         (:MouseScrollPattern, :MouseScroll, "scroll"))
    @eval begin
        struct $Pat <: EventPattern
            mods::Union{Vector{Symbol},Nothing}
            guard::Union{Function,Nothing}
        end
        matches(p::$Pat, e) =
            e isa $Ev && _mods_match(p.mods, e.modifiers) &&
            (p.guard === nothing || p.guard(e))
        describe(p::$Pat) = _mod_prefix(p.mods) * $label
    end
end

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
    mods = Symbol[]
    for p in params.args
        p isa Symbol ||
            error("event pattern: modifier flags must be bare names (e.g. `; ctrl, alt`), got `$p`")
        p in _MODIFIER_FLAGS ||
            error("event pattern: unknown modifier `$p`; expected one of $(_MODIFIER_FLAGS)")
        push!(mods, p)
    end
    mods
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
        mods = nothing
        if !isempty(rest) && rest[1] isa Expr && rest[1].head == :parameters
            mods = _parse_modifiers(rest[1])
            rest = rest[2:end]
        end
        fields = FieldPattern[_parse_field(a) for a in rest]
        declared = _EVENT_TYPES[name][2]
        length(fields) <= length(declared) ||
            error("event pattern: $name takes at most $(length(declared)) positional field(s) " *
                  "$(declared), got $(length(fields))")
        return (name, fields, mods)
    else
        error("event pattern: unsupported pattern `$ex`")
    end
end

"""
    parse_event_rule(expr) -> EventRule

Parse one `pattern => result` rule (or `when(pattern, condition) => result`) of the
event pattern syntax. Throws with a message naming the offending expression when
the pattern is not one of the known event types.
"""
function parse_event_rule(ex)
    (ex isa Expr && ex.head == :call && ex.args[1] == :(=>)) ||
        error("event pattern: expected `pattern => result`, got `$ex`")
    lhs, rhs = ex.args[2], ex.args[3]
    if lhs isa Expr && lhs.head == :call && lhs.args[1] == :when
        length(lhs.args) == 3 ||
            error("event pattern: when(pattern, condition) expects exactly two arguments")
        type, fields, mods = _parse_pattern(lhs.args[2])
        return EventRule(type, fields, mods, lhs.args[3], rhs)
    else
        type, fields, mods = _parse_pattern(lhs)
        return EventRule(type, fields, mods, nothing, rhs)
    end
end

# A field's constraint value: a literal or interpolated expression is required,
# a bound or wildcard field is unconstrained (`nothing`).
_constraint_expr(::WildcardField) = :nothing
_constraint_expr(::BoundField) = :nothing
_constraint_expr(p::LiteralField) = QuoteNode(p.value)
_constraint_expr(p::ExpressionField) = esc(p.expr)

"""
    event_pattern_expr(rule::EventRule, guard_expr) -> Expr

The expression constructing `rule`'s reified [`EventPattern`](@ref), with
`guard_expr` (a `(event) -> Bool` closure expression, or `:nothing`) as its guard.
The pattern constructor is named unescaped, so it resolves in the scope of the
module whose macro emits it — that module needs `EventPatternModule` in scope, and
nothing else.
"""
function event_pattern_expr(rule::EventRule, guard_expr)
    name = rule.type
    name === nothing && error("event pattern: `_` catch-all has no reified pattern")
    field(i) = i <= length(rule.fields) ? _constraint_expr(rule.fields[i]) : :nothing
    mods = rule.modifiers === nothing ? :nothing :
           Expr(:vect, QuoteNode.(rule.modifiers)...)
    if name === :KeyPress
        :(KeyPressPattern($(field(1)), $guard_expr))
    elseif name === :KeyDown
        :(KeyDownPattern($(field(1)), $mods, $guard_expr))
    elseif name === :KeyUp
        :(KeyUpPattern($(field(1)), $mods, $guard_expr))
    elseif name === :MousePress
        :(MousePressPattern($(field(1)), $mods, $guard_expr))
    elseif name === :MouseDown
        :(MouseDownPattern($(field(1)), $mods, $guard_expr))
    elseif name === :MouseUp
        :(MouseUpPattern($(field(1)), $mods, $guard_expr))
    elseif name === :MouseMove
        :(MouseMovePattern($mods, $guard_expr))
    elseif name === :MouseEnter
        :(MouseEnterPattern($mods, $guard_expr))
    elseif name === :MouseLeave
        :(MouseLeavePattern($mods, $guard_expr))
    elseif name === :MouseScroll
        :(MouseScrollPattern($mods, $guard_expr))
    else
        error("event pattern: no reified pattern for $name")
    end
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

# Exact modifier test: each of the four flags must equal its membership in `mods`
# (listed => must be held, unlisted => must be absent).
function _gen_mod_test(scrutinee, mods::Vector{Symbol})
    tests = Any[:($scrutinee.modifiers.$flag === $(flag in mods)) for flag in _MODIFIER_FLAGS]
    foldr((a, b) -> :($a && $b), tests)
end

function _gen_rule(scrutinee, rule::EventRule)
    success = rule.guard === nothing ? esc(rule.result) :
              :($(esc(rule.guard)) ? $(esc(rule.result)) : _nomatch)

    # Catch-all `_` matches any event.
    rule.type === nothing && return success

    type, declared = _EVENT_TYPES[rule.type]

    # Wrap field matches from last to first so all binds are in scope for the
    # result and the guard.
    body = success
    for i in length(rule.fields):-1:1
        body = _gen_field_match(:($scrutinee.$(declared[i])), rule.fields[i], body)
    end

    if rule.modifiers !== nothing
        body = :($(_gen_mod_test(scrutinee, rule.modifiers)) ? $body : _nomatch)
    end

    return quote
        if $scrutinee isa $type
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
`isa`/field tests. Rules are tried top to bottom; when none matches, the
expression evaluates to `nothing`, so a reader body can simply
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
