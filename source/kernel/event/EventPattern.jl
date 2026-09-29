# Fragment of `EventModule` — the event pattern language: the reified
# `EventPattern`, the parser of the pattern syntax, and `@event_case`. The syntax is
# documented on `@event_case`.

# The event type that `name` names: first in `scope`, the module where the pattern
# is written, and then in `EventModule`. The result is `nothing` for a name that is
# no concrete event type there.
function _find_event_type(name::Symbol, scope::Module)
    for candidate in (scope, EventModule)
        isdefined(candidate, name) || continue
        value = getfield(candidate, name)
        value isa Type && value <: Event && isconcretetype(value) && return value
    end
    nothing
end

# The fields of `type` that a positional pattern argument binds or matches, in the
# declared order. `modifiers` is written after the `;`, so it is not one of them,
# and `time` is not a part of what a gesture is.
_get_positional_event_fields(type::Type) =
    Symbol[field for field in fieldnames(type) if !(field in (:modifiers, :time))]

const _MODIFIER_FLAGS = (:ctrl, :shift, :alt, :meta)

# ── The reified pattern ─────────────────────────────────────────────────────

"""
    EventPattern{E<:Event}(fields, modifiers, guard[, label])

A pattern as data: an event type `E`, the fields that must hold a value, the
modifiers, a guard and a label.

- `fields` is a `NamedTuple` of the fields that must be equal to a value. A field
  that is not in it matches any value.
- `modifiers` is `nothing`, which matches any modifiers, or a `Vector{Symbol}` that
  must match exactly: every listed flag held, and every other flag not held. A flag
  is `:ctrl`, `:shift`, `:alt` or `:meta`, and the constructor throws an
  `ArgumentError` for another name.
- `guard` is `nothing` or a function `event -> Bool` for a condition that the
  fields can not state.
- `label` is `nothing` or the text that `describe_event_pattern` returns. A guard has
  no text of its own, so a pattern for the digits reads better as `"0-9"` than as
  `"character"`.

Use it to keep a pattern as a value: to test an event with `matches_event_pattern`,
and to show the pattern to a person with `describe_event_pattern`.

# Example

    pattern = EventPattern{KeyDown}((key = :period,), [:ctrl], nothing)
    event = KeyDown(:period, ModifierKeys(ctrl = true); time = time())
    matches_event_pattern(pattern, event)       # true
    describe_event_pattern(pattern)             # "Ctrl+."

See also `KeyDownPattern` and the other constructors for one event type.
"""
struct EventPattern{E<:Event}
    fields::NamedTuple
    modifiers::Union{Vector{Symbol},Nothing}
    guard::Union{Function,Nothing}
    label::Union{String,Nothing}
    function EventPattern{E}(fields, modifiers, guard, label) where {E<:Event}
        for flag in (modifiers === nothing ? () : modifiers)
            flag in _MODIFIER_FLAGS || throw(ArgumentError(
                "event pattern: unknown modifier `$flag`; " *
                "expected one of $(_MODIFIER_FLAGS)"))
        end
        new{E}(fields, modifiers, guard, label)
    end
end
EventPattern{E}(fields, modifiers, guard) where {E<:Event} =
    EventPattern{E}(fields, modifiers, guard, nothing)

"""
    matches_event_pattern(pattern::EventPattern, event) -> Bool

Whether `event` matches `pattern`: the event has the type of the pattern, every field
of the pattern is equal, the modifiers match, and the guard, if any, holds.

Use it to find the pattern that an event fires, in a table of patterns.

# Example

    matches_event_pattern(KeyPressPattern('a'), KeyPress('a'; time = time()))   # true

See also `describe_event_pattern`.
"""
function matches_event_pattern(pattern::EventPattern{E}, event) where {E}
    event isa E || return false
    for (name, value) in pairs(pattern.fields)
        getfield(event, name) == value || return false
    end
    _match_modifiers(pattern.modifiers, get_modifier_keys(event)) || return false
    return pattern.guard === nothing || pattern.guard(event)::Bool
end

# The exact modifier test. `nothing` matches any modifiers.
function _match_modifiers(modifiers::Union{Vector{Symbol},Nothing}, held::ModifierKeys)
    modifiers === nothing && return true
    for flag in _MODIFIER_FLAGS
        (getfield(held, flag) === (flag in modifiers)) || return false
    end
    return true
end

# The constructors for one event type. Each names the type and the field that a
# pattern constrains most often; `nothing` for that field matches any value.

_constrain_field(name::Symbol, value) =
    value === nothing ? NamedTuple() : NamedTuple{(name,)}((value,))

"""
    KeyPressPattern(char; modifiers = nothing, guard = nothing, label = nothing)
    KeyDownPattern(key; modifiers = nothing, guard = nothing, label = nothing)
    KeyUpPattern(key; modifiers = nothing, guard = nothing, label = nothing)
    MouseDownPattern(button; modifiers = nothing, guard = nothing, label = nothing)
    MouseUpPattern(button; modifiers = nothing, guard = nothing, label = nothing)
    MousePressPattern(button; modifiers = nothing, guard = nothing, label = nothing)
    MouseMovePattern(; modifiers = nothing, guard = nothing, label = nothing)
    MouseEnterPattern(; modifiers = nothing, guard = nothing, label = nothing)
    MouseLeavePattern(; modifiers = nothing, guard = nothing, label = nothing)
    MouseScrollPattern(; modifiers = nothing, guard = nothing, label = nothing)

An `EventPattern` for one event type. The first argument, when there is one, is
the value of the field that the pattern constrains; `nothing` matches any value.

Use them to write a pattern without its `NamedTuple` of fields.

# Example

    KeyDownPattern(:period; modifiers = [:ctrl])    # Ctrl+.
    MousePressPattern(:left)                        # a left click

See also `EventPattern`.
"""
KeyPressPattern(char; modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{KeyPress}(_constrain_field(:char, char), modifiers, guard, label)
KeyDownPattern(key; modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{KeyDown}(_constrain_field(:key, key), modifiers, guard, label)
KeyUpPattern(key; modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{KeyUp}(_constrain_field(:key, key), modifiers, guard, label)
MouseDownPattern(button; modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{MouseDown}(_constrain_field(:button, button), modifiers, guard, label)
MouseUpPattern(button; modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{MouseUp}(_constrain_field(:button, button), modifiers, guard, label)
MousePressPattern(button; modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{MousePress}(_constrain_field(:button, button), modifiers, guard, label)
MouseMovePattern(; modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{MouseMove}(NamedTuple(), modifiers, guard, label)
MouseEnterPattern(; modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{MouseEnter}(NamedTuple(), modifiers, guard, label)
MouseLeavePattern(; modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{MouseLeave}(NamedTuple(), modifiers, guard, label)
MouseScrollPattern(; modifiers = nothing, guard = nothing, label = nothing) =
    EventPattern{MouseScroll}(NamedTuple(), modifiers, guard, label)

# ── The description of a pattern ────────────────────────────────────────────

"""
    describe_event_pattern(pattern::EventPattern) -> String

The input of `pattern`, written for a person: `"n"`, `"Ctrl+."`, `"Left click"`,
`"scroll"`. The label of the pattern, when it has one, is the text. Otherwise the
text comes from the event type, the fields and the modifiers. An event type with no
text of its own reads as its type name in words, such as `"window resize"`.

Use it to list the input that a table of patterns answers, such as on a page of
key bindings.

# Example

    describe_event_pattern(KeyPressPattern('a'; modifiers = [:ctrl]))    # "Ctrl+a"

See also `matches_event_pattern`.
"""
describe_event_pattern(pattern::EventPattern{E}) where {E} =
    pattern.label === nothing ? _describe(E, pattern) : pattern.label

# The prefix for a set of modifiers: "Ctrl+", "Ctrl+Alt+", or "".
function _get_modifier_prefix(modifiers::Union{Vector{Symbol},Nothing})
    (modifiers === nothing || isempty(modifiers)) && return ""
    labels = Dict(:ctrl => "Ctrl", :shift => "Shift", :alt => "Alt", :meta => "Meta")
    join((labels[flag] for flag in _MODIFIER_FLAGS if flag in modifiers), "+") * "+"
end

_get_key_label(::Nothing) = "key"
function _get_key_label(key::Symbol)
    special = Dict(:period => ".", :space => "Space", :tab => "Tab", :return => "Return",
                   :home => "Home", :end => "End", :backspace => "Backspace",
                   :delete => "Delete", :escape => "Esc", :up => "↑", :down => "↓",
                   :left => "←", :right => "→", :page_up => "PgUp", :page_down => "PgDn")
    get(special, key, uppercasefirst(string(key)))
end

_get_button_label(::Nothing) = "click"
_get_button_label(button::Symbol) =
    button === :left   ? "Left click" :
    button === :right  ? "Right click" :
    button === :middle ? "Middle click" : "$(button) click"

# The name of the button of a `MouseDown` or a `MouseUp`: "Left button", or "button".
_get_button_name(::Nothing) = "button"
_get_button_name(button::Symbol) = uppercasefirst(string(button)) * " button"

# The words of a type name: `WindowResize` gives "window resize".
_get_type_words(type::Type) =
    lowercase(replace(string(nameof(type)), r"(?<=[a-z0-9])(?=[A-Z])" => " "))

_get_field(pattern::EventPattern, name::Symbol) = get(pattern.fields, name, nothing)

# The text of a pattern: the prefix of its modifiers, and then `text`.
_prefix_modifiers(pattern, text) = _get_modifier_prefix(pattern.modifiers) * text

_describe_key(pattern) =
    _prefix_modifiers(pattern, _get_key_label(_get_field(pattern, :key)))
_describe_button(pattern) =
    _prefix_modifiers(pattern, _get_button_label(_get_field(pattern, :button)))

_describe(::Type{KeyDown}, pattern) = _describe_key(pattern)
_describe(::Type{KeyUp}, pattern) = "release " * _describe_key(pattern)
function _describe(::Type{KeyPress}, pattern)
    char = _get_field(pattern, :char)
    _prefix_modifiers(pattern, char === nothing ? "character" : string(char))
end
_describe(::Type{KeyChord}, pattern) = "key chord"
_describe(::Type{MousePress}, pattern) = _describe_button(pattern)
_describe(::Type{MouseDown}, pattern) =
    _prefix_modifiers(pattern, _get_button_name(_get_field(pattern, :button)) * " down")
_describe(::Type{MouseUp}, pattern) =
    _prefix_modifiers(pattern, _get_button_name(_get_field(pattern, :button)) * " up")
_describe(::Type{MouseMove}, pattern) = _prefix_modifiers(pattern, "move pointer")
_describe(::Type{MouseEnter}, pattern) = _prefix_modifiers(pattern, "pointer enters")
_describe(::Type{MouseLeave}, pattern) = _prefix_modifiers(pattern, "pointer leaves")
_describe(::Type{MouseScroll}, pattern) = _prefix_modifiers(pattern, "scroll")
_describe(::Type{E}, pattern) where {E<:Event} =
    _prefix_modifiers(pattern, _get_type_words(E))

# ── The parser, which `@event_case` and every macro that binds events share ──

# One positional field of a pattern.
abstract type FieldPattern end
struct WildcardField   <: FieldPattern end
struct BoundField      <: FieldPattern; name::Symbol; end
struct LiteralField    <: FieldPattern; value; end
struct ExpressionField <: FieldPattern; expr; end

"""
    EventPatternRule(type, fields, modifiers, guard, result)

One parsed `pattern => result` rule.

- `type` is the event type, or `nothing` for the catch-all `_`.
- `fields` holds the positional field patterns, in the declared order.
- `modifiers` is the exact set of modifiers, or `nothing` for any modifiers.
- `guard` is the condition of `when(pattern, condition)`, or `nothing`.
- `result` is the right side of the rule, not evaluated.

Use it to write a macro on the pattern syntax: `parse_event_pattern_rule` makes it,
and `build_event_pattern_expr` and `build_event_field_bindings` read it.

See also `@event_case`, which documents the syntax.
"""
struct EventPatternRule
    type::Union{DataType,Nothing}
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
        length(ex.args) == 2 ||
            error("event pattern: ^(expr) expects exactly one argument: $ex")
        ExpressionField(ex.args[2])
    else
        ExpressionField(ex)
    end
end

function _parse_modifiers(parameters::Expr)
    modifiers = Symbol[]
    for flag in parameters.args
        flag isa Symbol || error(
            "event pattern: modifier flags must be bare names, such as `; ctrl, alt`, " *
            "got `$flag`")
        flag in _MODIFIER_FLAGS || error(
            "event pattern: unknown modifier `$flag`; expected one of $(_MODIFIER_FLAGS)")
        push!(modifiers, flag)
    end
    modifiers
end

# The type, the fields and the modifiers of a pattern; the type is `nothing` for the
# catch-all `_`.
function _parse_pattern(ex, scope::Module)
    if ex === :_
        return (nothing, FieldPattern[], nothing)
    elseif ex isa Symbol
        type = _find_event_type(ex, scope)
        type === nothing && error(
            "event pattern: `$ex` is no event type in scope (use `_` for catch-all)")
        return (type, FieldPattern[], nothing)
    elseif ex isa Expr && ex.head == :call
        name = ex.args[1]
        type = name isa Symbol ? _find_event_type(name, scope) : nothing
        type === nothing && error("event pattern: no event type in scope in `$ex`")
        rest = ex.args[2:end]
        modifiers = nothing
        if !isempty(rest) && rest[1] isa Expr && rest[1].head == :parameters
            modifiers = _parse_modifiers(rest[1])
            rest = rest[2:end]
        end
        fields = FieldPattern[_parse_field(argument) for argument in rest]
        declared = _get_positional_event_fields(type)
        length(fields) <= length(declared) || error(
            "event pattern: $name takes at most $(length(declared)) positional " *
            "field(s) $(declared), got $(length(fields))")
        return (type, fields, modifiers)
    else
        error("event pattern: unsupported pattern `$ex`")
    end
end

"""
    parse_event_pattern_rule(expr; scope = EventModule) -> EventPatternRule

Parse one rule of the pattern syntax, `pattern => result` or
`when(pattern, condition) => result`. The name of the event type resolves in
`scope`, and then in `EventModule`. An error names the expression when the name is
no concrete event type.

Use it in a macro on the pattern syntax, with `scope = __module__`, so that an event
type of the package that uses the macro is matchable.

See also `build_event_pattern_expr`, `build_event_field_bindings` and `@event_case`.
"""
function parse_event_pattern_rule(ex; scope::Module = EventModule)
    (ex isa Expr && ex.head == :call && ex.args[1] == :(=>)) ||
        error("event pattern: expected `pattern => result`, got `$ex`")
    lhs, rhs = ex.args[2], ex.args[3]
    if lhs isa Expr && lhs.head == :call && lhs.args[1] == :when
        length(lhs.args) == 3 ||
            error("event pattern: when(pattern, condition) expects exactly two arguments")
        type, fields, modifiers = _parse_pattern(lhs.args[2], scope)
        return EventPatternRule(type, fields, modifiers, lhs.args[3], rhs)
    else
        type, fields, modifiers = _parse_pattern(lhs, scope)
        return EventPatternRule(type, fields, modifiers, nothing, rhs)
    end
end

# The value that a constrained field must hold; a bound or a wildcard field
# constrains nothing.
_is_constrained(field::FieldPattern) = field isa LiteralField || field isa ExpressionField
_get_constraint_expr(field::LiteralField) = QuoteNode(field.value)
_get_constraint_expr(field::ExpressionField) = esc(field.expr)

"""
    build_event_pattern_expr(rule::EventPatternRule, guard_expr) -> Expr

The expression that makes the `EventPattern` of `rule`, with `guard_expr` as its
guard: a closure expression `event -> Bool`, or `:nothing`. The event type is in
the expression as a value, so the expression resolves in any module.

Use it in a macro on the pattern syntax that keeps its patterns as data.

See also `parse_event_pattern_rule`.
"""
function build_event_pattern_expr(rule::EventPatternRule, guard_expr)
    rule.type === nothing && error("event pattern: `_` catch-all has no reified pattern")
    declared = _get_positional_event_fields(rule.type)
    names, values = Symbol[], Any[]
    for i in eachindex(rule.fields)
        _is_constrained(rule.fields[i]) || continue
        push!(names, declared[i])
        push!(values, _get_constraint_expr(rule.fields[i]))
    end
    fields = :($(NamedTuple{Tuple(names)})(($(values...),)))
    modifiers = rule.modifiers === nothing ? :nothing :
                Expr(:vect, QuoteNode.(rule.modifiers)...)
    :($(EventPattern{rule.type})($fields, $modifiers, $guard_expr))
end

"""
    build_event_field_bindings(rule::EventPatternRule, event_symbol, body) -> Expr

`body` inside the `let` bindings of the bound positional fields of `rule`, read
from `event_symbol`. So a guard and a result can name a field, as `c` in
`KeyPress(c)`, without the order of the fields of the event.

Use it in a macro on the pattern syntax, around the code of a rule. The result is
`body` itself when the rule binds no field.

See also `parse_event_pattern_rule`.
"""
function build_event_field_bindings(rule::EventPatternRule, event_symbol, body)
    rule.type === nothing && return body
    declared = _get_positional_event_fields(rule.type)
    for i in length(rule.fields):-1:1
        field = rule.fields[i]
        if field isa BoundField
            body = :(let $(esc(field.name)) = $event_symbol.$(declared[i]); $body end)
        end
    end
    body
end

# ── @event_case, the compiled table ─────────────────────────────────────────

# A generated rule evaluates to the escaped result when the event matches, and to
# the `_nomatch` sentinel otherwise.

_build_field_match(accessor, ::WildcardField, success) = success
_build_field_match(accessor, field::BoundField, success) =
    :(let $(esc(field.name)) = $accessor; $success end)
_build_field_match(accessor, field::LiteralField, success) =
    :($accessor == $(QuoteNode(field.value)) ? $success : _nomatch)
_build_field_match(accessor, field::ExpressionField, success) =
    :($accessor == $(esc(field.expr)) ? $success : _nomatch)

# The exact modifier test: each of the four flags must equal its membership in
# `modifiers`. The test reads the modifiers through `get_modifier_keys`, which is in
# the expression as a value, so the expression resolves in any module.
function _build_modifier_test(event, modifiers::Vector{Symbol})
    held = gensym(:modifiers)
    tests = Any[:($held.$flag === $(flag in modifiers)) for flag in _MODIFIER_FLAGS]
    :(let $held = $get_modifier_keys($event); $(foldr((a, b) -> :($a && $b), tests)) end)
end

function _build_rule(event, rule::EventPatternRule)
    success = rule.guard === nothing ? esc(rule.result) :
              :($(esc(rule.guard)) ? $(esc(rule.result)) : _nomatch)

    # The catch-all `_` matches any event.
    rule.type === nothing && return success

    declared = _get_positional_event_fields(rule.type)

    # The field tests nest from the last field to the first, so every binding is in
    # scope for the guard and the result.
    body = success
    for i in length(rule.fields):-1:1
        body = _build_field_match(:($event.$(declared[i])), rule.fields[i], body)
    end

    if rule.modifiers !== nothing
        body = :($(_build_modifier_test(event, rule.modifiers)) ? $body : _nomatch)
    end

    return quote
        if $event isa $(rule.type)
            $body
        else
            _nomatch
        end
    end
end

"""
    @event_case event begin
        pattern => result
        …
    end

A table of `pattern => result` rules for an input event. The first rule whose
pattern matches `event` gives the value, and the value is `nothing` when no rule
matches. The rules compile to plain `isa` and field tests.

Use it to turn an event into a value, such as an operation, in one expression.

# Example

    @event_case event begin
        KeyDown(:period; ctrl)                    => on_toggle()
        when(KeyDown(k; alt), k in (:up, :down))  => on_navigate(k)
        KeyPress(c)                               => insert_char(c)
        MousePress(:left, x, y)                   => select_at(x, y)
        _                                         => nothing
    end

# The pattern syntax

A pattern is written like the constructor of its event.

- The name selects the event type. It is any concrete `Event` type whose name is
  visible where the pattern is written, or one of `EventModule`. A bare name, such
  as `MouseScroll`, tests the type only.
- A positional argument matches or binds a field of the event, in the declared
  order of the fields, without `modifiers` and `time`: `KeyDown(key, repeat)`,
  `KeyPress(char, text)`, `MousePress(button, x, y, count)`, `MouseScroll(dx, dy, x,
  y)`. A literal, such as `:period`, `'a'` or `42`, must be equal to the field. A
  bare name, such as `k`, binds the field. `_` ignores the field. `^(expr)`, and any
  other expression, must be `==` to the field at run time.
- Modifier flags after `;`, from `ctrl`, `shift`, `alt` and `meta`, must match
  exactly: every listed flag held, and every other flag not held. A pattern without
  `;` matches any modifiers, so `KeyPress(c)` also matches a capital letter typed
  with Shift.
- `when(pattern, condition)` adds a condition, in which the bound names are in
  scope.
- `_` alone matches any event.

An event type of another package is matchable where its name is visible, and it
must exist before the macro expands.

See also `parse_event_pattern_rule`, the parser for a macro on the same syntax, and
`EventPattern`, a pattern as data.
"""
macro event_case(scrutinee, block)
    entries = block isa Expr && block.head == :block ? block.args : [block]
    rules = [parse_event_pattern_rule(entry; scope = __module__)
             for entry in entries if !(entry isa LineNumberNode)]

    event = gensym(:event)

    chain = :nothing
    for rule in reverse(rules)
        rule_expr = _build_rule(event, rule)
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
