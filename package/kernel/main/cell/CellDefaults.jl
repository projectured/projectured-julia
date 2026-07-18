# Fragment of `CellModule` — cell behaviours defined over every kind: the body for
# `unwrap_cell` (its generic declared in `CellInterface.jl`), and the cell-kind
# reflection every consumer of the kinds reuses — clone a cell in its own kind
# (`copy_cell_as`) and read the kind a cell-struct is built from
# (`get_cell_struct_kind`). A cell's kind lives in its type, not in a caller's
# hands, so both read it back off the cell that is already there.

unwrap_cell(x) = x isa AbstractCell ? x[] : x

# The kind constructor behind a cell's concrete type.
_cell_kind(::Type{<:ReactiveCell})  = ReactiveCell
_cell_kind(::Type{<:MutableCell})   = MutableCell
_cell_kind(::Type{<:ImmutableCell}) = ImmutableCell

"""
    copy_cell_as(c::AbstractCell, v) -> AbstractCell

A fresh cell of the same kind and declared value type as `c`, holding `v` — the
way to clone a cell without deciding its kind, since the kind is read off the cell
that is already there.
"""
copy_cell_as(c::AbstractCell{T}, v) where {T} = _cell_kind(typeof(c)){T}(v)

"""
    get_cell_struct_kind(x) -> Type{<:AbstractCell} | Nothing

The cell kind a value's fields are built from — `ReactiveCell`, `MutableCell`, or
`ImmutableCell` — read off its first cell-backed field. A transparent-cell struct's
kind lives in its field cells, not in its type name, so this is how a caller that
must *build* something in the same kind (a copy, a shadow slot) discovers which
one. Returns `nothing` when the first field is not a cell.
"""
function get_cell_struct_kind(x)
    isempty(fieldnames(typeof(x))) && return nothing
    c = getfield(x, 1)
    c isa AbstractCell ? _cell_kind(typeof(c)) : nothing
end
