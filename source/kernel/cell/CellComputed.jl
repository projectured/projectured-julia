# Fragment of `CellModule` — the computed marker. Included before the cell kinds:
# the reactive kind's constructor dispatches on it.

"""
    Computed(thunk::Function)

Marks `thunk` as a cell's **computation** rather than its value.
`ReactiveCell{T}(Computed(f))` (spelled `ComputedCell(f)` for the untyped case)
builds a computed cell whose thunk is `f`; every other argument — a `Function`
included — is stored as the cell's value.

Computedness is thus decided at the write site by a distinct type, never inferred
from what the value happens to be. That is what lets a cell hold a callable — a
callback, a predicate, a factory — as ordinary data: the only function a cell ever
calls is one that arrived inside this marker.

A `Computed` is cell vocabulary, not a value. It is consumed by the cell it is
handed to and never stored in one; and only the reactive kind has a computation to
hold, so handing it to another kind is an error rather than a silent box.
"""
struct Computed
    thunk::Function
end

Base.show(io::IO, c::Computed) = print(io, "Computed(", c.thunk, ")")
