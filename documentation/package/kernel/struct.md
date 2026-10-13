# Structs of cells

> **Kind:** reference · **Status:** current · **Stands on:** [cell.md](cell.md)

This guide says how the struct layer makes a struct whose fields are cells, and
which builders it gives to a macro that makes such a struct with parts of its own.
The layer is the folder [source/kernel/struct/](../../../source/kernel/struct/), and
`CellStructModule` is its one module. It uses the cell layer and nothing else: the
[cell guide](cell.md) describes the cells, their kinds and the engine.

## A struct of cells

`@cell_struct struct T [<: Super] … end` writes each field as a cell. A read and a
write of a field look like those of a plain field, and a computation that reads a
field follows its writes.

```julia
@cell_struct struct Point
    x::Int
    y::Int = 0
end
point = Point(5, 1)
total = Cell(@computation point.x + point.y)
total[]                     # 6
point.y = 4
total[]                     # 9, computed again
getfield(point, :x)         # Cell(value, 5): the cell of the field
```

The macro generates these parts:

- **The inner constructor `T(values…)`.** It wraps each value in a new cell of the
  kind of its field. A cell of the type of the field cell becomes the cell of the
  field, so two structs can share one cell. A cell of another type throws a
  `MethodError`, so a field never holds a cell as its value.
- **`getproperty` and `setproperty!`.** `object.f` reads the value of the cell, and
  `object.f = v` writes it. A cell as `v` throws an `ArgumentError`, because a
  field holds a value: two structs share a cell only through the constructor. A
  `Computation` as `v` gives a reactive field a computation, as `c[] = v` does.
- **A keyword constructor**, when a field has a default `f = value`. A field with a
  default is an optional keyword, and a field without one is a required keyword,
  as in `Base.@kwdef`. `Point(x = 7)` makes `Point(7, 0)`, and `Point(y = 2)` throws
  an `UndefKeywordError`.

The macro gives `nothing`, as a `struct` definition does. A write follows the rule
of the cell of the field: a write of the same plain value to a reactive field
makes nothing compute again, and a write to an immutable field throws a
`MethodError`. The generated code holds the kinds and `Cell` as objects, so a module
that calls `@cell_struct` needs only the macro in scope.

## The kind of each field

A kind is one of the types `ReactiveCell`, `ImmutableCell`, `MutableCell` and
`UntrackedCell`. A field whose type names a kind has that kind:

- `f::ImmutableCell{T}`, `f::MutableCell{T}` and `f::UntrackedCell{T}`;
- `f::Cell` and `f::ReactiveCell{T}` for the reactive kind.

Every other field has the kind that the macro gets before `struct`, or
`ReactiveCell` without one: `@cell_struct ImmutableCell struct Label … end` makes
each such field immutable. An immutable, a mutable or an untracked field is a cell
of its declared value type. A reactive field is a `Cell`, which is
`ReactiveCell{Any}`, so its declared type is not checked, and a `ReactiveCell{T}`
cell of another `T` is not the cell of the field.

`get_cell_struct_kind(x)` reads the kind of the cell in the first field of `x`, and
`nothing` when `x` has no field or its first field is not a cell. For a struct whose
fields have different kinds, it is the kind of the first field. Use it to make a
new struct, such as a copy, in the kind of one that exists.

## Type parameters

A struct keeps its supertype and its type parameters, and `T{A}(values…)` always
makes one. `T(values…)` works too when each parameter is the value type of a
field: an outer constructor binds each parameter from the argument of that field,
with `get_cell_struct_argument_type`.

- A plain value gives its type, and a typed cell, such as `ImmutableCell{Int}`,
  gives the type of its value.
- A `Computation`, whose value type is not known before it runs, and a `Cell`,
  which holds any value, give the declared bound of the parameter: `Real` for
  `A<:Real`, and `Any` for `A`. A bound that names another parameter gives `Any`.
- A parameter that is the value type of no field, such as `A` in `items::Vector{A}`,
  binds from no argument. Then the struct has only `T{A}(values…)`, and no keyword
  constructor either, because the keyword constructor calls `T(values…)`.

The parameter of a reactive field is a label of the type after the construction:
the field is a `Cell`, so `box = Box(1)` makes a `Box{Int}`, and `box.content =
"text"` then holds a `String`. Use an immutable, a mutable or an untracked field
when the parameter must also hold for each write.

## What the macro does not do

- **No Rule Y.** `@cell_struct` makes no positional constructor that leaves out a
  trailing run of defaults. A generated method with the signature of an outer
  constructor that the programmer wrote would overwrite it when the package
  precompiles. Only `@document` applies Rule Y; see [the macros guide](macros.md).
- **No inner constructor of the programmer.** The builders generate the only inner
  constructor, so an inner constructor in the body is an `ArgumentError`. So is a
  body expression that is not a field, a line number or a docstring, such as
  `const f::T`. Define a constructor outside the struct.
- **No change to a struct without fields.** Its definition comes back as it is.

A `mutable struct` works, and so does a docstring on a field.

## Where a generated method points

`@cell_struct` passes its `__source__` to the builder, so each generated method
points to the declaration of the struct: a stack trace, `methods(T)` and the hint of
a `MethodError` name that line, not a file of the kernel. A macro of your own passes
its `__source__` too, as the keyword `source` of `build_cell_struct_exprs`.

## A macro of your own

The builders are public, so a macro that makes a struct of cells with parts of its
own starts from them. `@iomap` and `@projection` call `build_cell_struct_exprs`;
`@document` takes the parts that it needs. [The macros guide](macros.md) says how.

1. **Read the arguments.** `parse_cell_struct_macro_arguments(arguments)` reads
   `@macro [Kind] struct … end` into the kind and the definition.
2. **Parse the definition.** `make_cell_struct_plan(definition)` gives a
   `CellStructPlan`: the name, the type parameters, the supertype, and for each
   field its name, its declared type, its slot in the body and its default.
   `declared_field_count` and `programmer_default_count` count what the
   programmer wrote.
3. **Ask the plan.** `get_cell_struct_field_kinds(plan; default)` gives the kind of
   each field, and `get_cell_struct_value_types(plan)` its value type.
   `get_cell_struct_parameter_names` and `get_cell_struct_parameter_bounds` give
   the name and the bound of each type parameter, and
   `find_cell_struct_parameter_slots` the field that binds each one, or `nothing`.
   `get_cell_struct_required_count` gives the number of fields before the trailing
   run of defaults.
4. **Change the plan.** `add_cell_struct_field!(plan, name; type, default)` adds a
   field that the programmer does not write, such as a label.
   `retype_cell_struct_fields!(plan, types)` writes a type into the slot of each
   field, and `build_cell_struct_field_type(kind, value_type)` gives that type for a
   kind. Both write the definition of the plan in place.
5. **Build the parts.** `build_cell_struct_exprs(plan; default, source)` gives the
   whole struct of cells from the plan, and `build_cell_struct_exprs(definition;
   …)` from a definition. Neither changes its argument. The result names `new`,
   `getfield` and `Base` without a module, so the macro returns it escaped.
   `build_cell_struct_keyword_parameters` and `build_cell_struct_keyword_constructor`
   give the keyword constructor alone.
   `build_cell_struct_positional_constructors(plan, name; each_arity)` gives the
   constructors of Rule Y, and calls `each_arity(k)` for each arity `k` that has
   one, so a caller can put a part of its own after it.

```julia
macro labeled(definition)
    plan = make_cell_struct_plan(definition)
    add_cell_struct_field!(plan, :label; type = :String, default = "none")
    esc(build_cell_struct_exprs(plan; source = __source__))
end
@labeled struct Tagged
    value::Int
end
Tagged(value = 3).label     # "none"
```

## Layer structure

```
cell/CellModule.jl                (CellModule): the cell kinds
        │  Cell, AbstractCell, Computation and the kinds, used by ↓
struct/CellStructModule.jl        (CellStructModule): the struct of cells
        ├─ CellStructPlan.jl  : the plan of a definition, the field changes, and the questions
        └─ CellStruct.jl      : @cell_struct, the builders, the argument type and the kind
```

`CellStructPlan.jl` holds `CellStructPlan`, `make_cell_struct_plan`,
`add_cell_struct_field!`, `retype_cell_struct_fields!` and the questions about the
fields and the type parameters. `CellStruct.jl` holds the builders, `@cell_struct`,
`parse_cell_struct_macro_arguments`, `get_cell_struct_argument_type`, which a
generated constructor calls at run time, and `get_cell_struct_kind`.

## Try it

`print_cell_struct_example()` in `ProjecturedKernelExample` prints a REPL session
with the layer: a struct of cells, a read and a write of a field, the cell of a
field, a computation that follows a field, a shared cell, a write of a cell that
throws, the keyword constructor, the kind of each field, type parameters and their
bounds, a plan and the builders, and a macro that adds a field. Each line runs as it
prints. Type the lines yourself after `using ProjecturedKernel.CellStructModule`.

```julia
using ProjecturedKernelExample
print_cell_struct_example()
```

Public surface: `CellStructPlan`, `make_cell_struct_plan`, `add_cell_struct_field!`,
`retype_cell_struct_fields!`, `get_cell_struct_value_types`,
`get_cell_struct_field_kinds`, `get_cell_struct_parameter_names`,
`get_cell_struct_parameter_bounds`, `find_cell_struct_parameter_slots`,
`get_cell_struct_required_count`, `build_cell_struct_field_type`,
`build_cell_struct_keyword_parameters`, `build_cell_struct_keyword_constructor`,
`build_cell_struct_positional_constructors`, `build_cell_struct_exprs`,
`parse_cell_struct_macro_arguments`, `@cell_struct`, `get_cell_struct_argument_type`
and `get_cell_struct_kind`.
