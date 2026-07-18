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
       set_cell_value!, set_cell_function!, is_cell_up_to_date, unwrap_cell,
       copy_cell_as

include("CellInterface.jl")
include("ReactiveCell.jl")
include("MutableCell.jl")
include("ImmutableCell.jl")
include("CellDefaults.jl")

end # module
