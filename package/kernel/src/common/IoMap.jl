"""
    IoMapModule

Generic IO map linking a projection's input to its output. Projections
with a strict positional contract return this plain form; projections
that need richer data (e.g. character-to-coordinate tables) define their
own specialised IoMap struct alongside their projection type.
"""
module IoMapModule

import ..ReactiveModule: Cell
import ..IoMapApiModule: IoMap
# Shared Cell-struct codegen (also used by `@document`); see `common/Document.jl`.
import ..DocumentModule: _cell_autowrap_ctor, _cell_property_accessors,
                         _cell_kw_params, _cell_kwctor

export SimpleIoMap, ChildrenIoMap, ContentIoMap, @iomap

"""
    SimpleIoMap(projection, input, output)

Generic IO map returned by projections that have a strict positional contract
between input and output elements — the reader can reconstruct the mapping
from the structure alone without any additional stored data.

Specialised projections define their own IoMap struct (named
`{ProjectionName}IoMap`) in their respective modules.
"""
struct SimpleIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
end

"""
    ChildrenIoMap(projection, input, output, child_iomaps)

IoMap for projections whose output has recursively projected children.
`child_iomaps` is a Cell holding a vector of child IoMaps.

Storing the child IoMaps is what lets `map_reference_forward` /
`map_reference_backward` and `projection_read` recurse in lockstep with the
printer: they peel the one step the projection owns, look the child up here, and
delegate the tail to that child's *own* mapper. That keeps the projection
independent of the domains its children belong to (see "Mapping references when
the printer recurses" in documentation/projection-system.md). A projection with a strict
positional contract and no recursion uses `SimpleIoMap` instead.
"""
struct ChildrenIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    child_iomaps::Cell
end

"""
    ContentIoMap(projection, input, output, inner_iomap)

IoMap for projections that wrap a single inner projection result.
`inner_iomap` holds the IoMap of the projected content.
"""
struct ContentIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
end

"""
    @iomap struct T ... end

Annotate an IoMap struct whose `::Cell` fields should be transparent.
`obj.field` reads the Cell value, `obj.field = val` writes to it;
raw Cells remain accessible via `getfield(obj, :field)`.

Fields may carry `@kwdef`-style defaults (`field::T = value`). When at least one
default is present, a keyword constructor is also generated — fields with a
default are optional keywords, fields without one are required keywords —
forwarding into the positional auto-wrapping constructor.
"""
macro iomap(structdef)
    structdef.head === :struct || error("@iomap expects a struct definition")
    name_expr = structdef.args[2]
    if name_expr isa Expr && name_expr.head === :(<:)
        struct_name = name_expr.args[1]
    else
        struct_name = name_expr
        structdef.args[2] = Expr(:(<:), name_expr, :IoMap)
    end
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
            # out of the (plain) struct body and remember it for the keyword ctor.
            lhs = ex.args[1]
            fname = lhs isa Symbol ? lhs : lhs.args[1]
            push!(cell_fields, fname)
            push!(defaults, fname => ex.args[2])
            body.args[i] = :($(fname)::Cell)
        end
    end
    isempty(cell_fields) && return esc(structdef)

    cell_set = Set(cell_fields)

    # Collect all field names/types for the auto-wrapping constructor
    all_fields = Tuple{Symbol, Any}[]
    for ex in body.args
        if ex isa Symbol
            push!(all_fields, (ex, nothing))
        elseif ex isa Expr && ex.head === :(::) && length(ex.args) == 2
            push!(all_fields, (ex.args[1], ex.args[2]))
        end
    end

    # Replace the default inner constructor with one that auto-wraps non-Cell
    # values into Cell for Cell-typed fields (shared with `@document`).
    if !isempty(all_fields)
        push!(body.args,
              _cell_autowrap_ctor(struct_name, [f[1] for f in all_fields], cell_set))
    end

    # getproperty / setproperty! read/write through the Cell fields (shared).
    getprop, setprop = _cell_property_accessors(struct_name, cell_fields)

    # Keyword constructor (only when ≥1 default is declared) that forwards into
    # the positional inner ctor above, so Cell auto-wrapping is unchanged. Fields
    # without a default become required keywords, à la `Base.@kwdef`.
    extra = Any[]
    if !isempty(defaults)
        default_map = Dict(defaults)
        field_names = [f[1] for f in all_fields]
        push!(extra, _cell_kwctor(struct_name, field_names,
                                  _cell_kw_params(field_names, default_map)))
    end

    return esc(Expr(:block, :(Base.@__doc__ $structdef), getprop, setprop, extra...))
end

end # module
