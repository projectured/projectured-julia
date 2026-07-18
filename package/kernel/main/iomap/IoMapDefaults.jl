# Fragment of `IoMapModule` — the default accessor implementations and the
# concrete IO maps. The `IoMap` supertype and the accessor generics come from
# `IoMapInterface.jl`, already in scope.

# The field convention every IoMap keeps unless it says otherwise: it stores the
# `projection` that produced it and the `input`/`output` it maps between under
# those names. Read with `getfield`, not property access, so the accessor yields
# the stored slot for a plain struct (`SimpleIoMap`) and an `@iomap` cell-struct
# alike — property access on the latter would unwrap the Cell. An IoMap that
# stores a correspondence differently overrides the accessor it changes.
get_iomap_projection(iomap::IoMap) = getfield(iomap, :projection)
get_iomap_input(iomap::IoMap) = getfield(iomap, :input)
get_iomap_output(iomap::IoMap) = getfield(iomap, :output)

"""
    SimpleIoMap(projection, input, output)

Generic IO map for projections with a strict positional contract between input
and output elements — the reader reconstructs the mapping from the structure
alone, with no extra stored data. Specialised projections define their own
`{ProjectionName}IoMap` struct instead.
"""
struct SimpleIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
end

"""
    ChildrenIoMap(projection, input, output, child_iomaps)

IoMap for projections whose output has recursively projected children;
`child_iomaps` is a `Cell` holding a vector of child IoMaps. Storing them lets
the reference mappers and the reader recurse in lockstep with the printer: peel
the one step the projection owns, look the child up here, and delegate the tail
to that child's own mapper — which keeps the projection independent of the
domains its children belong to. A projection with a strict positional contract
and no recursion uses `SimpleIoMap`.
"""
struct ChildrenIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    child_iomaps::Cell
end

"""
    ContentIoMap(projection, input, output, inner_iomap)

IoMap for projections that wrap a single inner projection result; `inner_iomap`
holds the IoMap of the projected content.
"""
struct ContentIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
end

"""
    @iomap struct T ... end

Annotate an IoMap struct whose `::Cell` fields should be transparent: `obj.field`
reads the Cell value, `obj.field = val` writes it, and raw Cells stay reachable
via `getfield(obj, :field)`. Fields may carry `@kwdef`-style defaults
(`field::T = value`); when at least one is present, a keyword constructor is
generated alongside the positional auto-wrapping one.

This is `@cell_struct` plus one default: a struct without an explicit supertype
gets `<: IoMap` (injected as `:IoMap`, resolved in the caller's `esc`'d scope).
"""
macro iomap(args...)
    default, structdef = cell_struct_macro_default(args)
    structdef.head === :struct || error("@iomap expects a struct definition")
    name_expr = structdef.args[2]
    if !(name_expr isa Expr && name_expr.head === :(<:))
        structdef.args[2] = Expr(:(<:), name_expr, :IoMap)
    end
    return esc(cell_struct_exprs(structdef; default = default))
end
