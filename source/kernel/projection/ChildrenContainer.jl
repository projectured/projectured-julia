"""
    ChildrenContainerModule

Open generics for constructing the *children container* every
`@projection_template` rule holds. Declaring the seam here lets the kernel's
template engine build a children container without naming the concrete
element-collection type; a higher package supplies that type by registering
these generics, so the upward reference stays out of the kernel.

The `type()` seam returns the concrete container type — used by
`@projection_template`'s wiring code to emit `TypeReferenceStep(T)` markers
against the container it produces. Any children container that wants to
work with the template engine registers both the constructor methods
and the type accessor.

A registrant maps `make_children_container(::Vector)` /
`make_children_container(::Function)` onto its own sequence container and
returns that type from `get_children_container_type()`. The kernel's toy-document
tests supply a toy container to keep the seam honest.
"""
module ChildrenContainerModule

export make_children_container, get_children_container_type

"""
    make_children_container(cells_or_thunk) -> children container

Construct a children container from either a `Vector` of cells or a
`Function` (a zero-argument thunk producing the child sequence
reactively).
"""
function make_children_container end

"""
    get_children_container_type() -> Type

The concrete children container type a registrant supplies. Used by the
template engine for `TypeReferenceStep(...)` markers.
"""
function get_children_container_type end

end # module
