# Fragment of `RosterModule` — the contract of the slice: the generics that a
# source of items and a kind of item answer, with no body. A slice that owns a
# kind of item or a store adds methods to them, and the roster slice names none
# of those slices. The fallback behaviours sit in `RosterDefaults.jl`.

"""
    collect_roster_parts(source, link) -> Vector

The parts of the items of `source`, each an object that names one part, such as
a tab of a window or a file that holds items. The roster keeps one computed cell
for each part, so a change inside one part gathers the items of that part again
and of no other ([`collect_roster_items`](@ref)). `link` is the document of the
window that shows the roster.

It runs inside a computation, so it reads cells, and the parts follow them. It
must read only what says which parts there are, such as the tabs of a window,
and not what is inside a part.

There is no default method: a source that has no parts is a bug, not an empty
roster.
"""
function collect_roster_parts end

"""
    collect_roster_items(source, link, part) -> Vector{RosterItem}

The items of one part of `source`, which [`collect_roster_parts`](@ref) gave,
each with the item of an outer source that holds it. It runs inside the
computation of the part, so it reads cells, and the part follows them.

There is no default method, for the reason of `collect_roster_parts`.
"""
function collect_roster_items end

"""
    get_roster_item_inside(source, entry::RosterItem) -> part or nothing

The inside of the item of `entry` as a part of `source` of its own, or `nothing`
when `source` gathers nothing inside its items. The roster keeps one computed
cell for the inside of each item, by the identity of the item, which
[`collect_roster_items`](@ref) of that part fills. So a source that finds items
inside items does not read the inside of an item where it finds the item, and a
change inside one item gathers the inside of that item again, and of no other.
The default is `nothing`.
"""
function get_roster_item_inside end

"""
    get_roster_item_type(source) -> Type

The type of the items of `source`, which [`describe_item_facets`](@ref) reads to
say which facets a roster of `source` has. The default is `Any`.
"""
function get_roster_item_type end

"""
    get_item_facets(type::Type) -> Vector{Pair{String,String}}

The facets that the type `type` itself declares, each as its name and the words
that say what it is. A facet is a value of an item that a roster can show,
filter, sort and group by, which the slice of the type computes
([`compute_item_facet`](@ref)), such as the folder of a file.

Add a method for the exact type that declares the facets. A roster reads the
facets of the type of an item and of each of its supertypes, so a facet of an
abstract type is a facet of each type below it. A facet must not have the name
of a field of the type, because a key names either. The default declares none.
"""
function get_item_facets end

"""
    compute_item_facet(item, name::Val) -> Any

The value of the facet `name` of `item`. It runs inside a computation of the
roster, so it reads cells, and it must be pure: it is a function of the cells that
it reads. A type that declares a facet ([`get_item_facets`](@ref)) adds a method
for its name, such as `compute_item_facet(file::FileDocument, ::Val{:folder})`.
"""
function compute_item_facet end

"""
    make_item_facet_operation(item, name::Val, value) -> Operation or nothing

The edit that gives the facet `name` of `item` the value `value`, as an
operation, or `nothing` when the facet takes no edit. The default answers
`nothing`, so a facet is read only unless its slice gives the edit.
"""
function make_item_facet_operation end
