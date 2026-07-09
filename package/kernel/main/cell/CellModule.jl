"""
    CellModule

The reactive cell engine and its kinds. A cell is a typed box
`AbstractCell{T}`; the kind decides behavior — `ReactiveCell` (pull-based
dependency tracking; `Cell` = `ReactiveCell{Any}`), `MutableCell` (plain box, no
reactive bookkeeping), `ImmutableCell` (read-only wrapper). Also provides
`@cell_struct`, which declares a struct whose fields are transparent reactive
`Cell`s.

This file is the aggregator (exports + include list); see
[cell.md](../../doc/cell.md) for the engine, invariants, and worked examples.
"""
module CellModule

export Cell, AbstractCell, ReactiveCell, MutableCell, ImmutableCell,
       set_value!, set_function!, is_up_to_date
# `@cell_struct` and its assembler `cell_struct_exprs` / keyword-ctor builders
# `cell_struct_kw_params` / `cell_struct_kwctor` are the public codegen seam for macro authors;
# `cell_struct_autowrap_ctor` / `cell_struct_property_accessors` stay internal to CellStruct.jl.
export var"@cell_struct", cell_struct_exprs, cell_struct_kw_params, cell_struct_kwctor

# ── the base type + the three kinds (one file each) ────────────────────────
# AbstractCell first (it also holds the cross-kind protocol fallbacks); the
# concrete kinds subtype it.
include("AbstractCell.jl")
include("ReactiveCell.jl")
include("MutableCell.jl")
include("ImmutableCell.jl")

# ── transparent-Cell struct codegen (`@cell_struct` + its builders) ─────────
include("CellStruct.jl")

end # module
