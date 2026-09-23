# Fragment of `GestureBindingModule` — `GestureBinding`, one rule pairing a
# gesture with what it produces, and the table a document or a projection
# answers with.

struct GestureBinding
    pattern::Union{EventPattern,Nothing}
    operation::Function
    applicable::Function
    description::String
    domain::String
    override::Bool
    name::Union{String,Nothing}
end

"""
    GestureBinding(pattern, operation; applicable, description, domain, name = nothing)

One rule: `pattern` is the gesture it answers and `operation` is what it makes of
it. The rest says when the rule stands and how it is shown.

`applicable(document, selection)` answers whether the rule stands where the
selection is, and the default is a rule that always stands. `description` is the
line the gesture help draws, `domain` is the vocabulary it belongs to, and `name`
is what a command palette calls it. `override = true` takes a key from a layer
below, which is what `override(...)` in a `@gestures` table writes.
"""
GestureBinding(pattern, operation; applicable = (document, selection) -> true,
               description::AbstractString, domain::AbstractString,
               override::Bool = false, name = nothing) =
    GestureBinding(pattern, operation, applicable, String(description), String(domain),
                   override, name)

# ─────────────────────────────────────────────────────────────────────────
# Registry (own bindings per type) + supertype inheritance
#
# Own bindings are held in `get_document_gesture_bindings_own(::Type{T})` *methods*
# (emitted by `@gestures`), not a mutable table, so they persist across
# precompilation — mutating a Dict at a module's load time would be lost.
# `get_document_gesture_bindings` walks the supertype chain over those methods.
# ─────────────────────────────────────────────────────────────────────────

"""
    get_document_gesture_bindings_own(::Type{T}) -> Vector{GestureBinding}

The bindings declared *directly* on type `T` by `@gestures T …` (default empty). Use
[`get_document_gesture_bindings`](@ref) to also collect inherited supertype bindings.
"""
get_document_gesture_bindings_own(::Type) = GestureBinding[]

"""
    get_document_gesture_bindings(T::Type)  -> Vector{GestureBinding}
    get_document_gesture_bindings(document) -> Vector{GestureBinding}

Every binding that applies to document type `T`: `T`'s own bindings, most specific
first, followed by each supertype's, walking up the chain. The result is the reified
table the [`read_bound_gesture`](@ref) interpreter fires and an inspector shows —
one source of truth.

The walk is recomputed per call rather than memoised: a process-wide cache keyed by
type is exactly the kind of module-level mutable state that ties independent
editors together (PAR-NO-PROJECTION-GLOBALS, PAR-PER-EDITOR-STATE), and appending a
handful of vectors costs nothing next to the event that provoked it.
"""
function get_document_gesture_bindings(T::Type)
    result = GestureBinding[]
    S = T
    while true
        # Kind-parameterized document types carry their bindings on the bare stem —
        # the UnionAll the `@gestures` method dispatches on. The supertype walk never
        # visits that stem, so normalize each concrete level to its UnionAll base
        # before the registry lookup.
        base = S isa DataType ? S.name.wrapper : S
        append!(result, get_document_gesture_bindings_own(base))
        S === Any && break
        S = supertype(S)
    end
    return result
end
get_document_gesture_bindings(document::Document) =
    get_document_gesture_bindings(typeof(document))

"""
    get_instance_gesture_bindings(document) -> Vector{GestureBinding}

Per-*instance* gesture bindings carried by `document` itself, checked ahead of the
per-type table so an instance can add, override (by shadowing a same-pattern
default), or suppress behavior. Default empty, so any object that does not opt in
behaves as if it had none. Because the default is empty and untyped it also serves
values that are not `Document`s — pass such a target's selection to
[`read_bound_gesture`](@ref) explicitly.
"""
get_instance_gesture_bindings(document) = GestureBinding[]

"""
    fire_gesture_bindings(bindings, target, event; selection, claimed = nothing)
        -> Operation | Nothing

The firing loop: the first binding whose pattern matches the event, whose
`applicable` precondition holds for `target` + `selection`, and whose `operation`
returns non-`nothing`, wins. A binding whose operation returns `nothing` is a finer
event-dependent decline and is skipped, so a later binding may still fire.

A binding with no pattern is skipped: it has no gesture, so no event fires it. Run
it with [`fire_named_gesture_binding`](@ref).

`claimed` is the operation an *output* layer has already produced for this event, or
`nothing` when the event is unclaimed. A claimed event only fires bindings marked
`override`: the reader runs last-to-first, so anything the output layers understood
they have already done, and a document gesture that is not an explicit override has
nothing to add. This is why a structural gesture needs no guard against firing
mid-text — a key that could be text never arrives unclaimed.

This is the one place a table of bindings becomes an operation. Anything holding
bindings — a document, an instance, a projection — fires them through here rather
than walking them itself, so *what fires* cannot drift from what a listing shows.
"""
function fire_gesture_bindings(bindings, target, event; selection, claimed = nothing)
    # Asked what is available rather than for one thing to happen: answer with all
    # of them instead of the first match. Same table, same preconditions, same
    # operation closures — so what is listed cannot drift from what fires.
    event isa CollectIntents &&
        return collect_binding_intents(bindings, target, selection)
    for binding in bindings
        binding.pattern === nothing && continue
        claimed === nothing || binding.override || continue
        if matches_event_pattern(binding.pattern, event) && binding.applicable(target, selection)
            operation = binding.operation(target, event)
            operation === nothing || return operation
        end
    end
    return nothing
end

"""
    fire_named_gesture_binding(bindings, target, name; selection) -> Operation | Nothing

Run the first binding of `bindings` called `name`, whose `applicable`
precondition holds for `target` + `selection`, and whose `operation` returns
non-`nothing`. The counterpart of [`fire_gesture_bindings`](@ref): where that one
selects a binding by the event that fires it, this one selects it by the name a
user types.

The operation closure gets `nothing` for the event. A named binding never reads
the event, because `@gestures` withholds the name from a rule that binds a
pattern variable.

`claimed` has no counterpart here. A name comes from a user who picked a command
from a list, so no output layer can have taken it first.
"""
function fire_named_gesture_binding(bindings, target, name::AbstractString; selection)
    for binding in bindings
        binding.name == name || continue
        binding.applicable(target, selection) || continue
        operation = binding.operation(target, nothing)
        operation === nothing || return operation
    end
    return nothing
end

"""
    collect_binding_intents(bindings, target, selection) -> CollectedIntentsOperation

One `Intent` per binding in `bindings`, each carrying the operation that binding
would produce right now, expressed against `target`.

The counterpart of [`fire_gesture_bindings`](@ref) for the `CollectIntents`
payload: where firing stops at the first match, this builds them all. A binding
whose precondition fails, or whose operation declines, still yields an `Intent` —
with `operation === nothing`, which is the greyed row a listing shows. That is the
one deliberate difference from the Lisp, which drops what cannot fire.

The operation closure gets `nothing` for the event, so a binding that *reads* the
event yields an `Intent` with no operation: it has no meaning without the keystroke
that carries its argument. `@gestures` marks exactly those by withholding the
`name`. Such a binding still earns its row — a listing should say the key exists —
it simply cannot be run from a list.
"""
function collect_binding_intents(bindings, target, selection)
    intents = Intent[]
    for binding in bindings
        runnable = binding.name !== nothing
        operation = (runnable && binding.applicable(target, selection)) ?
                    binding.operation(target, nothing) : nothing
        push!(intents, Intent(binding.pattern, operation, binding.description, binding.domain))
    end
    CollectedIntentsOperation(intents)
end

"""
    read_bound_gesture(target, event; claimed = nothing) -> Operation | Nothing
    read_bound_gesture(target, event, selection; claimed = nothing) -> Operation | Nothing

Fire the first matching binding for `target`, checking its per-instance
[`get_instance_gesture_bindings`](@ref) ahead of its per-type
[`get_document_gesture_bindings`](@ref) table (which walks the supertype chain), so
an instance can add to, shadow, or suppress the type's defaults.

`selection` defaults to `target`'s own — pass it explicitly for a target that has
none of its own, such as a node whose identity is its path inside an enclosing tree
(then it is usually the enclosing document's). A target with neither instance nor
type bindings yields `nothing`. `claimed` restricts firing to `override` bindings —
see [`fire_gesture_bindings`](@ref).
"""
function read_bound_gesture(target, event, selection; claimed = nothing)
    bindings = _gesture_bindings(target)
    isempty(bindings) && return nothing
    return fire_gesture_bindings(bindings, target, event; selection, claimed)
end

function read_bound_gesture(target, event; claimed = nothing)
    bindings = _gesture_bindings(target)
    # Read the selection only once a binding could fire: reading a cell to answer
    # "no bindings" would register a dependency on it for nothing.
    isempty(bindings) && return nothing
    return fire_gesture_bindings(bindings, target, event;
                                 selection = getfield(target, :selection)[], claimed)
end

# The instance's own bindings ahead of its type's, so an instance shadows a
# same-pattern default.
function _gesture_bindings(target)
    instance = get_instance_gesture_bindings(target)
    type = get_document_gesture_bindings(typeof(target))
    isempty(instance) ? type : (isempty(type) ? instance : vcat(instance, type))
end

# The projection-independent reader for any `@gestures`-declared document is the
# table interpreter. Documents with no registered gestures get `nothing`. `claimed`
# (an operation an output layer already produced for this event) restricts firing to
# `override` bindings — see `fire_gesture_bindings`.
read_gesture(document::Document, event; claimed = nothing) =
    read_bound_gesture(document, event; claimed)

"""
    get_applicable_gesture_bindings(document, bindings) -> Vector{GestureBinding}

The subset of `bindings` whose `applicable` precondition holds for `document`'s
current selection — the ones that would fire in the state the document is in.
"""
function get_applicable_gesture_bindings(document, bindings)
    selection = getfield(document, :selection)[]
    GestureBinding[b for b in bindings if b.applicable(document, selection)]
end
