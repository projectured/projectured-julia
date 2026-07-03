"""
    IntentModule

The backward-flowing unit of the reader pipeline — the reader-side protocol data
type `Intent`. It is a concrete data vehicle, not an interface to implement, so it
lives in `common/` rather than the pure-interface `api/` tier; readers import
`Intent` from here directly.
"""
module IntentModule

export Intent

"""
    Intent(gesture, operation = nothing)

The backward-flowing unit of the reader pipeline — the symmetric dual of the
document that flows forward through the printer. It carries the same user change
in two coordinate frames:

- `gesture` — the originating input (a device event such as `MousePress`/`KeyDown`,
  or an `EventEnvelope` at the screen layer). **Invariant**: it is threaded
  unchanged through the whole reader chain, so any reader can inspect *what the
  user did*, not just what it currently means.
- `operation` — the change expressed in the current projection's input domain.
  Starts as `nothing` (a "nothing-change") and is filled in / re-mapped by the
  readers as the change travels one domain inward at each step.

A reader returns a `Intent`: it either keeps `operation === nothing` (it had
nothing to say) or returns a fresh `Intent` with the gesture preserved and a real
operation swapped in (cf. Lisp's `clone-command`; the original names this
type `command`).
"""
struct Intent
    gesture::Any
    operation::Any
end

Intent(gesture) = Intent(gesture, nothing)

end # module
