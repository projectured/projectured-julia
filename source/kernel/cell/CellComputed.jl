# Fragment of `CellModule` — the marker of a computation. The constructor of the
# reactive kind dispatches on it, so this file comes before the kinds.

"""
    Computed(thunk::Function)

The marker that makes a cell compute: the cell runs `thunk` to get its value,
and does not store `thunk` as its value.

Use it to give a computation to a cell where a value goes: to a typed cell, to a
write into a cell that exists, or to a field of a document. `thunk` takes no
argument. A cell stores every other value as it is, a function too, so a cell
can hold a callback or a predicate as data.

# Example

    width = Cell(80)
    label = ReactiveCell{String}(Computed(() -> "width " * string(width[])))
    label[]                              # "width 80"
    label[] = Computed(() -> "fixed")    # the cell computes something else now

The cell keeps the thunk and not the marker. Only a `ReactiveCell` can compute,
so a `MutableCell` or an `ImmutableCell` throws an `ArgumentError` when it gets a
`Computed`.

See also `ComputedCell`, which makes an untyped computed cell, and
`set_cell_function!`.
"""
struct Computed
    thunk::Function
end

Base.show(io::IO, c::Computed) = print(io, "Computed(", c.thunk, ")")
