# Fragment of `CellStructModule` — `@cell_struct`, the builders that return the parts
# of a struct of cells as expressions, and the two functions that read a struct of
# cells at run time.

"""
    build_cell_struct_field_type(kind, value_type) -> Type | Expr

The declared type of a field of the kind `kind` that holds a value of the type
`value_type`. A `ReactiveCell` field is a `Cell`, which is `ReactiveCell{Any}`. An
`ImmutableCell` or `MutableCell` field is a cell of `value_type`, such as
`ImmutableCell{Int}`. The result holds the types as objects, so it needs no name in
the scope where it expands.
"""
build_cell_struct_field_type(kind, value_type) =
    kind === ReactiveCell ? Cell : Expr(:curly, kind, value_type)

# The inner constructor `T(values…)`, or `T{A…}(values…) where {A…}` for a struct
# with type parameters. Each field stores a cell argument as its cell, and `new`
# throws a `MethodError` when the cell does not have the type of the field, so a
# field never holds a cell as its value. Every other value goes into a new cell of
# the type of the field.
function _build_cell_struct_autowrap_ctor(plan, field_types)
    arguments = [gensym(name) for name in plan.field_names]
    values = map(enumerate(arguments)) do (i, argument)
        :($argument isa $(AbstractCell) ? $argument : $(field_types[i])($argument))
    end
    names = get_cell_struct_parameter_names(plan)
    isempty(names) && return Expr(:function, :($(plan.name)($(arguments...))),
                                  Expr(:block, Expr(:call, :new, values...)))
    head = Expr(:where, :($(Expr(:curly, plan.name, names...))($(arguments...))),
                plan.parameters...)
    Expr(:function, head,
         Expr(:block, Expr(:call, Expr(:curly, :new, names...), values...)))
end

# The outer constructor `T(values…)` of a struct with type parameters. It binds each
# parameter to the value type of the argument that `find_cell_struct_parameter_slots`
# gives, and calls `T{A…}(values…)`. The result is `nothing` for a struct without
# type parameters, and for a struct with a parameter that binds from no argument.
function _build_cell_struct_inferring_ctor(plan)
    isempty(plan.parameters) && return nothing
    slots = find_cell_struct_parameter_slots(plan)
    slots === nothing && return nothing
    arguments = [gensym(name) for name in plan.field_names]
    bound = [:($(get_cell_struct_argument_type)($(arguments[slot]))) for slot in slots]
    :($(plan.name)($(arguments...)) =
          $(Expr(:curly, plan.name, bound...))($(arguments...)))
end

# `object.f` reads the value of the cell in the field `f`, and `object.f = v` writes
# it. Every field holds a cell, so the methods need no branch for each field.
_build_cell_struct_property_accessors(type_name) = (
    :(Base.getproperty(object::$(type_name), name::Symbol) = getfield(object, name)[]),
    :(Base.setproperty!(object::$(type_name), name::Symbol, value) =
          (getfield(object, name)[] = value)))

"""
    build_cell_struct_keyword_parameters(field_names, defaults) -> Vector

The parameters of a keyword constructor, as `Base.@kwdef` writes them:
`name = default` for a field with a default, and the required keyword `name` for a
field without one.
"""
build_cell_struct_keyword_parameters(field_names, defaults) =
    Any[haskey(defaults, name) ? Expr(:kw, name, defaults[name]) : name
        for name in field_names]

"""
    build_cell_struct_keyword_constructor(type_name, field_names, parameters) -> Expr

The keyword constructor `type_name(; parameters…)`. It calls the positional
constructor `type_name(field_names…)`, so only the positional constructor wraps a
value in a cell.
"""
function build_cell_struct_keyword_constructor(type_name, field_names, parameters)
    # `Expr(:call, type_name, field_names...)` lowers to `Core._apply_iterate` on the
    # generic `Expr` constructor. A `juliac --trim=safe` build of omnet-julia reported
    # that call as a verifier error, so `append!` builds the same expression.
    call = Expr(:call, type_name)
    append!(call.args, field_names)
    :(function $(type_name)(; $(parameters...))
        $(call)
    end)
end

"""
    build_cell_struct_positional_ctors(plan, type_name; each_arity = _ -> ()) -> Vector

The positional constructors that leave out fields with a default at the end of the
declaration, as `Base.@kwdef` does for keywords. For each arity `k` from
`get_cell_struct_required_count(plan)` to one less than the number of fields,
`type_name(f₁, …, f_k)` calls the constructor of all fields with the defaults of
the fields that it leaves out.

The result is empty when no field is required, because a constructor without an
argument has the signature of the keyword constructor. It is also empty when the
last field has no default.

The function calls `each_arity(k)` only for an arity `k` that has a constructor,
and puts the expressions that it returns after that constructor. So a caller does
not compute that condition again.

When `find_cell_struct_parameter_slots(plan)` returns `nothing`, the constructors
name the type parameters: `type_name{A…}(f₁, …, f_k) where {A…}`.
"""
function build_cell_struct_positional_ctors(plan::CellStructPlan, type_name;
                                            each_arity = _ -> ())
    field_count = length(plan.field_names)
    required    = get_cell_struct_required_count(plan)
    ctors = Any[]
    required ≥ 1 || return ctors
    names = get_cell_struct_parameter_names(plan)
    needs_parameters = !isempty(names) &&
                       find_cell_struct_parameter_slots(plan) === nothing
    called = needs_parameters ? Expr(:curly, type_name, names...) : type_name
    for k in required:(field_count - 1)
        kept   = plan.field_names[1:k]
        filled = Any[plan.defaults[plan.field_names[j]] for j in (k + 1):field_count]
        head   = needs_parameters ?
                 Expr(:where, :($(called)($(kept...))), plan.parameters...) :
                 :($(type_name)($(kept...)))
        call   = Expr(:call, called, kept..., filled...)
        push!(ctors, Expr(:(=), head, Expr(:block, call)))
        append!(ctors, each_arity(k))
    end
    ctors
end

"""
    build_cell_struct_exprs(definition; default = ReactiveCell) -> Expr

The code of `@cell_struct` for one `struct` definition: the struct with its fields
written as cells and its inner constructor, the outer constructor that binds the
type parameters, the property accessors, and the keyword constructor. `default` is
the kind of a field whose type names no kind.

Use it to write a macro that makes a struct of cells with parts of its own, such
as a default supertype. The macro changes `definition`, and then returns the
result of this function escaped. The result names `new`, `getfield` and `Base`
without a module, so it must be escaped.

# Example

    macro shape(definition)
        definition.args[2] isa Symbol &&
            (definition.args[2] = :(\$(definition.args[2]) <: AbstractShape))
        esc(build_cell_struct_exprs(definition))
    end

See also `parse_cell_struct_macro_arguments`, which reads a leading kind.
"""
function build_cell_struct_exprs(definition; default = ReactiveCell)
    plan = make_cell_struct_plan(definition)
    isempty(plan.field_names) && return definition
    kinds       = get_cell_struct_field_kinds(plan; default = default)
    value_types = get_cell_struct_value_types(plan)
    field_types = Any[build_cell_struct_field_type(kinds[i], value_types[i])
                      for i in eachindex(kinds)]
    retype_cell_struct_fields!(plan, field_types)
    push!(plan.definition.args[3].args,
          _build_cell_struct_autowrap_ctor(plan, field_types))
    inferring = _build_cell_struct_inferring_ctor(plan)
    parts = Any[:(Base.@__doc__ $(plan.definition))]
    inferring === nothing || push!(parts, inferring)
    append!(parts, _build_cell_struct_property_accessors(plan.name))
    # The keyword constructor calls `T(values…)`, which a struct does not have when
    # one of its type parameters binds from no argument.
    if !isempty(plan.defaults) && (isempty(plan.parameters) || inferring !== nothing)
        parameters = build_cell_struct_keyword_parameters(plan.field_names, plan.defaults)
        push!(parts, build_cell_struct_keyword_constructor(plan.name, plan.field_names,
                                                           parameters))
    end
    Expr(:block, parts...)
end

"""
    parse_cell_struct_macro_arguments(arguments) -> (kind, definition)

Parse the arguments of a macro of the form `@macro [Kind] struct … end`. `Kind` is
`ReactiveCell`, `Cell`, `ImmutableCell` or `MutableCell`, and it sets the kind of
each field whose type names no kind. Without it, the kind is `ReactiveCell`.
"""
function parse_cell_struct_macro_arguments(arguments)
    length(arguments) == 1 && return (ReactiveCell, arguments[1])
    length(arguments) == 2 || throw(ArgumentError(
        "expected `[Kind] struct … end`, got $(length(arguments)) arguments"))
    kind = arguments[1] isa Symbol ? _find_cell_kind(arguments[1]) : nothing
    kind === nothing && throw(ArgumentError(
        "expected a cell kind before `struct`: ImmutableCell, MutableCell, " *
        "ReactiveCell or Cell, got `$(arguments[1])`"))
    (kind, arguments[2])
end

"""
    @cell_struct [Kind] struct T [<: Super] … end

A struct whose fields are cells, read and written like plain fields.

Use it to keep state that computations read in a struct of your own. A read of
`object.f` in a computation makes the computation depend on the field, and a write
to `object.f` makes it compute again.

# Example

    @cell_struct struct Counter
        count::Int = 0
    end
    counter = Counter()
    doubled = Cell(@computation 2 * counter.count)
    counter.count = 3
    doubled[]                                       # 6

Each field is a cell of one kind. A field `f::ImmutableCell{T}` or
`f::MutableCell{T}` has that kind. Every other field has the kind `Kind`, which is
`ReactiveCell` when the macro gets no `Kind`. A reactive field is a `Cell`, so its
declared type is not checked. An immutable or a mutable field is a cell of the
declared type.

The macro generates these parts:

- The inner constructor `T(values…)`. It stores a cell of the type of the field as
  the cell of that field, and it wraps every other value in a new cell. A cell of
  another type throws a `MethodError`, so a field never holds a cell as its value.
- `getproperty` and `setproperty!`. `object.f` reads the value of the cell, and
  `object.f = v` writes it. `getfield(object, :f)` returns the cell.
- A keyword constructor, when a field has a default `f = value`. A field with a
  default is an optional keyword, and a field without one is a required keyword.

A struct with type parameters keeps them, and `T{A}(values…)` makes one.
`T(values…)` also works when each parameter is the value type of a field. The
parameter then takes the value type of that argument, and a cell gives the type of
its value. A struct without that constructor has no keyword constructor either.

See also `get_cell_struct_kind`, and `build_cell_struct_exprs` for a macro that
adds parts of its own.
"""
macro cell_struct(arguments...)
    kind, definition = parse_cell_struct_macro_arguments(arguments)
    esc(build_cell_struct_exprs(definition; default = kind))
end

"""
    get_cell_struct_argument_type(argument) -> Type

The type that a constructor argument gives to a type parameter: `T` for a cell of
the type `AbstractCell{T}`, and the type of `argument` for any other value.

Use it in a constructor that binds a type parameter from its arguments, so that
an argument can be a cell or a value.

# Example

    get_cell_struct_argument_type(1)                        # Int64
    get_cell_struct_argument_type(ImmutableCell{Int}(1))    # Int64
    get_cell_struct_argument_type(Cell(1))                  # Any
"""
get_cell_struct_argument_type(argument) = typeof(argument)
get_cell_struct_argument_type(::AbstractCell{T}) where {T} = T

_get_cell_kind(::Type{<:ReactiveCell})  = ReactiveCell
_get_cell_kind(::Type{<:MutableCell})   = MutableCell
_get_cell_kind(::Type{<:ImmutableCell}) = ImmutableCell

"""
    get_cell_struct_kind(x) -> Type{<:AbstractCell} | Nothing

The kind of the cell in the first field of `x`: `ReactiveCell`, `MutableCell` or
`ImmutableCell`. The result is `nothing` when `x` has no field, or when its first
field is not a cell.

Use it to make a new struct of cells, such as a copy, in the kind of one that
exists. The kind is a property of the cells and not of the type name.

# Example

    @cell_struct ImmutableCell struct Point
        x::Int
        y::Int
    end
    get_cell_struct_kind(Point(1, 2))               # ImmutableCell

The function reads only the first field. For a struct whose fields have different
kinds, the result is the kind of the first field.
"""
function get_cell_struct_kind(x)
    isempty(fieldnames(typeof(x))) && return nothing
    cell = getfield(x, 1)
    cell isa AbstractCell ? _get_cell_kind(typeof(cell)) : nothing
end
