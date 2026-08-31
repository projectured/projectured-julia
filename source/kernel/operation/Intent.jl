"""
    IntentModule

The backward-flowing unit of the reader pipeline — the reader-side protocol data
types `Intent` and `ClaimedGesture`, the `CollectIntents` payload, and the
`CollectedIntentsOperation` that carries a collection home. They are concrete data
vehicles, not interfaces to implement; readers import them from here directly.

They sit in the operation layer because an `Intent`'s second half *is* an
operation, and because the binding layer above has to build one.
"""
module IntentModule

import ..OperationModule: Operation, reroot_operation

export Intent, ClaimedGesture, CollectIntents, CollectedIntentsOperation,
       labelled_intent, merge_collected_intents

"""
    Intent(gesture, operation = nothing, description = "", domain = "")

The backward-flowing unit of the reader pipeline — the symmetric dual of the
document that flows forward through the printer. It carries the same user change
in two coordinate frames:

- `gesture` — the originating input (a device event such as `MousePress`/`KeyDown`,
  or an `WindowInput` at the screen layer). **Invariant**: it is threaded
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

A reader returns an `Intent`: it either keeps `operation === nothing` (it had
nothing to say) or returns a fresh `Intent` with the gesture preserved and a real
operation swapped in (cf. Lisp's `clone-command`; the original names this
type `command`, and carries exactly these four fields).

**A reader that reroots an operation must preserve the labels.** Rerooting changes
where an operation points, never what it is called.
"""
struct Intent
    gesture::Any
    operation::Any
    description::String
    domain::String
end

Intent(gesture) = Intent(gesture, nothing, "", "")
Intent(gesture, operation) = Intent(gesture, operation, "", "")

"""
    labelled_intent(intent, description, domain) -> Intent

`intent` with its labels replaced. The one place labels are attached, so a reader
that builds an operation does not have to remember the field order.
"""
labelled_intent(intent::Intent, description::AbstractString, domain::AbstractString) =
    Intent(intent.gesture, intent.operation, String(description), String(domain))

"""
    ClaimedGesture(gesture, operation)

A reader **payload**: `gesture`, offered to a projection that has already been
handed an `operation` an *output* layer produced for it.

Reading runs last-to-first, so by the time a change reaches an input-domain
projection the output layers have had their say — a printable key they understood is
already a character edit. That is the good default: it is what makes JSON's `,` a
literal comma inside a string without a guard, and why a structural gesture never has
to reconstruct what the text layer would have done in order to decline.

A few keys cannot be text in their own context and must win anyway (XML's `<` inside
a tag name inserts a child element). The generic reader bridge offers this payload to
such a projection *before* translating the claimed operation; only `override`
bindings fire for it (see `fire_gesture_bindings`), so it is inert for every ordinary
gesture. A projection with nothing to say returns `nothing` and the claimed operation
is translated exactly as before.

It is a payload rather than a fifth generic function on purpose: descent rides
`read_intent`, which already dispatches on what the payload *is* — a raw event, an
`Operation`, or (now) a claimed event. The recursion contract forbids a new function
to descend with (see `ProjectionApiModule`).
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
the input vocabulary. `ClaimedGesture` is the precedent.

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

end # module
