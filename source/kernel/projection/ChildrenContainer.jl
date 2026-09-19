# Fragment of `ProjectionModule` — the open generics for the children container
# every `@projection_template` rule holds. Declaring the seam here lets the
# template engine build a container without naming the concrete
# element-collection type; a higher package supplies that type by registering
# `make_children_container` and `get_children_container_type`.
