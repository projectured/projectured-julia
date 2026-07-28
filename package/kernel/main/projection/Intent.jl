"""
    IntentModule

The backward-flowing unit of the reader pipeline — the reader-side protocol data
types `Intent` and `ClaimedGesture`. They are concrete data vehicles, not interfaces
to implement — they live beside the interface stubs at the head of the projection
layer, and readers import them from here directly.
"""
module IntentModule

export Intent, ClaimedGesture

"""
    Intent(gesture, operation = nothing)

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

A reader returns an `Intent`: it either keeps `operation === nothing` (it had
nothing to say) or returns a fresh `Intent` with the gesture preserved and a real
operation swapped in (cf. Lisp's `clone-command`; the original names this
type `command`).
"""
struct Intent
    gesture::Any
    operation::Any
end

Intent(gesture) = Intent(gesture, nothing)

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

end # module
