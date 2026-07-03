"""
    GestureBindingModule

Reified **gesture → operation** bindings: the data layer the `read_gesture`
seam was missing. A `GestureBinding` is a piece of *data* that can both **fire**
an operation and be **inspected** (gesture rendering + human description +
applicability), so the very same declaration that handles a key both edits the
document and feeds the gesture-help projection.

The pieces:

- **`GesturePattern`** (`KeyPressPattern`, `KeyDownPattern`, … ) — a reified
  input pattern with `matches(pattern, event)::Bool` (does this event fire it?)
  and `describe(pattern)::String` (how is the gesture written, e.g. `"n"`,
  `"Tab"`, `"Ctrl+."`). Built from the same pattern surface as
  [`@event_case`](../device/EventCase.jl); the parser is reused verbatim.
- **`GestureBinding`** — `pattern` + `operation(doc, event)->Operation|Nothing`
  (build the edit) + `applicable(doc, selection)->Bool` (an *event-independent*
  state precondition) + a human `description` + a `domain` tag.
- **Registry** keyed by document type with supertype inheritance:
  `get_document_gesture_bindings(T)` collects `T`'s own bindings plus every supertype's, so
  `@gestures JsonDocument` covers `JsonNull`, `JsonArray`, … for free. The own
  bindings live in `get_document_gesture_bindings_own(::Type{T})` *methods* (not a mutable
  table) so they survive precompilation.
- **`@gestures DocType begin … end`** — the declarative authoring form. It emits
  the `get_document_gesture_bindings_own(::Type{DocType})` method holding the reified table.
  Firing is then a *single generic interpreter* (`read_document_gesture`, wired
  into `read_gesture`) that walks that very table — so what *fires* is provably
  the set that is *shown*.

This is the kernel half (Stage 1 + the `get_projection_gesture_bindings` seam / collector
defaults of Stage 2). The JSON authoring set is ported onto it in
`document/Json.jl`; the contextual collector combinator methods live with the
projection combinators they mirror.
"""
module GestureBindingModule

import ..KeyboardModule: KeyDown, KeyUp, KeyPress
import ..MouseModule: MouseDown, MouseUp, MousePress, MouseMove, MouseScroll
import ..ModifiersModule: Modifiers
import ..DocumentApiModule: Document, read_gesture
import ..ProjectionApiModule: Projection
# Reuse the `@event_case` pattern parser for the LHS of `@gestures` rules.
# These EventCase internals are deliberately shared (not exported) — see the
# "deliberately-shared parser internals" note in device/EventCase.jl; the seam
# goes away when Phase 2 merges EventCase + GestureBinding into one module.
import ..EventCaseModule: _parse_rule, _EVENT_TYPES, EvPat, EvWild, EvBind, EvLit, EvInterp

export GesturePattern, KeyPressPattern, KeyDownPattern, KeyUpPattern,
       MouseDownPattern, MouseUpPattern, MousePressPattern, MouseMovePattern,
       MouseScrollPattern,
       GestureBinding, matches, describe,
       get_document_gesture_bindings, get_document_gesture_bindings_own, get_instance_gesture_bindings,
       read_document_gesture, read_node_gesture,
       get_projection_gesture_bindings, read_projection_gesture, collect_gesture_bindings, get_applicable_gesture_bindings,
       is_help_gesture, var"@gestures", var"@gesture_set"

# ─────────────────────────────────────────────────────────────────────────
# Gesture patterns
#
# A pattern is reified *data* that answers two questions about an event:
#   matches(pattern, event)  — would this event fire the binding?
#   describe(pattern)        — how is the gesture written for the user?
# A field constraint is either `nothing` (any value) or a required value
# (literal or interpolated). Modifier constraints follow the `@event_case`
# model: `nothing` = unconstrained, a `Vector{Symbol}` = exact (every listed
# flag held, every unlisted flag absent). An optional `guard` adds an
# event-dependent predicate (e.g. `isdigit(char)`).
# ─────────────────────────────────────────────────────────────────────────

abstract type GesturePattern end

const _MODFLAGS = (:ctrl, :shift, :alt, :meta)

# Exact modifier test, mirroring `@event_case`. `nothing` = don't care.
function _mods_match(mods::Union{Vector{Symbol},Nothing}, m::Modifiers)
    mods === nothing && return true
    for f in _MODFLAGS
        (getfield(m, f) === (f in mods)) || return false
    end
    return true
end

# Human prefix for a modifier set ("Ctrl+", "Ctrl+Alt+", "").
function _mod_prefix(mods::Union{Vector{Symbol},Nothing})
    (mods === nothing || isempty(mods)) && return ""
    labels = Dict(:ctrl => "Ctrl", :shift => "Shift", :alt => "Alt", :meta => "Meta")
    join((labels[f] for f in _MODFLAGS if f in mods), "+") * "+"
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

# ── KeyPress: a character was typed. Modifiers are *not* matched — the OS has
#    already folded Shift into the character, and Ctrl-combinations arrive as
#    KeyDown, not KeyPress. An optional guard narrows a bound character (digits).
struct KeyPressPattern <: GesturePattern
    char::Union{Char,Nothing}
    guard::Union{Function,Nothing}
    label::String
end
KeyPressPattern(char) = KeyPressPattern(char, nothing, char === nothing ? "character" : string(char))
matches(p::KeyPressPattern, e) =
    e isa KeyPress && (p.char === nothing || e.char == p.char) &&
    (p.guard === nothing || p.guard(e))
describe(p::KeyPressPattern) = p.label

# ── KeyDown: a physical key (chords, navigation). Modifiers matched exactly.
struct KeyDownPattern <: GesturePattern
    key::Union{Symbol,Nothing}
    mods::Union{Vector{Symbol},Nothing}
    guard::Union{Function,Nothing}
end
matches(p::KeyDownPattern, e) =
    e isa KeyDown && (p.key === nothing || e.key == p.key) &&
    _mods_match(p.mods, e.modifiers) && (p.guard === nothing || p.guard(e))
describe(p::KeyDownPattern) =
    _mod_prefix(p.mods) * (p.key === nothing ? "key" : _key_label(p.key))

struct KeyUpPattern <: GesturePattern
    key::Union{Symbol,Nothing}
    mods::Union{Vector{Symbol},Nothing}
    guard::Union{Function,Nothing}
end
matches(p::KeyUpPattern, e) =
    e isa KeyUp && (p.key === nothing || e.key == p.key) &&
    _mods_match(p.mods, e.modifiers) && (p.guard === nothing || p.guard(e))
describe(p::KeyUpPattern) =
    "release " * _mod_prefix(p.mods) * (p.key === nothing ? "key" : _key_label(p.key))

# ── Mouse buttons. Position is never matched (it is geometry); only the button
#    and modifiers are. Help lists them generically until Stage 0 intent names.
for (Pat, Ev, verb) in ((:MousePressPattern, :MousePress, ""),
                        (:MouseDownPattern, :MouseDown, "press "),
                        (:MouseUpPattern, :MouseUp, "release "))
    @eval begin
        struct $Pat <: GesturePattern
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

struct MouseMovePattern <: GesturePattern
    mods::Union{Vector{Symbol},Nothing}
    guard::Union{Function,Nothing}
end
matches(p::MouseMovePattern, e) =
    e isa MouseMove && _mods_match(p.mods, e.modifiers) &&
    (p.guard === nothing || p.guard(e))
describe(p::MouseMovePattern) = _mod_prefix(p.mods) * "move pointer"

struct MouseScrollPattern <: GesturePattern
    mods::Union{Vector{Symbol},Nothing}
    guard::Union{Function,Nothing}
end
matches(p::MouseScrollPattern, e) =
    e isa MouseScroll && _mods_match(p.mods, e.modifiers) &&
    (p.guard === nothing || p.guard(e))
describe(p::MouseScrollPattern) = _mod_prefix(p.mods) * "scroll"

# ─────────────────────────────────────────────────────────────────────────
# Gesture binding
# ─────────────────────────────────────────────────────────────────────────

"""
    GestureBinding(pattern, operation, applicable, description, domain)

One reified gesture → operation rule.

- `pattern::GesturePattern` — what input fires it (and how it is described).
- `operation::Function` — `(doc, event) -> Operation | Nothing`, builds the
  edit in `doc`'s own reference vocabulary. May return `nothing` for a finer,
  event-dependent guard that the precondition cannot express.
- `applicable::Function` — `(doc, selection) -> Bool`, an *event-independent*
  state precondition. This is what greys a row out in the help projection.
- `description::String` — human text for *what the binding does*.
- `domain::String` — a tag (usually the document type name) for grouping help.
"""
struct GestureBinding
    pattern::GesturePattern
    operation::Function
    applicable::Function
    description::String
    domain::String
end

# ─────────────────────────────────────────────────────────────────────────
# Registry (own bindings per type) + supertype inheritance
#
# Own bindings are held in `get_document_gesture_bindings_own(::Type{T})` *methods* (emitted
# by `@gestures`), not a mutable table, so they persist across precompilation —
# mutating a Dict at a domain module's load time would be lost. `get_document_gesture_bindings`
# walks the supertype chain over those methods, caching the merged result in a
# runtime Dict (caches repopulate at runtime, so they are precompile-safe).
# ─────────────────────────────────────────────────────────────────────────

"""
    get_document_gesture_bindings_own(::Type{T}) -> Vector{GestureBinding}

The bindings declared *directly* on type `T` by `@gestures T …` (default empty).
Use `get_document_gesture_bindings` to also collect inherited supertype bindings.
"""
get_document_gesture_bindings_own(::Type) = GestureBinding[]

const _GESTURE_CACHE = IdDict{Type,Vector{GestureBinding}}()

"""
    get_document_gesture_bindings(T::Type) -> Vector{GestureBinding}
    get_document_gesture_bindings(doc)     -> Vector{GestureBinding}

Every binding that applies to document type `T`: `T`'s own bindings, most
specific first, followed by each supertype's, walking up the chain. The result
is the reified table the help projection shows and the `read_document_gesture`
interpreter fires — one source of truth.
"""
function get_document_gesture_bindings(T::Type)
    cached = get(_GESTURE_CACHE, T, nothing)
    cached === nothing || return cached
    result = GestureBinding[]
    S = T
    while true
        # Kind-parameterized document types (`JsonArray{ReactiveCell{Any}}`) carry
        # their bindings on the bare stem `JsonArray` — the UnionAll the `@gestures`
        # method dispatches on (`::Type{JsonArray}`). The supertype walk goes
        # `JsonArray{…} → JsonDocument → …` and never visits that stem, so normalize
        # each concrete level to its UnionAll base before the registry lookup.
        base = S isa DataType ? S.name.wrapper : S
        append!(result, get_document_gesture_bindings_own(base))
        S === Any && break
        S = supertype(S)
    end
    _GESTURE_CACHE[T] = result
    return result
end
get_document_gesture_bindings(doc::Document) = get_document_gesture_bindings(typeof(doc))

"""
    get_instance_gesture_bindings(doc) -> Vector{GestureBinding}

Per-*instance* gesture bindings carried by `doc` itself, checked ahead of the
per-type table so an instance can add, override (by shadowing a same-pattern
default), or suppress behavior. Default empty, so any object that does not opt in
behaves exactly as before. Widgets override this to return their `gestures`
field; because the default is empty and untyped it also serves non-`Document`
values (e.g. a `WidgetTreeNode`) — see [`read_node_gesture`](@ref).
"""
get_instance_gesture_bindings(doc) = GestureBinding[]

# Shared firing loop: the first binding whose pattern `matches` and whose
# `applicable` precondition holds (for `doc` + `sel`) and whose `operation`
# returns non-`nothing` wins. A binding whose operation returns `nothing` is a
# finer event-dependent decline and is skipped so a later binding may still fire.
function _fire_gestures(bindings, doc, sel, event)
    for b in bindings
        if matches(b.pattern, event) && b.applicable(doc, sel)
            op = b.operation(doc, event)
            op === nothing || return op
        end
    end
    return nothing
end

"""
    read_document_gesture(doc, event) -> Operation | Nothing

Fire the first matching binding for `doc`, checking its per-instance
[`get_instance_gesture_bindings`](@ref) first and then its per-type [`get_document_gesture_bindings`](@ref)
table (walking the supertype chain), evaluated against the current selection.
Instance bindings therefore shadow same-pattern type defaults. This is the single
interpreter that backs `read_gesture` for every `@gestures`-declared type; an
object with neither instance nor type bindings yields `nothing`, exactly as the
old default.
"""
function read_document_gesture(doc, event)
    inst = get_instance_gesture_bindings(doc)
    type = get_document_gesture_bindings(typeof(doc))
    (isempty(inst) && isempty(type)) && return nothing
    sel = getfield(doc, :selection)[]
    bindings = isempty(inst) ? type : (isempty(type) ? inst : vcat(inst, type))
    return _fire_gestures(bindings, doc, sel, event)
end

"""
    read_node_gesture(node, event, selection) -> Operation | Nothing

The selection-agnostic sibling of [`read_document_gesture`](@ref) for values that
are *not* `Document`s and so carry no `selection` field of their own — notably a
`WidgetTreeNode`, whose identity is its path inside the enclosing tree. Fires
`node`'s [`get_instance_gesture_bindings`](@ref) against the explicitly supplied `selection`
(usually the enclosing document's).
"""
function read_node_gesture(node, event, selection)
    bindings = get_instance_gesture_bindings(node)
    isempty(bindings) && return nothing
    return _fire_gestures(bindings, node, selection, event)
end

# The projection-independent reader for any `@gestures`-declared document is the
# table interpreter. JSON, Syntax and Text are all reified onto it; a domain may
# still add a more-specific `read_gesture(::SomeDoc, evt)` that wins. Documents
# with no registered gestures get `nothing` (empty table), exactly as the old default.
read_gesture(doc::Document, event) = read_document_gesture(doc, event)

# ─────────────────────────────────────────────────────────────────────────
# Projection-owned gestures (Stage 2 seam) + collector defaults
# ─────────────────────────────────────────────────────────────────────────

"""
    get_projection_gesture_bindings(projection, iomap) -> Vector{GestureBinding}

Gestures owned by a *projection* rather than a document (focus, collapse glyph,
clipboard, …). Default empty; a projection overrides this to contribute its own
rows to the contextual collector. The combinator `collect_gesture_bindings` methods
(beside the `read_intent` combinators) gather these across the chain.
"""
get_projection_gesture_bindings(::Projection, iomap) = GestureBinding[]

"""
    read_projection_gesture(projection, iomap, event) -> Operation | Nothing

Fire the first reified `get_projection_gesture_bindings(projection, iomap)` binding whose
pattern `matches` the event and whose `applicable` precondition holds; a binding
whose `operation` returns `nothing` is skipped so a later one may still fire. The
projection-layer analogue of [`read_document_gesture`](@ref): a projection whose
reader delegates here (e.g. Clipboard) *fires* the very table `collect_gesture_bindings`
*shows*, so fire == show holds at the projection layer too.

The binding `operation`/`applicable` closures are built by `get_projection_gesture_bindings`
over `projection` and `iomap`, so they already capture what they need; the `doc`
and `selection` passed here are `iomap.input` and its selection (a binding may
ignore them and use its captured `iomap`).
"""
function read_projection_gesture(projection, iomap, event)
    bindings = get_projection_gesture_bindings(projection, iomap)
    isempty(bindings) && return nothing
    input = hasproperty(iomap, :input) ? iomap.input : nothing
    sel = (input !== nothing && hasfield(typeof(input), :selection)) ?
          getfield(input, :selection)[] : nothing
    for b in bindings
        if matches(b.pattern, event) && b.applicable(input, sel)
            op = b.operation(input, event)
            op === nothing || return op
        end
    end
    return nothing
end

"""
    collect_gesture_bindings(projection, recursion, iomap) -> Vector{GestureBinding}

Gather every gesture available at `iomap` — the data-driven generalization of
`read_intent`'s 4-arg routing: where the reader *matches* one gesture, this
*collects* them all. The leaf default is the projection's own
`get_projection_gesture_bindings` plus `get_document_gesture_bindings(iomap.input)`; compound projections
override to recurse in lockstep with their reader. Each combinator method lives
beside that combinator's `read_intent` (so coverage extends incrementally —
un-reified layers simply contribute nothing).
"""
function collect_gesture_bindings(p::Projection, recursion, iomap)
    result = GestureBinding[]
    append!(result, get_projection_gesture_bindings(p, iomap))
    input = hasproperty(iomap, :input) ? iomap.input : nothing
    if input isa Document
        # Per-instance bindings first (they shadow same-pattern type defaults in
        # the reader), then the per-type table — the same order `read_document_gesture`
        # fires, so the help window shows exactly what would fire.
        append!(result, get_instance_gesture_bindings(input))
        append!(result, get_document_gesture_bindings(typeof(input)))
    end
    return result
end

"""
    get_applicable_gesture_bindings(doc, bindings) -> Vector{GestureBinding}

The subset of `bindings` whose `applicable` precondition holds for `doc`'s
current selection — the rows the help projection shows un-greyed.
"""
function get_applicable_gesture_bindings(doc, bindings)
    sel = getfield(doc, :selection)[]
    GestureBinding[b for b in bindings if b.applicable(doc, sel)]
end

# ─────────────────────────────────────────────────────────────────────────
# Help-gesture recognition
#
# The gesture that summons the gesture-help window. Lisp uses Ctrl-H; here the
# unambiguous F1 ("help") is used, since Ctrl-? would need `Ctrl+Shift+/` handling.
# A gesture carries no intent (event-to-gesture.md), so there is no keymap to bind
# a `:help` intent — the summons is just whichever gesture this predicate matches.
# It could later be a key chord (event-to-gesture.md Phase 2 B landed `KeyChord`),
# but that needs a chord-table entry + a `KeyChordPattern`; F1 stays the v1.
# ─────────────────────────────────────────────────────────────────────────

"""
    is_help_gesture(event) -> Bool

True when `event` is the gesture that summons the gesture-help window (F1). A
content-level `GestureHelpProjection` decorator matches this and emits an
`OpenWindowOperation` whose content renders `collect_gesture_bindings` over the focused
pipeline; the help window closes itself.
"""
is_help_gesture(event) = event isa KeyDown && event.key === :f1

# ─────────────────────────────────────────────────────────────────────────
# @gestures macro
#
# Surface:
#
#     @gestures DocType begin
#         when(<precondition over doc, sel>)          # optional, block-level
#         PATTERN => "human description" => rhs        # description optional
#         when(PATTERN, guard) => "desc" => rhs        # per-rule event guard
#         ...
#     end
#
# The LHS PATTERN reuses the `@event_case` parser. The right side is parsed
# right-associatively: `PATTERN => "desc" => rhs` is `PATTERN => ("desc" => rhs)`.
# In `rhs`/the precondition, `doc` is the document and `sel` the selection;
# bound pattern variables (e.g. `c` in `KeyPress(c)`) are in scope in `rhs` and
# in the per-rule guard.
# ─────────────────────────────────────────────────────────────────────────

# Pattern-constructor expression + auto gesture label, from a parsed
# (typename, posargs, mods). Bound/wild fields become `nothing` (any); literals
# and interpolations become required values. `guard_ex` is a closure expr or
# `nothing`.
function _pattern_expr(tname::Symbol, posargs::Vector{EvPat},
                       mods::Union{Vector{Symbol},Nothing}, guard_ex)
    fields = _EVENT_TYPES[tname][2]
    # Map each declared positional field to its constraint expression.
    fieldval(i) = i <= length(posargs) ? _constraint_expr(posargs[i]) : :nothing
    modsex = mods === nothing ? :nothing : Expr(:vect, QuoteNode.(mods)...)
    if tname === :KeyPress
        :(KeyPressPattern($(fieldval(1)), $guard_ex,
                          _keypress_label($(fieldval(1)))))
    elseif tname === :KeyDown
        :(KeyDownPattern($(fieldval(1)), $modsex, $guard_ex))
    elseif tname === :KeyUp
        :(KeyUpPattern($(fieldval(1)), $modsex, $guard_ex))
    elseif tname === :MousePress
        :(MousePressPattern($(fieldval(1)), $modsex, $guard_ex))
    elseif tname === :MouseDown
        :(MouseDownPattern($(fieldval(1)), $modsex, $guard_ex))
    elseif tname === :MouseUp
        :(MouseUpPattern($(fieldval(1)), $modsex, $guard_ex))
    elseif tname === :MouseMove
        :(MouseMovePattern($modsex, $guard_ex))
    elseif tname === :MouseScroll
        :(MouseScrollPattern($modsex, $guard_ex))
    else
        error("@gestures: unsupported pattern type $tname")
    end
end

# Auto label for a KeyPress whose char constraint is `cexpr` (a Char or nothing).
_keypress_label(c::Char) = string(c)
_keypress_label(::Nothing) = "character"

# A field constraint: literal/interp → its value; wild/bind → nothing (any).
_constraint_expr(::EvWild) = :nothing
_constraint_expr(::EvBind) = :nothing
_constraint_expr(p::EvLit) = QuoteNode(p.value)
_constraint_expr(p::EvInterp) = esc(p.expr)

# Bind `let`-expressions for the positional fields named by EvBind, so `rhs`
# and the per-rule guard can read them off the event. Escaped names + escaped
# body keep hygiene consistent (same trick as `@event_case`).
function _bind_lets(tname::Symbol, posargs::Vector{EvPat}, evsym, body)
    fields = _EVENT_TYPES[tname][2]
    for i in length(posargs):-1:1
        p = posargs[i]
        if p isa EvBind
            body = :(let $(esc(p.name)) = $evsym.$(fields[i]); $body end)
        end
    end
    body
end

# Parse a `@gestures` / `@gesture_set` body into `(applicable_ex, items)`: the
# block precondition closure expression and the ordered list of table entries —
# each either a `GestureBinding(...)` expression or a `splice`d
# `Vector{GestureBinding}...` splat. `domain_str` tags every binding built here.
# Bindings reference a hygienic `_applicable` local that the caller binds to
# `applicable_ex`; both macros wrap the items in the same `let _applicable = …`.
function _parse_gesture_block(entries, domain_str)
    precondition_ex = nothing       # closure expr (doc, sel) -> Bool
    items = Any[]

    for e in entries
        e isa LineNumberNode && continue
        # Block-level precondition: a bare `when(expr)` call (one argument).
        if e isa Expr && e.head == :call && e.args[1] == :when && length(e.args) == 2
            precondition_ex = :(($(esc(:doc)), $(esc(:sel))) -> $(esc(e.args[2])))
            continue
        end
        # Splice a reusable `Vector{GestureBinding}` (e.g. a `@gesture_set`) inline,
        # preserving position — the cross-type sharing single inheritance can't do.
        if e isa Expr && e.head == :call && e.args[1] == :splice && length(e.args) == 2
            push!(items, :($(esc(e.args[2]))...))
            continue
        end
        # A rule: PATTERN => [ "desc" => ] rhs  (or when(PATTERN, guard) => …).
        (e isa Expr && e.head == :call && e.args[1] == :(=>)) ||
            error("@gestures: expected `PATTERN => rhs`, `splice(set)`, or `when(expr)`, got `$e`")
        tname, posargs, mods, cond, rhs = _parse_rule(e)
        tname === nothing && error("@gestures: `_` catch-all is not allowed")

        # Split an optional leading "description" out of the right side.
        desc, body = if rhs isa Expr && rhs.head == :call && rhs.args[1] == :(=>) &&
                        rhs.args[2] isa String
            (rhs.args[2], rhs.args[3])
        else
            (nothing, rhs)
        end

        evsym = gensym(:event)
        docsym = esc(:doc)

        # Per-rule event guard closure (from `when(PATTERN, cond)`).
        guard_ex = cond === nothing ? :nothing :
            :($evsym -> $(_bind_lets(tname, posargs, evsym, esc(cond))))

        pat_ex = _pattern_expr(tname, posargs, mods, guard_ex)

        # Operation closure: (doc, event) -> rhs, with bound fields in scope.
        op_ex = :(($docsym, $evsym) -> $(_bind_lets(tname, posargs, evsym, esc(body))))

        desc_ex = desc === nothing ? :(describe($pat_ex)) : desc

        push!(items, :(GestureBinding($pat_ex, $op_ex, _applicable, $desc_ex, $domain_str)))
    end

    applicable_ex = precondition_ex === nothing ?
        :((($(esc(:doc)), $(esc(:sel))) -> true)) : precondition_ex

    return (applicable_ex, items)
end

"""
    @gestures DocType begin … end

Declare the reified gesture table for document type `DocType`. Each entry is one
of:

  - `PATTERN => "description" => rhs` — a rule (description optional); `PATTERN`
    uses the `@event_case` surface, `rhs` builds the operation with `doc`, `event`
    and any bound pattern variables in scope.
  - `when(PATTERN, cond) => …` — a rule with a per-rule event guard.
  - `when(<expr over doc, sel>)` — an optional block-level `applicable`
    precondition (event-independent).
  - `splice(set)` — splice a reusable `Vector{GestureBinding}` (typically a
    [`@gesture_set`](@ref)) in at this position.

Bindings shared by a whole type family go on the common abstract supertype (e.g.
`@gestures JsonDocument`) and are inherited by every subtype via
[`get_document_gesture_bindings`](@ref); a set shared by *unrelated* types (no common
supertype) is a `@gesture_set` `splice`d into each.
"""
macro gestures(doctype, block)
    entries = block isa Expr && block.head == :block ? block.args : [block]
    applicable_ex, items = _parse_gesture_block(entries, _typename_string(doctype))

    # Emit a `get_document_gesture_bindings_own(::Type{DocType})` method holding the reified
    # table (built fresh per call; cached by `get_document_gesture_bindings`). A method, not a
    # mutable registry, so the bindings survive precompilation. The function name
    # is the module-qualified `GestureBindingModule.get_document_gesture_bindings_own` so the
    # method *extends* the kernel generic regardless of how the caller imported it
    # (a bare `function get_document_gesture_bindings_own` would be hygienically gensym'd into
    # a fresh local function instead of extending ours).
    quote
        function $(GestureBindingModule).get_document_gesture_bindings_own(::Type{$(esc(doctype))})
            _applicable = $applicable_ex
            GestureBinding[$(items...)]
        end
    end
end

"""
    @gesture_set name begin … end

Define a reusable, named `Vector{GestureBinding}` (a `const`) from the same body
grammar as [`@gestures`](@ref). `splice(name)` then includes it in any number of
`@gestures` blocks — the way to share a gesture group across document types that
have no common supertype (e.g. the same clipboard commands on JSON and XML). The
set carries its own `when(…)` precondition, independent of the blocks it lands in;
its `domain` tag is `name`. Spliced bindings are shared objects, not copies.
"""
macro gesture_set(name, block)
    name isa Symbol || error("@gesture_set: expected a name, got `$name`")
    entries = block isa Expr && block.head == :block ? block.args : [block]
    applicable_ex, items = _parse_gesture_block(entries, string(name))
    quote
        const $(esc(name)) = let _applicable = $applicable_ex
            GestureBinding[$(items...)]
        end
    end
end

# Best-effort domain tag from the doctype expression (the bare type name).
_typename_string(doctype) = doctype isa Symbol ? string(doctype) :
                            doctype isa Expr ? string(doctype) : "document"

end # module
