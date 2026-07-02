"""
    ChangeModule

The backward-flowing unit of the reader pipeline — the reader-side protocol data
type (`Change`) plus its `as_change` shim. It is a concrete data vehicle, not an
interface to implement, so it lives in `common/` rather than the pure-interface
`api/` tier; readers import `Change`/`as_change` from here directly.
"""
module ChangeModule

export Change, as_change

"""
    Change(gesture, operation = nothing)

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

A reader returns a `Change`: it either keeps `operation === nothing` (it had
nothing to say) or returns a fresh `Change` with the gesture preserved and a real
operation swapped in (cf. Lisp's `clone-command`).
"""
struct Change
    gesture::Any
    operation::Any
end

Change(gesture) = Change(gesture, nothing)

"""
    as_change(payload) -> Change

Wrap a legacy reader payload (a raw gesture/event, an `EventEnvelope`, or a
backward-threaded operation) into a `Change`. Used by the 3-argument
compatibility shims so existing 3-arg `projection_read(projection, iomap, x)`
call sites keep working against the 4-arg `Change` interface. The payload goes in
the gesture slot; the generic reader bridge falls back to the gesture slot
whenever the operation slot is empty, so an operation passed this way is still
applied correctly.
"""
as_change(payload) = payload isa Change ? payload : Change(payload, nothing)

end # module
