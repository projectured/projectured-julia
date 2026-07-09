"""
    CellModule

The reactive cell engine and its kinds. A cell is a typed box
`AbstractCell{T}`; the kind decides behavior — `ReactiveCell` (pull-based
dependency tracking; `Cell` = `ReactiveCell{Any}`), `MutableCell` (plain box, no
reactive bookkeeping), `ImmutableCell` (read-only wrapper). Also provides
`@cell_struct`, which declares a struct whose fields are transparent reactive
`Cell`s.

This file is the aggregator; each kind and the codegen are documented at their
own definition, and [cell.md](../../doc/cell.md) covers the engine, invariants,
and examples.
"""
module CellModule

export Cell, AbstractCell, ReactiveCell, MutableCell, ImmutableCell,
       set_value!, set_function!, is_up_to_date
# The exported `@cell_struct` and its codegen assemblers are the public seam for
# macro authors; CellStruct.jl's remaining builders stay internal.
export var"@cell_struct", cell_struct_exprs, cell_struct_kw_params, cell_struct_kwctor

include("AbstractCell.jl")    # the base type; the kinds below subtype it
include("ReactiveCell.jl")
include("MutableCell.jl")
include("ImmutableCell.jl")
include("CellStruct.jl")      # transparent-Cell struct codegen (@cell_struct)

end # module
