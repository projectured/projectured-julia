# Fragment of `CellModule` — the **struct plan**: what a macro needs to know about
# a `struct` definition before it can emit code for it, parsed once.
#
# A `struct` definition uses the same three field forms — bare `f`, typed
# `f::T`, defaulted `f[::T] = v`. The plan reads all three, strips the defaults
# out of the body (a `struct` cannot carry them), and remembers them for the
# constructors. That parse is the same wherever it is needed, so it is written
# here, once — a caller takes a `CellStructPlan` instead of re-walking the AST.
#
# The plan keeps each field's *slot* — its index in the struct body — rather than
# rebuilding the body, because the body's `LineNumberNode`s are what give a field a
# source location in errors and docs. `retype_cell_struct_fields!` overwrites the slots in
# place and leaves those nodes where they are.

"""
    CellStructPlan

The parsed form of a `struct` definition: its name, supertype, fields (names,
declared types, and the slot each occupies in the body), and the `@kwdef`-style
defaults stripped out of it.

`n_declared` and `n_programmer_defaults` record the counts **as the programmer
wrote them**, before any field is appended — a caller that appends a field needs
to tell the programmer's defaults apart from its own.
"""
struct CellStructPlan
    structdef             :: Expr
    name                  :: Symbol
    supertype             :: Any            # expr / symbol, or `nothing` if unwritten
    field_names           :: Vector{Symbol}
    field_types           :: Vector{Any}    # declared type expr, or `nothing` if untyped
    field_slots           :: Vector{Int}    # index of each field's expr in the body
    defaults              :: Dict{Symbol,Any}
    n_declared            :: Int
    n_programmer_defaults :: Int
end

"""
    cell_struct_plan(structdef) -> CellStructPlan

Parse a `struct` definition. Handles the three field forms (`f`, `f::T`,
`f[::T] = v`) and strips each default out of the body into the plan — the declared
type is kept, since it still feeds typed constructors and aliases.
"""
function cell_struct_plan(structdef)
    structdef isa Expr && structdef.head === :struct ||
        error("cell_struct_plan expects a struct definition")
    name_expr = structdef.args[2]
    has_super = name_expr isa Expr && name_expr.head === :(<:)
    name      = has_super ? name_expr.args[1] : name_expr
    supertype = has_super ? name_expr.args[2] : nothing
    body      = structdef.args[3]

    field_names = Symbol[]
    field_types = Any[]
    field_slots = Int[]
    defaults    = Pair{Symbol,Any}[]        # declaration order

    for (i, ex) in enumerate(body.args)
        if ex isa Symbol                                        # f
            fname, ftype = ex, nothing
        elseif ex isa Expr && ex.head === :(::) && length(ex.args) == 2   # f::T
            fname, ftype = ex.args[1], ex.args[2]
        elseif ex isa Expr && ex.head === :(=) && length(ex.args) == 2     # f[::T] = v
            lhs = ex.args[1]
            fname, ftype = lhs isa Symbol ? (lhs, nothing) : (lhs.args[1], lhs.args[2])
            push!(defaults, fname => ex.args[2])
        else
            continue                                            # LineNumberNode, etc.
        end
        push!(field_names, fname)
        push!(field_types, ftype)
        push!(field_slots, i)
    end

    CellStructPlan(structdef, name, supertype, field_names, field_types, field_slots,
               Dict(defaults), length(field_names), length(defaults))
end

"""
    add_cell_struct_field!(plan, name, type, default) -> CellStructPlan

Append a field the caller supplies rather than one written in the source `struct`
— it lands last, in the body and in the plan alike. The body slot is a
placeholder; `retype_cell_struct_fields!` writes the field's real cell type into it.
"""
function add_cell_struct_field!(plan::CellStructPlan, name::Symbol, type, default)
    body = plan.structdef.args[3]
    push!(body.args, :($(name)::Any))
    push!(plan.field_names, name)
    push!(plan.field_types, type)
    push!(plan.field_slots, length(body.args))
    plan.defaults[name] = default
    plan
end

"""
    retype_cell_struct_fields!(plan, cell_types) -> plan

Rewrite every field in the struct body to `name::cell_types[i]` — in place, so the
body's `LineNumberNode`s (and with them each field's source location) survive.
"""
function retype_cell_struct_fields!(plan::CellStructPlan, cell_types)
    body = plan.structdef.args[3]
    for (i, slot) in enumerate(plan.field_slots)
        body.args[slot] = :($(plan.field_names[i])::$(cell_types[i]))
    end
    plan
end

# A field's declared type may name a cell **kind** — `ImmutableCell{T}`,
# `MutableCell{T}`, `ReactiveCell{T}`, or bare `Cell` — carrying the value type as
# its parameter, or a plain value type (which means the reactive default). Detection
# is syntactic on the reserved kind names (no resolved types exist at expansion
# time); those names are reserved cell vocabulary, so the check is safe.
_cell_kind_name(s::Symbol) =
    s === :ImmutableCell ? :immutable :
    s === :MutableCell   ? :mutable   :
    (s === :ReactiveCell || s === :Cell) ? :reactive : nothing

"""
    cell_kind_of(sym) -> :reactive | :immutable | :mutable | nothing

Map a cell-kind **name** (`:ImmutableCell`, `:MutableCell`, `:ReactiveCell`, `:Cell`) to its kind,
or `nothing` when `sym` names no kind. Used to read a leading struct-level default
kind (`ImmutableCell struct …`).
"""
cell_kind_of(s::Symbol) = _cell_kind_name(s)

# `(kind, value_type, explicit)` for one declared field type (`nothing` = untyped field).
# `explicit` is true iff the type NAMES a cell kind; an unannotated (`f`) or plain-typed (`f::T`)
# field reads as `:reactive` but is NOT explicit, so a struct-level default may override it.
function _field_kind_type(ftype)
    ftype === nothing && return (:reactive, :Any, false)
    if ftype isa Symbol
        k = _cell_kind_name(ftype)
        return k === nothing ? (:reactive, ftype, false) : (k, :Any, true)
    end
    if ftype isa Expr && ftype.head === :curly && ftype.args[1] isa Symbol
        k = _cell_kind_name(ftype.args[1])
        k === nothing || return (k, length(ftype.args) ≥ 2 ? ftype.args[2] : :Any, true)
    end
    (:reactive, ftype, false)
end

"""
    cell_struct_value_types(plan) -> Vector

Each field's declared **value** type as an expr, with `Any` standing in for an
untyped field. A field that names a cell kind (`ImmutableCell{T}`, …) contributes
its parameter `T` — the kind wrapper is stripped, since this is the value-type
vocabulary the typed (immutable / mutable) constructors and aliases are written in.
"""
cell_struct_value_types(plan::CellStructPlan) =
    Any[_field_kind_type(t)[2] for t in plan.field_types]

"""
    cell_struct_field_kinds(plan; default = :reactive) -> Vector{Symbol}

Each field's cell kind — `:reactive` / `:immutable` / `:mutable`. A field that **names** a kind
(`f::ImmutableCell{T}`) keeps it; every other field (bare `f`, plain `f::T`) takes `default`, the
struct-level default the caller passes from a leading kind argument. `default = :reactive` (no
leading kind) leaves the result exactly as before.
"""
function cell_struct_field_kinds(plan::CellStructPlan; default::Symbol = :reactive)
    kinds = Symbol[]
    for t in plan.field_types
        k, _, explicit = _field_kind_type(t)
        push!(kinds, explicit ? k : default)
    end
    kinds
end

"""
    cell_struct_trailing_default_count(plan) -> Int

How many fields at the **end** of the declaration run all the way to the last one
with a default — the suffix a positional constructor may omit.
"""
function cell_struct_trailing_default_count(plan::CellStructPlan)
    n = 0
    for fname in Iterators.reverse(plan.field_names)
        haskey(plan.defaults, fname) || break
        n += 1
    end
    n
end

"""
    cell_struct_required_count(plan) -> Int

How many leading fields a positional constructor must be given: every field before
the trailing run of defaulted ones.
"""
cell_struct_required_count(plan::CellStructPlan) = length(plan.field_names) - cell_struct_trailing_default_count(plan)

"""
    cell_struct_positional_ctors(plan, target_name; each_arity = _ -> ()) -> Vector

**Rule Y** — the positional analog of `@kwdef`: for a trailing run of defaulted
fields, constructors `T(f₁..f_k)` that fill the omitted suffix with its defaults.

Emitted only when at least one leading field is *required* (`cell_struct_required_count ≥ 1`),
so a zero-argument form is never generated — that signature belongs to the keyword
constructor, and a struct whose fields all default is left to it.

`each_arity(k)` is called after the arity-`k` constructor and its result appended,
so a caller can emit a companion constructor for the same arity. A caller whose
companion *only* makes sense next to a Rule Y form gets the `cell_struct_required_count ≥ 1`
gate for free this way, rather than re-deriving it and getting it wrong.
"""
function cell_struct_positional_ctors(plan::CellStructPlan, target_name; each_arity = _ -> ())
    n   = length(plan.field_names)
    req = cell_struct_required_count(plan)
    ctors = Any[]
    req ≥ 1 || return ctors
    for k in req:(n - 1)
        kept   = plan.field_names[1:k]
        filled = Any[plan.defaults[plan.field_names[j]] for j in (k + 1):n]
        push!(ctors, :($(target_name)($(kept...)) =
            $(Expr(:call, target_name, kept..., filled...))))
        append!(ctors, each_arity(k))
    end
    ctors
end
