# Fragment of `IntentModule` — the carrier, its two reader payloads and their collection.

"""
    Intent(gesture, operation = nothing, description = "", domain = "")
    Intent(gesture, operation, description, domain, route)

The backward-flowing unit of the reader pipeline — the symmetric dual of the
document that flows forward through the printer. It carries the same user change
in two coordinate frames:

- `gesture` — the originating input: a device event such as `KeyDown`, a gesture
  such as `MouseClick`, or a `WindowInput`, the event of the event layer that holds
  the id of its window. **Invariant**: it is threaded
  unchanged through the whole reader chain, so any reader can inspect *what the
  user did*, not just what it currently means.
- `operation` — the change expressed in the current projection's input domain.
  Starts as `nothing` (a "nothing-change") and is filled in / re-mapped by the
  readers as the change travels one domain inward at each step.

- `description` — what this change does, in words, for a human reading a list of
  what is available. Empty when the reader that produced it says nothing.
- `domain` — the tag that groups it under a heading: the document type name for a
  document's own rule, the slice or projection name for a projection's own.
  Empty groups under one fallback heading, which is how an unlabelled reader makes
  itself visible.
- `route` — `nothing` for a change that a gesture starts at the pointer or at the
  selection. For an operation that code already made, the path from the current
  reader's input to the place the operation is relative to; the gesture is then
  `nothing`. For a gesture that is for one part, such as a leave for the part
  that the pointer left, the path to that part; the operation is then `nothing`,
  and no reader finds the part by the position of the gesture. A reader that
  passes the change to a child gives it the route that remains below that child
  ([`follow_intent_route`](@ref)); a container that holds its children does so
  by default ([`read_routed_child`](@ref)). Where the route is empty, the child
  is the place: its parent takes an operation as the child's answer, and the
  child reads a gesture. A reader that holds no children reads the change with
  the rest of the route as the part. On the way up, an answer carries no route.

A reader returns an `Intent`: it either keeps `operation === nothing` (it had
nothing to say) or returns a fresh `Intent` with the gesture preserved and a real
operation swapped in (cf. Lisp's `clone-command`; the original names this
type `command`).

**A reader that reroots an operation must preserve the labels.** Rerooting changes
where an operation points, never what it is called.
"""
struct Intent
    gesture::Any
    operation::Any
    description::String
    domain::String
    route::Union{Nothing,Reference}
end

Intent(gesture) = Intent(gesture, nothing, "", "", nothing)
Intent(gesture, operation) = Intent(gesture, operation, "", "", nothing)
# @positional: the fields of the carrier in their order, as its own constructor
# takes them, for a change that has no route.
Intent(gesture, operation, description::AbstractString, domain::AbstractString) =
    Intent(gesture, operation, String(description), String(domain), nothing)

"""
    follow_intent_route(change, steps...) -> Intent | Nothing

`change` with the route that remains after `steps`: what a reader gives the child
that `steps` reach from its input. `nothing` when the route of `change` does not
start with `steps`, so that child is not on the way to the place.
"""
function follow_intent_route(change::Intent, steps::ReferenceStep...)
    route = change.route
    for step in steps
        route isa ConcreteReference && get_reference_head(route) == step || return nothing
        route = get_reference_tail(route)
    end
    Intent(change.gesture, change.operation, change.description, change.domain, route)
end

"""
    ClaimedGesture(gesture, operation)

A reader **payload**: `gesture`, offered to a projection that has already been
handed an `operation` that an *output* stage produced for it.

Reading runs last-to-first, so by the time a change reaches an input-domain
projection the output stages have had their say: a printable key that a text stage
understood is already a character edit. That is the good default. A key that is
text inside a string needs no guard, and a structural gesture never has to
reconstruct what the text stage would have done in order to decline.

A few keys can not be text in their own context and must win anyway, such as a key
that inserts a child element inside a tag name. A reader offers this payload to such
a projection *before* it translates the claimed operation. A projection that answers
it acts only for a gesture that must win over the claimed operation, so the payload
is inert for every ordinary gesture. A projection with nothing to say returns
`nothing`, and the claimed operation is translated as it is with no offer.

It is a payload rather than a fifth generic function on purpose: descent rides
`read_intent`, which already dispatches on what the payload *is* — a raw event, an
`Operation`, or a claimed event. The recursion contract forbids a new function to
descend with.
"""
struct ClaimedGesture
    gesture::Any
    operation::Any
end

"""
    CollectIntents()

A reader **payload** asking for everything that is available rather than for one
thing to happen. A reader that receives it does not dispatch: it answers with a
[`CollectedIntentsOperation`](@ref) holding one `Intent` per rule it knows, each
carrying that rule's built operation.

It is a payload rather than an event because no device reports it and no pattern
matches it — `Intent.gesture` is untyped, so a reader payload needs no place in
the input vocabulary.

A reader that does not answer it declines, exactly as it declines an unknown
event. The failure mode is a missing row, never an error.
"""
struct CollectIntents end

"""
    CollectedIntentsOperation(intents)

The answer to [`CollectIntents`](@ref): every `Intent` available at the point the
question was asked.

Applying it does nothing. It is a **carrier**, and the reason it is an `Operation`
at all is so it travels the ordinary reader path home — every container that
reroots an operation reroots the operations inside this one, so the collection
that arrives at the top is already expressed in the top document's vocabulary. A
caller picks one and evaluates it; there is nothing left to look up.

`CompoundOperation` is the model. Every seam that maps a `CompoundOperation`
elementwise must map this one the same way.
"""
struct CollectedIntentsOperation <: Operation
    intents::Vector{Intent}
end

CollectedIntentsOperation() = CollectedIntentsOperation(Intent[])

"""
    merge_collected_intents(a, b) -> CollectedIntentsOperation

Both collections, `a` first. The reader equivalent of Lisp's `merge-commands`:
where a reader routing one gesture takes the first answer, a reader answering
`CollectIntents` takes every answer.
"""
merge_collected_intents(a::CollectedIntentsOperation, b::CollectedIntentsOperation) =
    CollectedIntentsOperation(vcat(a.intents, b.intents))
merge_collected_intents(a::CollectedIntentsOperation, ::Nothing) = a
merge_collected_intents(::Nothing, b::CollectedIntentsOperation) = b
merge_collected_intents(::Nothing, ::Nothing) = nothing

# Reroot every carried operation, exactly as `CompoundOperation` reroots every
# member. This is what makes a collection usable at the top of a chain: the
# operations arrive already rooted where the caller can apply them. The labels are
# untouched — rerooting changes where an operation points, not what it is called.
reroot_operation(op::CollectedIntentsOperation, steps::Tuple) =
    CollectedIntentsOperation([Intent(i.gesture, reroot_operation(i.operation, steps),
                                      i.description, i.domain)
                               for i in op.intents])

# A carrier changes no document, so its way back is to do nothing.
make_inverse_operation(document, ::CollectedIntentsOperation) = DoNothingOperation()
