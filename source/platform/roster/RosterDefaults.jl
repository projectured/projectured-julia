# Fragment of `RosterModule` — the fallback behaviours of the generics of
# `RosterInterface.jl` that a source or a kind of item does not have to answer.
# `collect_roster_parts`, `collect_roster_items` and `compute_item_facet` have no
# fallback on purpose: a source with no parts and a facet with no value are bugs.

# A source gathers nothing inside its items unless it says so.
get_roster_item_inside(source, entry) = nothing

# The items of a source of no stated type can be of any type.
get_roster_item_type(source) = Any

# A type declares no facet unless its slice says so.
get_item_facets(::Type) = Pair{String,String}[]

# A facet takes no edit unless its slice gives one.
make_item_facet_operation(item, name::Val, value) = nothing
