# Fragment of `CellModule` — the cell **contract**: the base type of the cell
# kinds and the generics that form their protocol. Included before the kinds,
# which subtype it and implement it. Nothing here carries a body; the bodies
# (`unwrap_cell`'s default and `copy_cell_as`'s per-kind methods) live in the
# sibling `CellDefaults.jl`.

"""
    AbstractCell{T}

Base type of the cell kinds. `T` is the type of the held value. The shared
protocol is the read `c[]`, the untracked read `Base.peek(c)` (a sample that
registers no dependency), and [`is_cell_up_to_date`](@ref); everything else (writes,
thunks, dependency tracking) is kind-specific. See [`ReactiveCell`](@ref),
[`MutableCell`](@ref), [`ImmutableCell`](@ref).
"""
abstract type AbstractCell{T} end

"""
    is_cell_up_to_date(cell) -> Bool

Whether `cell` can be read without recomputing anything. A kind that holds its
value outright is trivially up to date; a kind that holds a computed thunk
answers with the validity of its cache.
"""
function is_cell_up_to_date end

"""
    unwrap_cell(x) -> value

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

A fresh cell of the same kind and declared value type as `c`, holding `v` — clone
a cell without deciding its kind, since each kind supplies its own method keyed on
the cell already there.
"""
function copy_cell_as end
