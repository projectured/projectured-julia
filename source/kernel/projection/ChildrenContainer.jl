# Fragment of `ProjectionModule` — the place of the children-container seam, which
# holds no code. `ProjectionInterface.jl` declares `make_children_container` and
# `get_children_container_type`, so the template engine builds a container without
# naming the concrete element-collection type; a higher package supplies that type
# by adding methods to the two generics.
