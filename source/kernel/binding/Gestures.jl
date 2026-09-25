# Fragment of `GestureBindingModule` — the `@gestures` / `@gesture_set` authoring
# DSL. The left-hand side of a rule is the event pattern syntax, parsed by
# `EventModule`'s exported parser (`parse_event_pattern_rule`, `build_event_pattern_expr`,
# `build_event_field_bindings`) rather than re-implemented here.
#
# Surface:
#
#     @gestures DocumentType begin
#         when(<precondition over doc, sel>)          # optional, block-level
#         PATTERN => "human description" => rhs        # description optional
#         nothing => "human description" => rhs        # no gesture: run it by name
#         when(PATTERN, guard) => "desc" => rhs        # per-rule event guard
#         override(PATTERN) => "desc" => rhs           # claims a key the output layers took
#         ...
#     end
#
# The right side is parsed right-associatively: `PATTERN => "desc" => rhs` is
# `PATTERN => ("desc" => rhs)`. In `rhs` and in the precondition, `doc` is the
# document and `sel` the selection; bound pattern variables (e.g. `c` in
# `KeyPress(c)`) are in scope in `rhs` and in the per-rule guard.
#
# `override(…)` wraps a pattern (composing with `when(PATTERN, guard)` inside it) and
# sets `GestureBinding.override`: the binding fires even when an output layer already
# turned the key into an operation. Reserve it for a key that cannot be text in its
# own context — XML's `<` inside a tag name. Without it, a key that the text layer
# turned into a text edit reaches the document only where no stage can carry that edit,
# such as a `,` on a delimiter or in a number. Inside a string the edit is carried, so
# an ordinary structural gesture skips the "am I inside a string?" guard entirely.

# Is this pattern slot the absence of a gesture? The parser hands `nothing` over as
# the symbol it was written as; a spliced value arrives as `nothing` itself.
_is_no_pattern(ex) = ex === :nothing || ex === nothing

# Build the `GestureBinding(...)` expression for a command rule — a rule whose
# pattern slot is `nothing`. `rhs` is everything right of the `=>`, and it must be
# `"description" => body`: the description is mandatory here, because it is the name
# the user types and there is no pattern to derive a rendering from. The operation
# closure still takes an event so every binding fires through one loop, but the
# event is unused — a command rule binds no pattern variable.
function _command_binding_expr(rhs, domain::String)
    (rhs isa Expr && rhs.head == :call && rhs.args[1] == :(=>) && rhs.args[2] isa String) ||
        error("@gestures: a `nothing` rule needs a description — write `nothing => \"what it does\" => rhs`, got `$rhs`")
    description = rhs.args[2]
    body = rhs.args[3]
    operation = :(($(esc(:doc)), $(gensym(:event))) -> $(esc(body)))
    :(GestureBinding(nothing, $operation; applicable = _applicable,
                     description = $description, domain = $domain, name = $description))
end

# Parse a `@gestures` / `@gesture_set` body into `(applicable_expr, items)`: the
# block precondition closure expression and the ordered list of table entries — each
# either a `GestureBinding(...)` expression or a `splice`d `Vector{GestureBinding}`
# splat. `domain` tags every binding built here. Bindings reference a hygienic
# `_applicable` local that the caller binds to `applicable_expr`; both macros wrap
# the items in the same `let _applicable = …`.
function _parse_gesture_block(entries, domain::String; scope::Module)
    precondition = nothing          # closure expr (doc, sel) -> Bool
    items = Any[]

    for e in entries
        e isa LineNumberNode && continue
        # Block-level precondition: a bare `when(expr)` call (one argument).
        if e isa Expr && e.head == :call && e.args[1] == :when && length(e.args) == 2
            precondition = :(($(esc(:doc)), $(esc(:sel))) -> $(esc(e.args[2])))
            continue
        end
        # Splice a reusable `Vector{GestureBinding}` (e.g. a `@gesture_set`) inline,
        # preserving position — the cross-type sharing single inheritance can't do.
        if e isa Expr && e.head == :call && e.args[1] == :splice && length(e.args) == 2
            push!(items, :($(esc(e.args[2]))...))
            continue
        end
        # A rule: PATTERN => [ "desc" => ] rhs  (or when(PATTERN, guard) => …), with the
        # pattern optionally wrapped in `override(…)`. Unwrap that first so the event
        # parser sees the plain rule.
        (e isa Expr && e.head == :call && e.args[1] == :(=>)) ||
            error("@gestures: expected `PATTERN => rhs`, `splice(set)`, or `when(expr)`, got `$e`")
        override = false
        lhs = e.args[2]
        if lhs isa Expr && lhs.head == :call && lhs.args[1] == :override
            length(lhs.args) == 2 ||
                error("@gestures: `override` wraps exactly one pattern, got `$lhs`")
            _is_no_pattern(lhs.args[2]) &&
                error("@gestures: `override(nothing)` is not a rule — override claims a key, and a `nothing` rule has none")
            override = true
            e = Expr(:call, :(=>), lhs.args[2], e.args[3])
        end
        # A command rule: `nothing => "description" => rhs`. The pattern slot holds
        # what the field holds, so the absence of a gesture needs no second surface.
        # The event parser never sees it — it reads a bare symbol as an event type.
        if _is_no_pattern(lhs)
            push!(items, _command_binding_expr(e.args[3], domain))
            continue
        end
        rule = parse_event_pattern_rule(e; scope = scope)
        rule.type === nothing && error("@gestures: `_` catch-all is not allowed")

        # Split an optional leading "description" out of the right side.
        description, body = if rule.result isa Expr && rule.result.head == :call &&
                               rule.result.args[1] == :(=>) && rule.result.args[2] isa String
            (rule.result.args[2], rule.result.args[3])
        else
            (nothing, rule.result)
        end

        event = gensym(:event)
        document = esc(:doc)

        # Per-rule event guard closure (from `when(PATTERN, cond)`).
        guard = rule.guard === nothing ? :nothing :
            :($event -> $(build_event_field_bindings(rule, event, esc(rule.guard))))

        pattern = build_event_pattern_expr(rule, guard)

        # Operation closure: (doc, event) -> rhs, with bound fields in scope.
        # `build_event_field_bindings` returns the body untouched when the rule binds
        # no pattern variable, and wraps it in a `let` when it does. Identity of the
        # result is therefore the answer to "does this rhs read the event?", asked
        # through the parser's own exported form rather than its field types.
        escaped_body = esc(body)
        bound_body = build_event_field_bindings(rule, event, escaped_body)
        reads_event = bound_body !== escaped_body
        operation = :(($document, $event) -> $bound_body)

        description_expr = description === nothing ? :(describe_event_pattern($pattern)) : description

        # The name a user types to run the rule from a command list. A rule with no
        # authored description has no name to type: its description is the gesture
        # rendering ("Ctrl+K"). A rule that reads the event has no name either,
        # because a name carries no event.
        name_expr = (description === nothing || reads_event) ? :nothing : description

        push!(items, :(GestureBinding($pattern, $operation; applicable = _applicable,
                                      description = $description_expr, domain = $domain,
                                      override = $override, name = $name_expr)))
    end

    applicable = precondition === nothing ?
        :((($(esc(:doc)), $(esc(:sel))) -> true)) : precondition

    return (applicable, items)
end

"""
    @gestures DocumentType begin … end

Declare the reified gesture table for document type `DocumentType`. Each entry is one
of:

  - `PATTERN => "description" => rhs` — a rule (description optional); `PATTERN` uses
    the event pattern syntax, `rhs` builds the operation with `doc`, `event` and any
    bound pattern variables in scope.
  - `nothing => "description" => rhs` — a rule with **no gesture**. No key and no
    click reaches it. A user runs it by its description, which is also its name, so
    the description is mandatory here. `override(nothing)` is an error, and the rhs
    reads `doc` and `sel` only. This is how an operation reaches a user without
    spending a key on it, from the one table that already says what a document can
    do.
  - `when(PATTERN, cond) => …` — a rule with a per-rule event guard.
  - `override(PATTERN) => …` — a rule that claims its key even when an output layer
    already turned it into an operation (see [`GestureBinding`](@ref)). Without it, a
    printable key that the text layer turned into a text edit reaches the document only
    where no stage can carry that edit, such as a `,` on a delimiter or in a number.
    Inside a string the edit is carried, so an ordinary structural rule needs no guard
    against firing mid-text.
  - `when(<expr over doc, sel>)` — an optional block-level `applicable` precondition
    (event-independent).
  - `splice(set)` — splice a reusable `Vector{GestureBinding}` (typically a
    [`@gesture_set`](@ref)) in at this position.

Bindings shared by a whole type family go on the common abstract supertype and are
inherited by every subtype via [`get_document_gesture_bindings`](@ref); a set shared
by *unrelated* types (no common supertype) is a `@gesture_set` `splice`d into each.
"""
macro gestures(document_type, block)
    entries = block isa Expr && block.head == :block ? block.args : [block]
    applicable, items = _parse_gesture_block(entries, _type_name(document_type);
                                             scope = __module__)

    # Emit a `get_document_gesture_bindings_own(::Type{DocumentType})` method holding
    # the reified table (built fresh per call; cached by
    # `get_document_gesture_bindings`). A method, not a mutable registry, so the
    # bindings survive precompilation. The function name is module-qualified so the
    # method *extends* this module's generic regardless of how the caller imported it
    # (a bare `function get_document_gesture_bindings_own` would be hygienically
    # gensym'd into a fresh local function instead of extending ours).
    quote
        function $(@__MODULE__).get_document_gesture_bindings_own(::Type{$(esc(document_type))})
            _applicable = $applicable
            GestureBinding[$(items...)]
        end
    end
end

"""
    @gesture_set name begin … end

Define a reusable, named `Vector{GestureBinding}` (a `const`) from the same body
grammar as [`@gestures`](@ref). `splice(name)` then includes it in any number of
`@gestures` blocks — the way to share a gesture group across document types that have
no common supertype (e.g. the same clipboard commands on two unrelated domains). The
set carries its own `when(…)` precondition, independent of the blocks it lands in;
its `domain` tag is `name`. Spliced bindings are shared objects, not copies.
"""
macro gesture_set(name, block)
    name isa Symbol || error("@gesture_set: expected a name, got `$name`")
    entries = block isa Expr && block.head == :block ? block.args : [block]
    applicable, items = _parse_gesture_block(entries, string(name); scope = __module__)
    quote
        const $(esc(name)) = let _applicable = $applicable
            GestureBinding[$(items...)]
        end
    end
end

# Best-effort domain tag from the document-type expression (the bare type name).
_type_name(document_type) = document_type isa Symbol ? string(document_type) :
                            document_type isa Expr ? string(document_type) : "document"
