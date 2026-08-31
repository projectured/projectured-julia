"""
    CellStructModule

The transparent-cell **struct toolkit** for a `struct` whose fields are
transparent `Cell`s. The compile-time codegen is two pieces, each documented at
its own definition:

  - the **struct plan** ([`CellStructPlan`](@ref) and its builders) — the parse of a
    `struct` definition (field names, declared types, defaults, cell kinds) a
    transparent-cell macro performs before it can emit code; and
  - the [`@cell_struct`](@ref) **codegen** ([`cell_struct_exprs`](@ref) and its
    expr-builders) — which rewrites every field to a `::Cell`, adds the
    auto-wrapping inner constructor and the transparent property accessors, and
    forms a reusable composition seam.

At runtime, [`get_cell_struct_kind`](@ref) reads back the cell kind a generated
struct is built from, off its first field.

Built on [`CellModule`](@ref): the codegen wraps field values in the cell kinds
that module defines. [cell.md](../../doc/cell.md) covers the mechanics and
examples.
"""
module CellStructModule

using ..CellModule

export var"@cell_struct", cell_struct_exprs, cell_struct_kw_params, cell_struct_kwctor,
       cell_struct_positional_ctors, cell_struct_macro_default
export CellStructPlan, cell_struct_plan, add_cell_struct_field!, retype_cell_struct_fields!,
       cell_struct_value_types, cell_struct_field_kinds, cell_kind_of, cell_struct_required_count, cell_struct_trailing_default_count,
       get_cell_struct_kind

include("CellStructPlan.jl")
include("CellStruct.jl")

end # module
