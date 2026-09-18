# Fragment of `CellModule` — the cell **contract**: the base type of the cell
# kinds and the generics that form their protocol. Included before the kinds,
# which subtype it and implement it. Nothing here carries a body; the bodies
# (`unwrap_cell`'s default and `copy_cell_as`'s per-kind methods) live in the
# sibling `CellDefaults.jl`.

"""
    AbstractCell{T}

What every kind of cell is: a box that holds one value, of type `T`.

Use it to say that something holds a value without saying how it holds it. A
reactive cell tells its readers when it changes, a mutable one keeps a value and
tells nobody, an immutable one cannot be written at all. Code that only reads
takes any of them.

# Example

    show_value(cell::AbstractCell) = println(cell[])

See also `ReactiveCell`, `MutableCell` and `ImmutableCell`, the three kinds, and
`unwrap_cell`, for a slot that may hold a value instead of a cell.

Base type of the cell kinds. `T` is the type of the held value. The shared
protocol is the read `c[]`, the untracked read `Base.peek(c)` (a sample that
registers no dependency), and [`is_cell_up_to_date`](@ref); everything else (writes,
thunks, dependency tracking) is kind-specific. See [`ReactiveCell`](@ref),
[`MutableCell`](@ref), [`ImmutableCell`](@ref).
"""
abstract type AbstractCell{T} end

"""
    is_cell_up_to_date(cell) -> Bool

Whether reading a cell costs nothing, or starts a computation.

Use it to tell a value that is ready from one that must be worked out: before a
measurement of what a read costs, or in a test that asks whether a write
reached the cells that depend on it.

# Example

    total = ComputedCell(() -> length(rows[]))
    is_cell_up_to_date(total)       # false until the first read
    total[]
    is_cell_up_to_date(total)       # true

See also `set_cell_function!` and `ReactiveCell`.

Whether `cell` can be read without recomputing anything. A kind that holds its
value outright is trivially up to date; a kind that holds a computed thunk
answers with the validity of its cache.
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

The cell-or-value accessor: read `x`'s value when it is a cell, pass it through
unchanged when it is not.

Any walk over a structure whose slots may hold *either* a raw value or a cell
wrapping one needs this. It is one expression, but it has exactly one meaning and
so exactly one home; open-coding it at each such walk is how it ends up written a
dozen ways.

The read is `x[]`, so unwrapping a `ReactiveCell` inside a cell computation
**registers a dependency**, exactly as a direct read would. Use `peek` where an
untracked sample is wanted instead.
"""
function unwrap_cell end

"""
    copy_cell_as(c::AbstractCell, v) -> AbstractCell

Make a new cell like this one, holding another value.

Use it when copying a document: each field keeps the kind of cell it had, so a
reactive field stays reactive and a stored field stays stored, and the copy does
not have to know which was which.

# Example

    copied = copy_cell_as(original.width, 120)

See also `AbstractCell` and `is_computed_cell`, which says whether the value
came from a computation.

A fresh cell of the same kind and declared value type as `c`, holding `v` — clone
a cell without deciding its kind, since each kind supplies its own method keyed on
the cell already there.
"""
function copy_cell_as end
