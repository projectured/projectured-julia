"""
    CellStructModule

A struct whose fields are cells, and the code generation that makes one.
`@cell_struct` writes each field as a cell, and generates a constructor that wraps
a value in a cell and property methods that read and write the value of a cell.
The builders of that code are public, so a macro that makes a struct of cells with
parts of its own starts from them.

A kind is one of the types `ReactiveCell`, `ImmutableCell` and `MutableCell` of
[`CellModule`](@ref), when a macro expands and at run time. The guide
`kernel/cell` explains the struct of cells with the cell engine.

The module lives in two fragments that share this namespace:

- [`CellStructPlan.jl`](CellStructPlan.jl) — `CellStructPlan`, the parse of a
  `struct` definition, and the functions that give the builders the kinds, the
  value types and the type parameters of its fields.
- [`CellStruct.jl`](CellStruct.jl) — `@cell_struct`, the builders that return its
  parts as expressions, and the two functions that read a struct of cells at run
  time.
"""
module CellStructModule

using ..CellModule

export CellStructPlan, make_cell_struct_plan, add_cell_struct_field!,
       retype_cell_struct_fields!, get_cell_struct_value_types,
       get_cell_struct_field_kinds, get_cell_struct_parameter_names,
       find_cell_struct_parameter_slots, get_cell_struct_trailing_default_count,
       get_cell_struct_required_count
export build_cell_struct_field_type, build_cell_struct_keyword_parameters,
       build_cell_struct_keyword_constructor, build_cell_struct_positional_ctors,
       build_cell_struct_exprs, parse_cell_struct_macro_arguments, @cell_struct,
       get_cell_struct_argument_type, get_cell_struct_kind

include("CellStructPlan.jl")
include("CellStruct.jl")

end # module
