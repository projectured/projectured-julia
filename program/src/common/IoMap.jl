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
    for (i, ex) in enumerate(body.args)
        if ex isa Symbol
            push!(cell_fields, ex)
            body.args[i] = :($(ex)::Cell)
        elseif ex isa Expr && ex.head === :(::) && length(ex.args) == 2
            push!(cell_fields, ex.args[1])
            ex.args[2] = :Cell
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

    # Replace the default inner constructor with one that auto-wraps
    # non-Cell values into Cell for Cell-typed fields.
    if !isempty(all_fields)
        arg_names = [gensym(f[1]) for f in all_fields]
        new_args = map(enumerate(all_fields)) do (i, (fname, ftype))
            a = arg_names[i]
            fname in cell_set ? :($a isa Cell ? $a : Cell($a)) : a
        end
        ctor = :(function $(struct_name)($(arg_names...))
            $(Expr(:call, :new, new_args...))
        end)
        push!(body.args, ctor)
    end

    # Build if-elseif chain for getproperty
    get_body = :(getfield(obj, name))
    for fname in reverse(cell_fields)
        get_body = Expr(:if, :(name === $(QuoteNode(fname))),
                        :(return getfield(obj, $(QuoteNode(fname)))[]),
                        get_body)
    end
    getprop = :(function Base.getproperty(obj::$(struct_name), name::Symbol)
        $get_body
    end)

    # Build if-elseif chain for setproperty!
    set_body = :(setfield!(obj, name, val))
    for fname in reverse(cell_fields)
        set_body = Expr(:if, :(name === $(QuoteNode(fname))),
                        :(return getfield(obj, $(QuoteNode(fname)))[] = val),
                        set_body)
    end
    setprop = :(function Base.setproperty!(obj::$(struct_name), name::Symbol, val)
        $set_body
    end)

    return esc(Expr(:block, :(Base.@__doc__ $structdef), getprop, setprop))
end

end # module
