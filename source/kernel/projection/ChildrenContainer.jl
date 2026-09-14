# Fragment of `ProjectionModule` — the open generics for the children container
# every `@projection_template` rule holds. Declaring the seam here lets the
# template engine build a container without naming the concrete
# element-collection type; a higher package supplies that type by registering
# `make_children_container` and `get_children_container_type`.

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
