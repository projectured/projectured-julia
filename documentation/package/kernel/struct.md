# Structs of cells

> **Kind:** reference · **Status:** current · **Stands on:** [cell.md](cell.md)

This guide says how the struct layer makes a struct whose fields are cells, and
which builders it gives to the macros of the layers above. The layer is the folder
[source/kernel/struct/](../../../source/kernel/struct/), and `CellStructModule` is
its one module. It uses the cell layer and nothing else: the
[cell guide](cell.md) describes the cells, their kinds and the engine.

## Layer structure

```
cell/CellModule.jl                (CellModule): the cell kinds
        │  Cell and AbstractCell, used by ↓
struct/CellStructModule.jl        (CellStructModule): the struct of cells
        ├─ CellStructPlan.jl  : the parse of a struct definition that the struct macros share
        └─ CellStruct.jl      : @cell_struct and its expression builders
```

## CellStructModule: the struct of cells

`CellStructModule` is the struct layer, and it uses `CellModule` and nothing else.
`@cell_struct struct T [<: Super] … end` writes each field as a cell and generates
three parts:

- An inner constructor `T(values…)`. It wraps each value in a cell of the kind of
  its field. A cell of the type of the field is the cell of the field, so two
  structs can share one cell. A cell of another type throws a `MethodError`, so a
  field never holds a cell as its value.
- `getproperty` and `setproperty!`. `obj.f` reads the value of the cell,
  `obj.f = v` writes it, and `getfield(obj, :f)` returns the cell.
- A keyword constructor, when a field has a default `f = value`. It has the
  optional and required keywords of `Base.@kwdef`.

A kind is a type: `ReactiveCell`, `ImmutableCell`, `MutableCell` or
`UntrackedCell`. A field `f::ImmutableCell{T}`, `f::MutableCell{T}` or
`f::UntrackedCell{T}` has that kind. Every other field has the kind that the macro
gets before `struct`, or `ReactiveCell` without one. A reactive field is a `Cell`,
and an immutable, a mutable or an untracked field is a cell of the declared value
type. The struct keeps its supertype and its type parameters.
`T{A}(values…)` always works, and `T(values…)` works when each parameter is the
value type of a field.

The generated code holds the kinds and `Cell` as objects, so a module that calls
`@cell_struct` needs only the macro in scope. The code names `new`, `getfield` and
`Base` without a module, so `build_cell_struct_exprs` returns it unescaped and
the macro escapes it.

The builders are public, so a macro that makes a struct of cells with parts of its
own starts from them:

- `make_cell_struct_plan` reads a `struct` definition into a `CellStructPlan`.
- The `get_cell_struct_…` functions and `find_cell_struct_parameter_slots` answer
  questions about the fields and the type parameters of a plan.
- The `build_cell_struct_…` functions return the parts as expressions, and
  `build_cell_struct_exprs` returns all of `@cell_struct`.
- `parse_cell_struct_macro_arguments` reads the kind before `struct`.

[The macros guide](macros.md) says how `@iomap`, `@projection` and `@document`
use them. At run time, `get_cell_struct_kind(x)` returns the kind of the cell in
the first field of `x`. A generated constructor calls
`get_cell_struct_argument_type(argument)` to bind a type parameter: it returns the
value type of a cell, or the type of any other value.

Public surface: `CellStructPlan`, `make_cell_struct_plan`, `add_cell_struct_field!`,
`retype_cell_struct_fields!`, `get_cell_struct_value_types`,
`get_cell_struct_field_kinds`, `get_cell_struct_parameter_names`,
`find_cell_struct_parameter_slots`, `get_cell_struct_required_count`,
`build_cell_struct_field_type`, `build_cell_struct_keyword_parameters`,
`build_cell_struct_keyword_constructor`, `build_cell_struct_positional_constructors`,
`build_cell_struct_exprs`, `parse_cell_struct_macro_arguments`, `@cell_struct`,
`get_cell_struct_argument_type` and `get_cell_struct_kind`.
