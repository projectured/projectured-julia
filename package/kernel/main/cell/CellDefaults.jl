# Fragment of `CellModule` — the bodies for the cell contract's utility generics
# declared in `CellInterface.jl`: the `unwrap_cell` default, and `copy_cell_as`,
# which each kind answers for itself — a cell's kind lives in its type, so cloning
# reads it back off the cell already there.

unwrap_cell(x) = x isa AbstractCell ? x[] : x

copy_cell_as(c::ReactiveCell{T},  v) where {T} = ReactiveCell{T}(v)
copy_cell_as(c::MutableCell{T},   v) where {T} = MutableCell{T}(v)
copy_cell_as(c::ImmutableCell{T}, v) where {T} = ImmutableCell{T}(v)
