# Fragment of `CellModule` — the cell **contract**: the base type of the cell
# kinds and the generics that form their protocol. Included before the kinds,
# which subtype it and implement it. Nothing here carries a body. The read, the
# untracked read and `is_cell_up_to_date` live in the file of each kind, and the
# bodies of the other generics live in the sibling `CellDefaults.jl`.

"""
    AbstractCell{T}

What every kind of cell is: a box that holds one value, of type `T`.

Use it to say that something holds a value without saying how it holds it. A
reactive cell tells its readers when it changes, a mutable one keeps a value and
tells nobody, an immutable one cannot be written at all. Code that only reads
takes any of them.

# Example

    show_value(cell::AbstractCell) = println(cell[])

Every kind has the read `c[]`, the untracked read `Base.peek(c)`, which records
no dependency, and [`is_cell_up_to_date`](@ref). The writes, the computations
and the dependency tracking belong to each kind.

See also `ReactiveCell`, `MutableCell` and `ImmutableCell`, the three kinds, and
`unwrap_cell`, for a slot that may hold a value instead of a cell.
"""
abstract type AbstractCell{T} end

"""
    is_cell_up_to_date(cell) -> Bool

Whether reading a cell costs nothing, or starts a computation.

Use it to tell a value that is ready from one that must be worked out: before a
measurement of what a read costs, or in a test that asks whether a write
reached the cells that depend on it.

# Example

    total = Cell(Computed(() -> length(rows[])))
    is_cell_up_to_date(total)       # false until the first read
    total[]
    is_cell_up_to_date(total)       # true

A kind that holds its value, and not a computation, is always up to date.

See also `set_cell_function!` and `ReactiveCell`.
"""
function is_cell_up_to_date end

"""
    unwrap_cell(x) -> value

Read a value that may be wrapped in a cell, or may be the value itself.

Use it wherever a field, a slot or an argument holds either: the document
machinery stores some fields as cells and some as plain values, and this reads
both without asking which. The read is an ordinary one, so inside a computation
it makes the computation depend on the cell.

# Example

    width(box) = unwrap_cell(box.width) + unwrap_cell(box.padding)

See also `peek`, for a read that depends on nothing, and `AbstractCell`.
"""
function unwrap_cell end

"""
    copy_cell_as(c::AbstractCell, v) -> AbstractCell

Make a new cell like this one, holding another value.

Use it when copying a document: each field keeps the kind of cell it had, so a
reactive field stays reactive and a stored field stays stored, and the copy does
not have to know which was which.

# Example

    copied = copy_cell_as(getfield(original, :width), 120)

The new cell has the kind and the declared value type of `c`.

See also `AbstractCell` and `is_computed_cell`, which says whether the value
came from a computation.
"""
function copy_cell_as end

"""
    is_computed_cell(cell) -> Bool

Whether a cell computes its value or stores one.

Use it to tell a derived value from a written one before you copy, print or
freeze a document: the value of a computed cell is one moment of a
computation, and a cell that stores that moment stops following what the
computation reads.

# Example

    is_computed_cell(Cell(3))                       # false
    is_computed_cell(Cell(Computed(() -> 3)))       # true

Only the reactive kind can compute, so the other kinds always return `false`.

See also `set_cell_function!`, which makes a cell compute, and `copy_cell_as`.
"""
function is_computed_cell end

"""
    has_dependent_cells(cell) -> Bool

Whether a live computed cell reads `cell`.

Use it to skip work that nothing shows: a producer that fills a cell can call it
first, and do nothing when no computation reads the cell.

# Example

    status = Cell("idle")
    has_dependent_cells(status)            # false
    shown = Cell(Computed(() -> uppercase(status[])))
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
