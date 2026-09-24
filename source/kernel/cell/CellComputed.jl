# Fragment of `CellModule` — the marker of a computation. The constructor of the
# reactive kind dispatches on it, so this file comes before the kinds.

"""
    Computed(thunk::Function)

The marker that makes a cell compute: the cell runs `thunk` to get its value,
and does not store `thunk` as its value.

Use it to state a derived value where it belongs, beside the thing that has it,
instead of computing it again at every place that needs it. `Cell(Computed(f))`
is a cell whose value `f` computes, the first time it is read and after anything
it read has changed. The marker also goes where any other value goes: to a typed
cell, to a write into a cell that exists, or to a field of a document. `thunk`
takes no argument, and a cell stores every other value as it is, a function too.

# Example

    rows = Cell(["a", "b"])
    count = Cell(Computed(() -> length(rows[])))
    count[]                                   # 2
    double = ReactiveCell{Int}(Computed(() -> 2 * count[]))
    count[] = Computed(() -> 0)               # the cell computes something else now

The cell keeps the thunk and not the marker. Only a `ReactiveCell` can compute,
so a `MutableCell` or an `ImmutableCell` throws an `ArgumentError` when it gets a
`Computed`.

See also `Cell`, which holds a value, and `set_cell_function!`, which makes a
cell that holds a value compute.
"""
struct Computed
    thunk::Function
end

Base.show(io::IO, c::Computed) = print(io, "Computed(", c.thunk, ")")
