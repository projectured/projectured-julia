# Fragment of `CellModule` — the cell **contract**: the base type of the cell
# kinds and the generics that form their protocol. Included before the kinds,
# which subtype it and implement it. Nothing here carries a body. The read, the
# untracked read and `is_cell_up_to_date` live in the file of each kind, and the
# bodies of the other generics live in the sibling `CellDefaults.jl`.

"""
    AbstractCell{T}

What every kind of cell is: a box that holds one value, of type `T`.

Use it to say that something holds a value without saying how it holds it. A
write to a reactive cell invalidates the cells that read it, a write to a
mutable one invalidates nothing, and an immutable one can not be written. Code
that only reads takes any of them.

# Example

    show_value(cell::AbstractCell) = println(cell[])

Every kind has the read `c[]`, the untracked read `Base.peek(c)`, which records
no dependency, and [`is_cell_up_to_date`](@ref). The writes, the computations
and the dependency tracking belong to each kind.

See also `ReactiveCell`, `MutableCell`, `ImmutableCell` and `UntrackedCell`, the
four kinds, and `unwrap_cell`, for a slot that may hold a value instead of a cell.
"""
abstract type AbstractCell{T} end

"""
    is_cell_up_to_date(cell) -> Bool

Whether reading a cell costs nothing, or starts a computation.

Use it to tell a value that is ready from one that must be worked out: before a
measurement of what a read costs, or in a test that asks whether a write
reached the cells that depend on it.

# Example

    total = Cell(@computation length(rows[]))
    is_cell_up_to_date(total)       # false until the first read
    total[]
    is_cell_up_to_date(total)       # true

A kind that holds its value, and not a computation, is always up to date.

See also `set_cell_computation!` and `ReactiveCell`.
"""
function is_cell_up_to_date end

"""
    unwrap_cell(x) -> value

Read a value that may be wrapped in a cell, or may be the value itself.

Use it wherever a field, a slot or an argument holds either: a struct can store
some fields as cells and some as plain values, and this reads both without
asking which. The read is an ordinary one, so inside a computation
it makes the computation depend on the cell.

# Example

    width(box) = unwrap_cell(box.width) + unwrap_cell(box.padding)

See also `peek`, for a read that depends on nothing, and `AbstractCell`.
"""
function unwrap_cell end

"""
    get_cell_value_type(cell) -> Type

The type of the value that a cell holds: `T` for a cell of the type
`AbstractCell{T}`.

Use it to ask whether a value fits a cell before you write it, or to bind a type
parameter from a cell. The answer comes from the type of the cell, so it reads no
value, and no computation depends on the cell because of it.

# Example

    get_cell_value_type(ImmutableCell{Int}(1))      # Int64
    get_cell_value_type(Cell(1))                    # Any

A `Cell` is a `ReactiveCell{Any}`, so its value type is `Any`.

See also `unwrap_cell`, which reads the value.
"""
function get_cell_value_type end

"""
    make_similar_cell(c::AbstractCell, v) -> AbstractCell

Make a new cell like this one, holding another value.

Use it to copy a struct of cells: each field keeps the kind of cell it had, so a
reactive field stays reactive and a stored field stays stored, and the copy does
not have to know which was which.

# Example

    copied = make_similar_cell(getfield(original, :width), 120)

The new cell has the kind and the declared value type of `c`.

See also `AbstractCell` and `is_computed_cell`, which says whether the value
came from a computation.
"""
function make_similar_cell end

"""
    is_computed_cell(cell) -> Bool

Whether a cell computes its value or stores one.

Use it to tell a derived value from a written one before you copy, print or
freeze a struct of cells: the value of a computed cell is one moment of a
computation, and a cell that stores that moment stops following what the
computation reads.

# Example

    is_computed_cell(Cell(3))                       # false
    is_computed_cell(Cell(@computation 3))          # true

Only the reactive kind and the untracked kind can compute, so the other kinds
always return `false`.

See also `set_cell_computation!`, which makes a cell compute, and `make_similar_cell`.
"""
function is_computed_cell end

"""
    get_cell_computation(cell) -> Function or nothing

The computation that `cell` computes its value with, or `nothing` when it holds
a value.

Use it to put a computation around the one that a cell has, so a caller acts on
each value that the cell makes: the walk of the part under the pointer follows
each node of a lazy list when the list builds it. The caller gives the new
computation with `set_cell_computation!`.

Only the reactive kind keeps a computation that a caller can put another one
around, so the other kinds always return `nothing`.

See also `is_computed_cell`.
"""
function get_cell_computation end

"""
    has_dependent_cells(cell) -> Bool

Whether a live computed cell reads `cell`.

Use it to skip work that nothing shows: a producer that fills a cell can call it
first, and do nothing when no computation reads the cell.

# Example

    status = Cell("idle")
    has_dependent_cells(status)            # false
    shown = Cell(@computation uppercase(status[]))
    shown[]
    has_dependent_cells(status)            # true

A reactive cell holds its readers through a `WeakRef`. A reader that nothing
else holds still counts until the collector sweeps it, so the answer can stay
`true` for a short time after the last reader goes. That is the safe error: the
caller can do work that nobody needs, but it never skips work that a reader
needs. Only the reactive kind records readers, so the other kinds always return
`false`.

See also `is_cell_up_to_date`, and `peek`, a read that records no reader.
"""
function has_dependent_cells end
