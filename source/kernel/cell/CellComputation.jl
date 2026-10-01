# Fragment of `CellModule` — the computation of a cell: the marker that gives a
# cell a computation, and the macro that makes the marker for an expression. The
# constructor of the reactive kind dispatches on the marker, so this file comes
# before the kinds.

"""
    Computation(f::Function)

The marker that gives a cell a computation: the cell runs `f` to get its value,
and does not store `f` as its value.

Use it to give a cell a computation that exists as a function already: a named
function, or a function that came as an argument. For an expression, write
`@computation` instead. `f` takes no argument. A cell stores every other value
as it is, a function too, so a cell can hold a callback or a predicate as data.

# Example

    count_rows() = length(rows[])
    count = Cell(Computation(count_rows))

The cell keeps the function and not the marker. Only a `ReactiveCell` and an
`UntrackedCell` can compute, so a `MutableCell` or an `ImmutableCell` throws an
`ArgumentError` when it gets a `Computation`.

See also `@computation`, and `set_cell_computation!`, which gives a computation
to a cell that exists.
"""
struct Computation
    computation::Function
end

Base.show(io::IO, marker::Computation) =
    print(io, "Computation(", marker.computation, ")")

"""
    @computation expression

A `Computation` that computes `expression`: a cell evaluates it on its first
read, and again on the first read after a cell that it read was written.

Use it to state a derived value where it belongs, beside the thing that has it,
instead of computing it again at every place that needs it. It goes into a
reactive cell: a new cell, a typed cell, a write into a cell, or a reactive field
of a struct of cells. A `MutableCell` or an `ImmutableCell` throws an
`ArgumentError` for it.

# Example

    rows = Cell(["a", "b"])
    count = Cell(@computation length(rows[]))
    count[]                                   # 2
    double = ReactiveCell{Int}(@computation 2 * count[])
    count[] = @computation 0                  # the cell computes something else now

Inside an argument list, a macro call without parentheses takes every argument
after it. Where an argument follows, write `@computation(expression)`, as in
`pair(@computation(a[] + 1), b)`. For a function that exists already, write
`Computation(f)`: `@computation f` computes the function `f` as a value, and
does not call it.

See also `Computation`, the marker that it makes.
"""
macro computation(expression)
    :($Computation(() -> $(esc(expression))))
end
