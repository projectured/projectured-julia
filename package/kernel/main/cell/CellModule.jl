"""
    CellModule

The reactive cell engine and its kinds. A cell is a typed box
`AbstractCell{T}`; the kind decides behavior — `ReactiveCell` (pull-based
dependency tracking; `Cell` = `ReactiveCell{Any}`), `MutableCell` (plain box, no
reactive bookkeeping), `ImmutableCell` (read-only wrapper). Also provides
`@cell_struct`, a struct of transparent Cell fields that the declarative macros
(`@document`, `@iomap`, `@projection`) build on.

This file is the aggregator (exports + include list); see
[cell.md](../../doc/cell.md) for the engine, invariants, and worked examples.
"""
module CellModule

export Cell, AbstractCell, ReactiveCell, MutableCell, ImmutableCell,
       set_value!, set_function!, is_up_to_date
# `@cell_struct` and its assembler `cell_struct_exprs` / keyword-ctor builders
# `cell_kw_params` / `cell_kwctor` are the public codegen seam the declarative
# macros (`@document`, `@iomap`, `@projection`) build on. The remaining builders
# (`cell_autowrap_ctor`, `cell_property_accessors`) are internal to CellStruct.jl.
export var"@cell_struct", cell_struct_exprs, cell_kw_params, cell_kwctor

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
