"""
    EventCaseModule

The `@event_case` macro: a first-match-wins dispatch table over the keyboard
and mouse event types in [`KeyboardModule`](Keyboard.jl) and
[`MouseModule`](Mouse.jl). It is the sibling of `@reference_case` for input
events — it compiles a table of `pattern => result` rules to plain
`isa`/field tests and falls through to `nothing` when nothing matches, so a
projection reader body can simply `return @event_case evt begin … end`.

# Example

```julia
@event_case evt begin
    KeyDown(:period; ctrl)            => ToggleCollapseOperation()
    KeyDown(:home; ctrl, alt)         => TreeNavigateOperation(:root)
    when(KeyDown(k; alt), k in (:up, :down, :left, :right)) => TreeNavigateOperation(k)
    KeyPress(c)                       => insert_char(c)
    MousePress(:left, x, y)           => select_at(x, y)
    MouseScroll(dx, dy)               => scroll(dx, dy)
    _                                 => nothing
end
```

# Pattern syntax

Patterns mirror the event constructors:

- The constructor name selects the `isa` branch: `KeyDown`, `KeyUp`,
  `KeyPress`, `MouseDown`, `MouseUp`, `MousePress`, `MouseMove`,
  `MouseScroll`. A bare type name (`MouseScroll`) is a type-only match.
- Positional args match or bind the struct's **non-modifier** fields, in
  declared order:
  - a literal (`:period`, `'a'`, `42`, `true`) → equality test,
  - a bare identifier (`k`, `x`) → binds that field for the result/guard,
  - `_` → ignores that field,
  - `^(expr)` or any other expression → compared `==` to the runtime value.
- Modifier flags after `;` (`ctrl`, `shift`, `alt`, `meta`) are matched
  **exactly**: every listed flag must be held and every unlisted flag must be
  absent. Omitting the `;` block leaves modifiers unconstrained (so e.g.
  `KeyPress(c)` still matches a shifted capital letter).
- `when(pattern, condition)` adds a boolean guard; bound variables are in
  scope in the condition.
- `_` on its own is the catch-all.

Per-event positional field order (modifiers always via `;`, never positional):

| Pattern                          | Positional slots |
| -------------------------------- | ---------------- |
| `KeyDown(key, repeat)`           | key, repeat      |
| `KeyUp(key)`                     | key              |
| `KeyPress(char, text)`           | char, text       |
| `MouseDown/Up(button, x, y)`     | button, x, y     |
| `MousePress(button, x, y, count)` | button, x, y, count |
| `MouseMove(x, y, buttons)`       | x, y, buttons    |
| `MouseScroll(dx, dy, x, y)`      | dx, dy, x, y     |

Rules are tried top to bottom; the first match wins. If no rule matches the
expression evaluates to `nothing`.
"""
module EventCaseModule

import ..KeyboardModule
import ..MouseModule
import ..ModifiersModule

export var"@event_case"

# ------------------------------------------------------------
# Event-type table
#
# Maps the constructor name used in a pattern to its (fully-qualified) type
# expression and the ordered list of *non-modifier* fields that positional
# pattern arguments bind or match. Type expressions are emitted unescaped so
# they resolve in this module's scope (which imports the device modules), and
# callers need no imports.
# ------------------------------------------------------------

const _EVENT_TYPES = Dict{Symbol,Tuple{Any,Vector{Symbol}}}(
    :KeyDown     => (:(KeyboardModule.KeyDown),  [:key, :repeat]),
    :KeyUp       => (:(KeyboardModule.KeyUp),    [:key]),
    :KeyPress    => (:(KeyboardModule.KeyPress), [:char, :text]),
    :MouseDown   => (:(MouseModule.MouseDown),   [:button, :x, :y]),
    :MouseUp     => (:(MouseModule.MouseUp),     [:button, :x, :y]),
    :MousePress  => (:(MouseModule.MousePress),  [:button, :x, :y, :count]),
    :MouseMove   => (:(MouseModule.MouseMove),   [:x, :y, :buttons]),
    :MouseEnter  => (:(MouseModule.MouseEnter),  [:x, :y, :buttons]),
    :MouseLeave  => (:(MouseModule.MouseLeave),  [:x, :y, :buttons]),
    :MouseScroll => (:(MouseModule.MouseScroll), [:dx, :dy, :x, :y]),
)

const _MODIFIER_FLAGS = (:ctrl, :shift, :alt, :meta)

# ------------------------------------------------------------
# Value-pattern parsing (one positional field)
# ------------------------------------------------------------

abstract type EvPat end
struct EvWild   <: EvPat end
struct EvBind   <: EvPat; name::Symbol; end
struct EvLit    <: EvPat; value; end
struct EvInterp <: EvPat; expr; end

function _parse_value(ex)
    if ex === :_
        EvWild()
    elseif ex isa Symbol
        EvBind(ex)
    elseif ex isa QuoteNode
        EvLit(ex.value)
    elseif ex isa Bool || ex isa Int || ex isa Char || ex isa String
        EvLit(ex)
    elseif ex isa Expr && ex.head == :call && ex.args[1] == :(^)
        length(ex.args) == 2 || error("@event_case: ^(expr) expects exactly one argument: $ex")
        EvInterp(ex.args[2])
    else
        EvInterp(ex)
    end
end

# ------------------------------------------------------------
# Pattern parsing
#
# Returns (typename, posargs, mods) where:
#   typename :: Symbol | Nothing  (Nothing == catch-all `_`)
#   posargs  :: Vector{EvPat}
#   mods     :: Vector{Symbol} | Nothing  (Nothing == no `;` block = any)
# ------------------------------------------------------------

function _parse_pattern(ex)
    if ex === :_
        return (nothing, EvPat[], nothing)
    elseif ex isa Symbol
        haskey(_EVENT_TYPES, ex) ||
            error("@event_case: unknown event type `$ex` (use `_` for catch-all)")
        return (ex, EvPat[], nothing)
    elseif ex isa Expr && ex.head == :call
        tname = ex.args[1]
        (tname isa Symbol && haskey(_EVENT_TYPES, tname)) ||
            error("@event_case: unknown event type in pattern `$ex`")
        rest = ex.args[2:end]
        mods = nothing
        if !isempty(rest) && rest[1] isa Expr && rest[1].head == :parameters
            mods = _parse_mods(rest[1])
            rest = rest[2:end]
        end
        posargs = EvPat[_parse_value(a) for a in rest]
        fields = _EVENT_TYPES[tname][2]
        length(posargs) <= length(fields) ||
            error("@event_case: $tname takes at most $(length(fields)) positional field(s) " *
                  "$(fields), got $(length(posargs))")
        return (tname, posargs, mods)
    else
        error("@event_case: unsupported pattern `$ex`")
    end
end

function _parse_mods(params::Expr)
    mods = Symbol[]
    for p in params.args
        p isa Symbol ||
            error("@event_case: modifier flags must be bare names (e.g. `; ctrl, alt`), got `$p`")
        p in _MODIFIER_FLAGS ||
            error("@event_case: unknown modifier `$p`; expected one of $(_MODIFIER_FLAGS)")
        push!(mods, p)
    end
    mods
end

# ------------------------------------------------------------
# Rule parsing (`pattern => result`, optionally `when(pattern, cond) => result`)
# ------------------------------------------------------------

function _parse_rule(ex)
    (ex isa Expr && ex.head == :call && ex.args[1] == :(=>)) ||
        error("@event_case: expected `pattern => result`, got `$ex`")
    lhs, rhs = ex.args[2], ex.args[3]
    if lhs isa Expr && lhs.head == :call && lhs.args[1] == :when
        length(lhs.args) == 3 ||
            error("@event_case: when(pattern, condition) expects exactly two arguments")
        tname, posargs, mods = _parse_pattern(lhs.args[2])
        return (tname, posargs, mods, lhs.args[3], rhs)
    else
        tname, posargs, mods = _parse_pattern(lhs)
        return (tname, posargs, mods, nothing, rhs)
    end
end

# ------------------------------------------------------------
# Code generation
# ------------------------------------------------------------

# Each generated rule evaluates to the (escaped) result on a full match, or to
# the `_nomatch` sentinel otherwise.

_gen_value_match(accessor, ::EvWild, success) = success
_gen_value_match(accessor, p::EvBind, success) =
    :(let $(esc(p.name)) = $accessor; $success end)
_gen_value_match(accessor, p::EvLit, success) =
    :($accessor == $(QuoteNode(p.value)) ? $success : _nomatch)
_gen_value_match(accessor, p::EvInterp, success) =
    :($accessor == $(esc(p.expr)) ? $success : _nomatch)

# Exact modifier test: each of the four flags must equal its membership in
# `mods` (listed => must be held, unlisted => must be absent).
function _gen_mod_test(scrut, mods::Vector{Symbol})
    tests = Any[:($scrut.modifiers.$flag === $(flag in mods)) for flag in _MODIFIER_FLAGS]
    foldr((a, b) -> :($a && $b), tests)
end

function _gen_rule(scrut, rule)
    tname, posargs, mods, cond, rhs = rule

    success = cond === nothing ? esc(rhs) :
              :($(esc(cond)) ? $(esc(rhs)) : _nomatch)

    # Catch-all `_` matches any event.
    tname === nothing && return success

    typ, fields = _EVENT_TYPES[tname]

    # Wrap field matches from last to first so all binds are in scope for the
    # result and the guard.
    body = success
    for i in length(posargs):-1:1
        body = _gen_value_match(:($scrut.$(fields[i])), posargs[i], body)
    end

    if mods !== nothing
        body = :($(_gen_mod_test(scrut, mods)) ? $body : _nomatch)
    end

    return quote
        if $scrut isa $typ
            $body
        else
            _nomatch
        end
    end
end

# ------------------------------------------------------------
# Macro entry point
# ------------------------------------------------------------

macro event_case(scrutinee, block)
    entries = block isa Expr && block.head == :block ? block.args : [block]
    rules = [_parse_rule(e) for e in entries if !(e isa LineNumberNode)]

    scrut = gensym(:evt)

    chain = :nothing
    for rule in reverse(rules)
        rule_ex = _gen_rule(scrut, rule)
        chain = quote
            let _m = $rule_ex
                _m === _nomatch ? $chain : _m
            end
        end
    end

    return quote
        let $scrut = $(esc(scrutinee)), _nomatch = Base.RefValue{Any}()
            $chain
        end
    end
end

end # module
