# Fragment of `CellStructModule` — the parse of a `struct` definition into a
# `CellStructPlan`, and the functions that give the builders the kinds, the value
# types and the type parameters of its fields.

"""
    CellStructPlan

A `struct` definition, parsed: the name, the type parameters, the supertype, the
fields and the defaults. Every builder of the struct layer reads it.

- `definition` is the `struct` expression. The builders change it in place.
- `parameters` holds each type parameter as the programmer wrote it, such as
  `A<:Real`. It is empty when the struct has none.
- `supertype` is the supertype expression, or `nothing` when none is written.
- `field_types` holds the declared type of each field, or `nothing` for a field
  without one.
- `field_slots` holds the index of each field in the body of `definition`.
- `defaults` maps the name of a field to its default expression.
- `declared_field_count` and `programmer_default_count` count the fields and the
  defaults of the source. A field that `add_cell_struct_field!` adds does not
  change them.

Use it to read the fields of the definition that your macro gets, and to give
them to the builders of the struct layer. `make_cell_struct_plan` makes one.

# Example

    plan = make_cell_struct_plan(:(struct Point; x::Int; y::Int = 0; end))
    plan.field_names                                # [:x, :y]
    plan.defaults                                   # Dict(:y => 0)

See also `build_cell_struct_exprs`, which makes the whole struct of cells from a
definition.
"""
struct CellStructPlan
    definition               :: Expr
    name                     :: Symbol
    parameters               :: Vector{Any}
    supertype                :: Any
    field_names              :: Vector{Symbol}
    field_types              :: Vector{Any}
    field_slots              :: Vector{Int}
    defaults                 :: Dict{Symbol,Any}
    declared_field_count     :: Int
    programmer_default_count :: Int
end

"""
    make_cell_struct_plan(definition) -> CellStructPlan

Parse a `struct` definition. A field is `f`, `f::T`, `f = v` or `f::T = v`. The
plan holds each default, and the body keeps it until `retype_cell_struct_fields!`
writes the slot of the field.

An inner constructor in the body is an error, because the builders generate the
only inner constructor. Define the constructor outside the struct. Any other
expression that is not a field, a line number or a docstring is an error too,
such as `const f::T` or `@atomic f::T`.

Use it to start a macro that makes a struct of cells: parse the definition that
the macro gets, then ask the plan for the kinds and the value types of its fields.

# Example

    plan = make_cell_struct_plan(:(struct Point; x::Int; y::Int = 0; end))
    plan.name                                       # :Point
    get_cell_struct_required_count(plan)            # 1

See also `parse_cell_struct_macro_arguments`, which reads a kind before `struct`.
"""
function make_cell_struct_plan(definition)
    definition isa Expr && definition.head === :struct ||
        throw(ArgumentError("make_cell_struct_plan expects a struct definition"))
    name_expr      = definition.args[2]
    has_supertype  = name_expr isa Expr && name_expr.head === :(<:)
    head           = has_supertype ? name_expr.args[1] : name_expr
    supertype      = has_supertype ? name_expr.args[2] : nothing
    has_parameters = head isa Expr && head.head === :curly
    name           = has_parameters ? head.args[1] : head
    parameters     = has_parameters ? Any[head.args[2:end]...] : Any[]
    name isa Symbol || throw(ArgumentError(
        "make_cell_struct_plan: the name of a struct must be a symbol, got `$(name)`"))

    field_names = Symbol[]
    field_types = Any[]
    field_slots = Int[]
    defaults    = Pair{Symbol,Any}[]
    for (slot, expression) in enumerate(definition.args[3].args)
        if expression isa Symbol                                      # f
            field_name, field_type = expression, nothing
        elseif _is_field_declaration(expression)                      # f::T
            field_name, field_type = expression.args
        elseif expression isa Expr && expression.head === :(=)        # f = v, f::T = v
            left = expression.args[1]
            if left isa Symbol
                field_name, field_type = left, nothing
            elseif _is_field_declaration(left)
                field_name, field_type = left.args
            else
                _reject_inner_constructor(name, left)
            end
            push!(defaults, field_name => expression.args[2])
        elseif expression isa Expr && expression.head === :function
            _reject_inner_constructor(name, expression.args[1])
        elseif expression isa LineNumberNode || expression isa String
            continue                                    # a line number, a docstring
        else
            _reject_body_expression(name, expression)
        end
        push!(field_names, field_name)
        push!(field_types, field_type)
        push!(field_slots, slot)
    end

    CellStructPlan(definition, name, parameters, supertype, field_names, field_types,
                   field_slots, Dict(defaults), length(field_names), length(defaults))
end

_is_field_declaration(expression) =
    expression isa Expr && expression.head === :(::) &&
    length(expression.args) == 2 && expression.args[1] isa Symbol

_reject_inner_constructor(name, signature) = throw(ArgumentError(
    "make_cell_struct_plan: `$(signature)` in the body of `$(name)` is an inner " *
    "constructor. The builders generate the only inner constructor, so define " *
    "this one outside the struct."))

_reject_body_expression(name, expression) = throw(ArgumentError(
    "make_cell_struct_plan: `$(expression)` in the body of `$(name)` is not a " *
    "field. A field is `f`, `f::T`, `f = v` or `f::T = v`."))

"""
    add_cell_struct_field!(plan, name; type, default) -> CellStructPlan

Add a field after the last field, in the plan and in the body of the definition.
The field has the declared type `type` and the default `default`. Its slot holds
`name::Any` until `retype_cell_struct_fields!` writes it.

Use it to give each struct of your macro a field that the programmer does not
write, such as a label or a link to a parent.

# Example

    plan = make_cell_struct_plan(:(struct Point; x::Int; end))
    add_cell_struct_field!(plan, :label; type = :String, default = "")
    plan.field_names                                # [:x, :label]
"""
function add_cell_struct_field!(plan::CellStructPlan, name::Symbol; type, default)
    body = plan.definition.args[3]
    push!(body.args, :($(name)::Any))
    push!(plan.field_names, name)
    push!(plan.field_types, type)
    push!(plan.field_slots, length(body.args))
    plan.defaults[name] = default
    plan
end

"""
    retype_cell_struct_fields!(plan, types) -> CellStructPlan

Write `name::types[i]` into the slot of each field, which also removes the default
of the field from the body. The function writes the slots in place, so each
`LineNumberNode` of the body stays, and an error or a docstring still gives the
source line of a field.

Use it to write the field types that your macro chose, such as a cell of the
value type, into the definition before the macro returns it.

# Example

    plan = make_cell_struct_plan(:(struct Point; x::Int; y::Int = 0; end))
    types = [build_cell_struct_field_type(ImmutableCell, value_type)
             for value_type in get_cell_struct_value_types(plan)]
    retype_cell_struct_fields!(plan, types)         # x::ImmutableCell{Int}, and y
"""
function retype_cell_struct_fields!(plan::CellStructPlan, types)
    body = plan.definition.args[3]
    for (i, slot) in enumerate(plan.field_slots)
        body.args[slot] = :($(plan.field_names[i])::$(types[i]))
    end
    plan
end

# The kind that a name in a field type or in a macro argument names, or `nothing`.
# The check is on the name, because no type exists yet when a macro expands.
_find_cell_kind(name::Symbol) =
    name === :ImmutableCell ? ImmutableCell :
    name === :MutableCell   ? MutableCell   :
    name === :UntrackedCell ? UntrackedCell :
    name === :ReactiveCell || name === :Cell ? ReactiveCell : nothing

# The kind that a declared field type names, or `nothing`, and the value type.
# `ImmutableCell{Int}` gives `(ImmutableCell, :Int)`, `Int` gives `(nothing, :Int)`,
# and a field without a type gives `(nothing, :Any)`.
function _parse_field_type(field_type)
    field_type === nothing && return (nothing, :Any)
    if field_type isa Symbol
        kind = _find_cell_kind(field_type)
        return kind === nothing ? (nothing, field_type) : (kind, :Any)
    end
    if field_type isa Expr && field_type.head === :curly && field_type.args[1] isa Symbol
        kind = _find_cell_kind(field_type.args[1])
        kind === nothing ||
            return (kind, length(field_type.args) ≥ 2 ? field_type.args[2] : :Any)
    end
    (nothing, field_type)
end

"""
    get_cell_struct_value_types(plan) -> Vector

The value type of each field, as an expression. A field `f::T` gives `T`, a field
`f::ImmutableCell{T}` gives `T`, and a field without a type gives `Any`.

Use it to know the type of the value that each field holds, also for a field that
names a kind, for example to type the arguments of a constructor.

# Example

    plan = make_cell_struct_plan(:(struct P; a::Int; b::ImmutableCell{String}; c; end))
    get_cell_struct_value_types(plan)               # [:Int, :String, :Any]

See also `get_cell_struct_field_kinds`, which gives the kind of each field.
"""
get_cell_struct_value_types(plan::CellStructPlan) =
    Any[last(_parse_field_type(type)) for type in plan.field_types]

"""
    get_cell_struct_field_kinds(plan; default = ReactiveCell) -> Vector

The kind of each field: `ReactiveCell`, `ImmutableCell`, `MutableCell` or
`UntrackedCell`. A field whose type names a kind, such as `f::ImmutableCell{T}`,
has that kind. Every other field has the kind `default`.

Use it to choose the cell of each field in your macro: the kind that the field
names, or the kind that the macro gets for the others.

# Example

    plan = make_cell_struct_plan(:(struct P; a::Int; b::ImmutableCell{String}; end))
    get_cell_struct_field_kinds(plan; default = MutableCell)
    # [MutableCell, ImmutableCell]

See also `get_cell_struct_value_types`, which gives the type of each value.
"""
get_cell_struct_field_kinds(plan::CellStructPlan; default = ReactiveCell) =
    Any[something(first(_parse_field_type(type)), default) for type in plan.field_types]

"""
    get_cell_struct_parameter_names(plan) -> Vector{Symbol}

The name of each type parameter: `A` for `A`, `A<:Real`, `A>:Int` and
`Int<:A<:Real`. A type application such as `T{A}` takes the names, and a `where`
clause or the head of a struct takes `plan.parameters`.

Use it to write the type application of a struct with type parameters, such as
`T{A}` in the head of a constructor of your macro.

# Example

    plan = make_cell_struct_plan(:(struct Box{T<:Real}; value::T; end))
    get_cell_struct_parameter_names(plan)           # [:T]
    plan.parameters                                 # [:(T <: Real)]
"""
get_cell_struct_parameter_names(plan::CellStructPlan) =
    Symbol[_get_parameter_name(parameter) for parameter in plan.parameters]

_get_parameter_name(parameter::Symbol) = parameter
function _get_parameter_name(parameter::Expr)
    parameter.head in (:(<:), :(>:)) && return parameter.args[1]
    parameter.head === :comparison && return parameter.args[3]
    throw(ArgumentError("`$(parameter)` is not a type parameter"))
end

"""
    find_cell_struct_parameter_slots(plan) -> Vector{Int} | nothing

For each type parameter, the index of the first field whose value type is that
parameter. A constructor that names no parameter, `T(values…)`, binds each
parameter from the argument at that index. The function returns `nothing` when a
parameter is the value type of no field, such as `A` in `f::Vector{A}`. A caller
then writes `T{A}(values…)`.

Use it to write a constructor that binds each type parameter from its argument,
so that a caller writes `Box(1)` and not `Box{Int}(1)`.

# Example

    plan = make_cell_struct_plan(:(struct Box{T}; value::T; end))
    find_cell_struct_parameter_slots(plan)          # [1]
    plan = make_cell_struct_plan(:(struct Bag{T}; items::Vector{T}; end))
    find_cell_struct_parameter_slots(plan)          # nothing

See also `get_cell_struct_argument_type`, which gives the type that an argument
binds.
"""
function find_cell_struct_parameter_slots(plan::CellStructPlan)
    value_types = get_cell_struct_value_types(plan)
    slots = Int[]
    for name in get_cell_struct_parameter_names(plan)
        slot = findfirst(==(name), value_types)
        slot === nothing && return nothing
        push!(slots, slot)
    end
    slots
end

# The number of fields at the end of the declaration that have a default, counted
# back from the last field to the first field without one. A positional constructor
# can leave out these fields.
function _get_cell_struct_trailing_default_count(plan::CellStructPlan)
    trailing = 0
    for field_name in Iterators.reverse(plan.field_names)
        haskey(plan.defaults, field_name) || break
        trailing += 1
    end
    trailing
end

"""
    get_cell_struct_required_count(plan) -> Int

The number of fields that a positional constructor must get: every field before
the run of fields with a default at the end of the declaration.

Use it to know the smallest arity of a positional constructor of your struct. An
arity of zero has the signature of the keyword constructor.

# Example

    plan = make_cell_struct_plan(:(struct Point; x::Int; y::Int = 0; end))
    get_cell_struct_required_count(plan)            # 1

See also `build_cell_struct_positional_constructors`, which builds a constructor
for each arity from this count to one less than the number of fields.
"""
get_cell_struct_required_count(plan::CellStructPlan) =
    length(plan.field_names) - _get_cell_struct_trailing_default_count(plan)
