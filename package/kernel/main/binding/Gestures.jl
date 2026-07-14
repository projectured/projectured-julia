# Fragment of `GestureBindingModule` — the `@gestures` / `@gesture_set` authoring
# DSL. The left-hand side of a rule is the event pattern syntax, parsed by
# `EventPatternModule`'s exported parser (`parse_event_rule`, `event_pattern_expr`,
# `event_field_bindings`) rather than re-implemented here.
#
# Surface:
#
#     @gestures DocumentType begin
#         when(<precondition over doc, sel>)          # optional, block-level
#         PATTERN => "human description" => rhs        # description optional
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
# own context — XML's `<` inside a tag name. Without it a key the text layer absorbed
# never reaches the document at all, which is what lets an ordinary structural gesture
# skip the "am I inside a string?" guard entirely.

# Parse a `@gestures` / `@gesture_set` body into `(applicable_expr, items)`: the
# block precondition closure expression and the ordered list of table entries — each
# either a `GestureBinding(...)` expression or a `splice`d `Vector{GestureBinding}`
# splat. `domain` tags every binding built here. Bindings reference a hygienic
# `_applicable` local that the caller binds to `applicable_expr`; both macros wrap
# the items in the same `let _applicable = …`.
function _parse_gesture_block(entries, domain::String)
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
            override = true
            e = Expr(:call, :(=>), lhs.args[2], e.args[3])
        end
        rule = parse_event_rule(e)
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
            :($event -> $(event_field_bindings(rule, event, esc(rule.guard))))

        pattern = event_pattern_expr(rule, guard)

        # Operation closure: (doc, event) -> rhs, with bound fields in scope.
        operation = :(($document, $event) -> $(event_field_bindings(rule, event, esc(body))))

        description_expr = description === nothing ? :(describe($pattern)) : description

        push!(items, :(GestureBinding($pattern, $operation, _applicable,
                                      $description_expr, $domain, $override)))
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
  - `when(PATTERN, cond) => …` — a rule with a per-rule event guard.
  - `override(PATTERN) => …` — a rule that claims its key even when an output layer
    already turned it into an operation (see [`GestureBinding`](@ref)). Without it, a
    printable key the text layer absorbed never reaches the document — so an ordinary
    structural rule needs no guard against firing mid-text.
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
    applicable, items = _parse_gesture_block(entries, _type_name(document_type))

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
    applicable, items = _parse_gesture_block(entries, string(name))
    quote
        const $(esc(name)) = let _applicable = $applicable
            GestureBinding[$(items...)]
        end
    end
end

# Best-effort domain tag from the document-type expression (the bare type name).
_type_name(document_type) = document_type isa Symbol ? string(document_type) :
                            document_type isa Expr ? string(document_type) : "document"
