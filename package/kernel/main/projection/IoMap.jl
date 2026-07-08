"""
    IoMapModule

Generic IO map linking a projection's input to its output. Projections
with a strict positional contract return this plain form; projections
that need richer data (e.g. character-to-coordinate tables) define their
own specialised IoMap struct alongside their projection type.
"""
module IoMapModule

import ..CellModule: Cell, cell_struct_exprs
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

Storing the child IoMaps is what lets `map_reference_forward` /
`map_reference_backward` and `read_intent` recurse in lockstep with the
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

This is `@cell_struct` (the cell layer's transparent-Cell struct codegen) plus
one default: a struct without an explicit supertype gets `<: IoMap`. The
injected `:IoMap` resolves in the caller's scope (the result is `esc`'d).
"""
macro iomap(structdef)
    structdef.head === :struct || error("@iomap expects a struct definition")
    name_expr = structdef.args[2]
    if !(name_expr isa Expr && name_expr.head === :(<:))
        structdef.args[2] = Expr(:(<:), name_expr, :IoMap)
    end
    return esc(cell_struct_exprs(structdef))
end

end # module
