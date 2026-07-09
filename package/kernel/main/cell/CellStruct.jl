# Fragment of `CellModule` — the transparent-Cell struct codegen: the
# `@cell_struct` macro, its assembler `cell_struct_exprs`, and the four
# expr-builders they compose. `cell_struct_exprs` is the composition seam a
# macro author reuses — inject a default supertype into the struct definition,
# delegate to it, and escape the result — while `@cell_struct` is the standalone
# macro over it.
#
# The symbols the builders emit (`Cell`, `new`, `getfield`, …) are spliced as
# bare names and resolve in the *caller's* scope when the calling macro escapes
# its result — a caller therefore needs `Cell` in scope, nothing else.

"""
    cell_struct_autowrap_ctor(struct_name, field_names, cell_set) -> Expr

Build the single auto-wrapping inner constructor: `T(vals...)` wrapping each
Cell-typed field's value in a `Cell` unless it already is one. `field_names`
is every field (declaration order); `cell_set` is the subset stored as Cells.
"""
function cell_struct_autowrap_ctor(struct_name, field_names, cell_set)
    arg_names = [gensym(f) for f in field_names]
    new_args = map(enumerate(field_names)) do (i, fname)
        a = arg_names[i]
        fname in cell_set ? :($a isa Cell ? $a : Cell($a)) : a
    end
    :(function $(struct_name)($(arg_names...))
        $(Expr(:call, :new, new_args...))
    end)
end

"""
    cell_struct_property_accessors(struct_name, cell_fields) -> (getprop, setprop)

Build `Base.getproperty` / `Base.setproperty!` methods that read/write through
each Cell-typed field (`obj.f` reads the cell value, `obj.f = v` writes into
it); every other field falls through to `getfield` / `setfield!`.
"""
function cell_struct_property_accessors(struct_name, cell_fields)
    get_body = :(getfield(obj, name))
    for fname in reverse(cell_fields)
        get_body = Expr(:if, :(name === $(QuoteNode(fname))),
                        :(return getfield(obj, $(QuoteNode(fname)))[]),
                        get_body)
    end
    getprop = :(function Base.getproperty(obj::$(struct_name), name::Symbol)
        $get_body
    end)

    set_body = :(setfield!(obj, name, val))
    for fname in reverse(cell_fields)
        set_body = Expr(:if, :(name === $(QuoteNode(fname))),
                        :(return getfield(obj, $(QuoteNode(fname)))[] = val),
                        set_body)
    end
    setprop = :(function Base.setproperty!(obj::$(struct_name), name::Symbol, val)
        $set_body
    end)
    (getprop, setprop)
end

"""
    cell_struct_kw_params(field_names, default_map) -> Vector

Build a keyword-constructor parameter list: a defaulted field becomes
`field = default`, an undefaulted one a required keyword `field` (à la
`Base.@kwdef`).
"""
cell_struct_kw_params(field_names, default_map) =
    [haskey(default_map, fname) ? Expr(:kw, fname, default_map[fname]) : fname
     for fname in field_names]

"""
    cell_struct_kwctor(type_name, field_names, kw_params) -> Expr

Build a keyword constructor for `type_name` forwarding into its positional
constructor, so value wrapping stays defined in exactly one place.
"""
cell_struct_kwctor(type_name, field_names, kw_params) =
    :(function $(type_name)(; $(kw_params...))
        $(Expr(:call, type_name, field_names...))
    end)

"""
    cell_struct_exprs(structdef) -> Expr

The assembler behind [`@cell_struct`](@ref): rewrite `structdef` in place so
every field is a `::Cell`, then return a block with the rewritten struct (its
auto-wrapping inner constructor appended), the transparent property accessors,
and — when at least one field declares a default — the keyword constructor.

This is the composition seam for macro authors: a macro injects its default
supertype into `structdef` and returns `esc(cell_struct_exprs(structdef))`. The
result must be escaped by the calling macro so the emitted bare names resolve at
the expansion site.
"""
function cell_struct_exprs(structdef)
    structdef isa Expr && structdef.head === :struct ||
        error("@cell_struct expects a struct definition")
    name_expr = structdef.args[2]
    struct_name = (name_expr isa Expr && name_expr.head === :(<:)) ?
        name_expr.args[1] : name_expr
    body = structdef.args[3]
    cell_fields = Symbol[]
    defaults = Pair{Symbol, Any}[]   # field => default-value expr (declaration order)
    for (i, ex) in enumerate(body.args)
        if ex isa Symbol
            push!(cell_fields, ex)
            body.args[i] = :($(ex)::Cell)
        elseif ex isa Expr && ex.head === :(::) && length(ex.args) == 2
            push!(cell_fields, ex.args[1])
            ex.args[2] = :Cell
        elseif ex isa Expr && ex.head === :(=) && length(ex.args) == 2
            # `name = v` / `name::T = v` — @kwdef-style default. Strip the default
            # out of the struct body and remember it for the keyword ctor.
            lhs = ex.args[1]
            fname = lhs isa Symbol ? lhs : lhs.args[1]
            push!(cell_fields, fname)
            push!(defaults, fname => ex.args[2])
            body.args[i] = :($(fname)::Cell)
        end
    end
    isempty(cell_fields) && return structdef

    cell_set = Set(cell_fields)

    # Collect all field names/types for the auto-wrapping constructor.
    all_fields = Tuple{Symbol, Any}[]
    for ex in body.args
        if ex isa Symbol
            push!(all_fields, (ex, nothing))
        elseif ex isa Expr && ex.head === :(::) && length(ex.args) == 2
            push!(all_fields, (ex.args[1], ex.args[2]))
        end
    end

    # Replace the default inner constructor with one that auto-wraps non-Cell
    # values into Cell for Cell-typed fields.
    if !isempty(all_fields)
        push!(body.args,
              cell_struct_autowrap_ctor(struct_name, [f[1] for f in all_fields], cell_set))
    end

    # getproperty / setproperty! read/write through the Cell fields.
    getprop, setprop = cell_struct_property_accessors(struct_name, cell_fields)

    # Keyword constructor (only when ≥1 default is declared) that forwards into
    # the positional inner ctor above, so Cell auto-wrapping is unchanged. Fields
    # without a default become required keywords, à la `Base.@kwdef`.
    extra = Any[]
    if !isempty(defaults)
        default_map = Dict(defaults)
        field_names = [f[1] for f in all_fields]
        push!(extra, cell_struct_kwctor(struct_name, field_names,
                                 cell_struct_kw_params(field_names, default_map)))
    end

    Expr(:block, :(Base.@__doc__ $structdef), getprop, setprop, extra...)
end

"""
    @cell_struct struct T [<: Super] ... end

Annotate a struct whose fields are transparent reactive `Cell`s. Every field
form — bare `f`, typed `f::T`, defaulted `f[::T] = value` — becomes a `::Cell`
field (declared value types are documentation only); the macro generates:

- an **auto-wrapping inner constructor** — `T(vals...)` wraps each non-Cell
  value in `Cell(v)`; Cells pass through unchanged;
- **transparent accessors** — `obj.f` reads the cell value, `obj.f = v`
  writes into it; raw Cells remain accessible via `getfield(obj, :f)`;
- when at least one default is present, a **keyword constructor** — fields
  with a default are optional keywords, fields without one are required
  keywords — forwarding into the positional constructor.

The struct keeps whatever supertype the definition declares (or none). A macro
that needs to compose this codegen with its own additions calls the assembler
`cell_struct_exprs` directly rather than this macro.
"""
macro cell_struct(structdef)
    esc(cell_struct_exprs(structdef))
end
