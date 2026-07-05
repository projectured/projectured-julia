"""
    ChildrenContainerModule

D5 seam (kernel plan Q2, completed 2026-07-06). Open generics for
constructing the *children container* every `@projection_template` rule
holds. Before D5, `ProjectionTemplate` lived in domain and constructed
`CellVector(...)` directly (a base type imported down from the concrete
document layer); D5 dissolves that upward reference by declaring the
generics here and letting base's `Collection.jl` register the
`CellVector` implementations.

The `type()` seam returns the concrete container type — used by
`@projection_template`'s wiring code to emit `TypeReference(T)` markers
against the container it produces. Any children container that wants to
work with `ProjectionTemplate` registers both the constructor methods
and the type accessor.

Base's `document/Collection.jl` adds:

    make_children_container(cells::Vector) = CellVector(cells)
    make_children_container(thunk::Function) = CellVector(thunk)
    children_container_type() = CellVector

The kernel's toy-document tests can supply a toy container to keep the
seam honest — the pressure the plan calls out.
"""
module ChildrenContainerModule

export make_children_container, children_container_type

"""
    make_children_container(cells_or_thunk) -> children container

Construct a children container from either a `Vector` of cells or a
`Function` (a zero-argument thunk producing the child sequence
reactively). Base's Collection.jl registers `Vector`/`Function`
methods on `CellVector`.
"""
function make_children_container end

"""
    children_container_type() -> Type

The concrete children container type the current base supplies. Used by
`ProjectionTemplate` for `TypeReference(...)` markers.
"""
function children_container_type end

end # module
