"""
    CellStructModule

The transparent-cell **struct toolkit**: the compile-time machinery that turns a
plain `struct` definition into one whose fields are transparent `Cell`s. Two
pieces, each documented at its own definition:

  - the **struct plan** ([`StructPlan`](@ref) and its builders) — the parse of a
    `struct` definition (field names, declared types, defaults, cell kinds) a
    transparent-cell macro performs before it can emit code; and
  - the [`@cell_struct`](@ref) **codegen** ([`cell_struct_exprs`](@ref) and its
    expr-builders) — which rewrites every field to a `::Cell`, adds the
    auto-wrapping inner constructor and the transparent property accessors, and
    is the composition seam a higher-level transparent-cell macro reuses.

Built on [`CellModule`](@ref): the codegen wraps field values in the cell kinds
that module defines. [cell.md](../../doc/cell.md) covers the mechanics and
examples.
"""
module CellStructModule

using ..CellModule

# The `@cell_struct` macro and its codegen assemblers — the public seam a
# higher-level transparent-cell macro composes with.
export var"@cell_struct", cell_struct_exprs, cell_struct_kw_params, cell_struct_kwctor,
       cell_struct_positional_ctors, struct_macro_default
# The struct plan: the parse a transparent-cell struct macro does before it can
# emit anything. Public for the same reason — a macro consumes it.
export StructPlan, struct_plan, add_plan_field!, retype_fields!,
       declared_value_types, field_cell_kinds, cell_kind_of, required_count, trailing_default_count

include("StructPlan.jl")      # the shared struct-definition parse
include("CellStruct.jl")      # transparent-Cell struct codegen (@cell_struct)

end # module
