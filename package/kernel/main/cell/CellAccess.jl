# Fragment of `CellModule` — reading a slot that may or may not hold a cell.
#
# An implementation fragment, deliberately not part of `AbstractCell.jl`: that is
# the layer's interface file and carries declarations only (#72). `unwrap_cell`
# has a body, so it lives beside the contract rather than inside it.

"""
    unwrap_cell(x) -> value

The cell-or-value accessor: read `x`'s value when it is a cell, pass it through
unchanged when it is not.

Any walk over a structure whose slots may hold *either* a raw value or a cell
wrapping one needs this — a document's fields, a `Vector{Cell}`'s elements, a
projection's output. It is one expression, but it has exactly one meaning and so
exactly one home; open-coding it at each such walk is how it ends up written a
dozen ways.

The read is `x[]`, so unwrapping a `ReactiveCell` inside a cell computation
**registers a dependency**, exactly as a direct read would. Use `peek` where an
untracked sample is wanted instead.
"""
unwrap_cell(x) = x isa AbstractCell ? x[] : x
