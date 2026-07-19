# Fragment of `IoMapModule` — the default accessor implementations and the
# concrete IO maps. The `IoMap` supertype and the accessor generics come from
# `IoMapInterface.jl`, already in scope.

"""
    @iomap struct T ... end

Annotate an IoMap struct whose `::Cell` fields should be transparent: `obj.field`
reads the Cell value, `obj.field = val` writes it, and raw Cells stay reachable
via `getfield(obj, :field)`. Fields may carry `@kwdef`-style defaults
(`field::T = value`); when at least one is present, a keyword constructor is
generated alongside the positional auto-wrapping one.

This is `@cell_struct` plus one default: a struct without an explicit supertype
gets `<: IoMap` (injected as `:IoMap`, resolved in the caller's `esc`'d scope).

An IoMap's varying fields are meant to be *computed* cells: pass `output = Cell(()
-> …)` and it re-derives reactively while the IoMap keeps its identity, so
`iomap.output` reads the current value and a change propagates without re-printing.
The transparent field is only the *vehicle* — the derivation (the thunk) is what
makes it reactive; a cell field holding an eagerly-computed value does not
re-derive. Keeping the IoMap's identity while its fields re-derive is what lets it
sit in a chain and have other projections wire to it.
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

# The field convention every IoMap keeps unless it says otherwise: it stores the
# `projection` that produced it and the `input`/`output` it maps between under
# those names. Read through property access so the accessor yields the *value* for
# a plain struct (`ChildrenIoMap`) and an `@iomap` cell-struct (`SimpleIoMap`)
# alike — an `@iomap` field unwraps its `Cell`, and a synthesized `.output` (a
# derived-output IoMap) resolves through its own `getproperty`. An IoMap that
# stores a correspondence differently overrides the accessor it changes.
get_iomap_projection(iomap::IoMap) = iomap.projection
get_iomap_input(iomap::IoMap) = iomap.input
get_iomap_output(iomap::IoMap) = iomap.output

"""
    SimpleIoMap(projection, input, output)

Generic IO map for projections with a strict positional contract between input
and output elements — the reader reconstructs the mapping from the structure
alone, with no extra stored data. Specialised projections define their own
`{ProjectionName}IoMap` struct instead. As an `@iomap` struct its `output` may be
a computed cell that re-derives reactively; `iomap.output` reads the current value
(AR-STABLE-IOMAP-IDENTITY).
"""
@iomap struct SimpleIoMap
    projection::Any
    input::Any
    output::Any
end

"""
    ChildrenIoMap(projection, input, output, child_iomaps)

IoMap for projections whose output has recursively projected children. As an
`@iomap` struct, `iomap.child_iomaps` reads the current per-child IoMap vector —
pass a computed/reconciling cell (`reconcile_child_iomaps`) so it re-derives on a
structural edit while the IoMap keeps its identity; `getfield(iomap,
:child_iomaps)` reaches the raw cell. Storing the child IoMaps lets the reference
mappers and the reader recurse in lockstep with the printer: peel the one step the
projection owns, look the child up here, and delegate the tail to that child's own
mapper — which keeps the projection independent of the domains its children belong
to. A projection with a strict positional contract and no recursion uses
`SimpleIoMap`.
"""
@iomap struct ChildrenIoMap
    projection::Any
    input::Any
    output::Any
    child_iomaps::Any
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
