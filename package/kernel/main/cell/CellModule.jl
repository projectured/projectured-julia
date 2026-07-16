"""
    CellModule

The reactive cell engine and its kinds. A cell is a typed box
`AbstractCell{T}`; the kind decides behavior — `ReactiveCell` (pull-based
dependency tracking; `Cell` = `ReactiveCell{Any}`), `MutableCell` (plain box, no
reactive bookkeeping), `ImmutableCell` (read-only wrapper).

This file is the aggregator; each kind is documented at its own definition, and
[cell.md](../../doc/cell.md) covers the engine, invariants, and examples.
"""
module CellModule

export Cell, AbstractCell, ReactiveCell, MutableCell, ImmutableCell,
       set_value!, set_function!, is_up_to_date, unwrap_cell

include("AbstractCell.jl")    # the base type; the kinds below subtype it
include("ReactiveCell.jl")
include("MutableCell.jl")
include("ImmutableCell.jl")
include("CellUnwrap.jl")      # unwrap_cell — reading a slot that may hold a cell

end # module
