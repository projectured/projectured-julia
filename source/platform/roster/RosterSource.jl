# Fragment of `RosterModule` — the sources that the roster slice gives itself:
# the items of a collection, the items inside the items of another source, and
# the records of a store that a slice registers under a name. A slice that owns
# what a source reads adds its own source in its own files, as the slice `pane`
# adds the documents of the tabs of a window.

"""
    CollectionItems(collection)

The items of a collection inside a document: `collection` is a `Reference` from
the document of the window that shows the roster, or the collection itself. The
roster follows the collection: an item that comes in gets a row, and the row of
an item that goes out goes.

Use it to give a roster the items of a collection in a document.

# Example

    Roster(CollectionItems(@reference(results)); columns = ["name", "status"])

See also `Roster` and `show_roster!`.
"""
struct CollectionItems
    collection::Any
end

collect_roster_parts(source::CollectionItems, link) = Any[source]

# A source is data, so a file that keeps a roster writes its source.
is_pred_constructible(::Type{CollectionItems}) = true

# Each item of a collection at a reference has its place there: the reference and
# its index, which the walk of the collection knows. A collection given as itself
# has no place in the link.
function collect_roster_items(source::CollectionItems, link, part)
    reference = source.collection
    collection = reference isa Reference ? try_evaluate_reference(link, reference, nothing) : reference
    collection === nothing && return RosterItem[]
    reference isa Reference || return RosterItem[RosterItem(item) for item in collection]
    RosterItem[RosterItem(item, nothing, extend_reference(reference, ElementReferenceStep(j)))
               for (j, item) in enumerate(collection)]
end

"""
    ItemsWithin(source, type)

The documents of `type` inside each item of `source`, at any depth. Each item of
`source` is one part, and the inside of each document that it finds is a part of
its own ([`get_roster_item_inside`](@ref)): the search of a part stops at each
document of `type` and reads nothing inside it. So a change inside one document
gathers the documents inside that document again, and of no other. The row of
each such document holds the item of `source` that holds it, which the key
`within` names.

Use it to give a roster the documents of one type that lie inside other items.

# Example

    # every call in the files of the tabs, each with its file
    Roster(ItemsWithin(TabDocuments(FileDocument), JuliaCall); columns = ["callee", "within.name"])

See also `Roster` and `TabDocuments`.
"""
struct ItemsWithin
    source::Any
    type::Type
end

get_roster_item_type(source::ItemsWithin) = source.type

is_pred_constructible(::Type{ItemsWithin}) = true

collect_roster_parts(source::ItemsWithin, link) =
    Any[entry.item for part in collect_roster_parts(source.source, link)
                   for entry in _collect_items_and_insides(source.source, link, part)]

# The items of `part` of `source` and the items inside each of them, in the order
# of a search: what a roster gathers of one part, without a cell for each inside.
function _collect_items_and_insides(source, link, part)
    found = RosterItem[]
    for entry in collect_roster_items(source, link, part)
        push!(found, entry)
        inside = get_roster_item_inside(source, entry)
        inside === nothing || append!(found, _collect_items_and_insides(source, link, inside))
    end
    found
end

# The inside of a document that `ItemsWithin` found, as a part of its own: the
# document, and the item of the outer source that holds it.
struct _ItemInside
    item::Any
    outer::Any
end

get_roster_item_inside(source::ItemsWithin, entry::RosterItem) = _ItemInside(entry.item, entry.within)

collect_roster_items(source::ItemsWithin, link, outer) =
    RosterItem[RosterItem(found, outer)
               for found in search_documents(outer, node -> node isa source.type; limit = nothing, enter_matches = false)]

# The documents inside a found document, each read up to itself. The search does
# not go back into the item of the outer source, which a document can name.
collect_roster_items(source::ItemsWithin, link, inside::_ItemInside) =
    RosterItem[RosterItem(found, inside.outer)
               for found in search_documents(inside.item, node -> node !== inside.item && node isa source.type;
                                             limit = nothing, enter_matches = false,
                                             descend = (parent, child) -> child !== inside.outer)]

# The stores that a slice registers as a source, by name. The table is filled when
# each slice loads (its `__init__`), as the rows of the natural renderer are, so a
# session that does not load a slice has no store of it.
const _ROSTER_SOURCES = Dict{Symbol, Any}()

"""
    register_roster_source!(name::Symbol, make_source; description = "") -> nothing

Offer the records of a store as a source of a roster under `name`:
`StoreRecords(name)` reads the source that `make_source(link)` makes for the
document of a window, `link`. `description` says what the records are, for
[`describe_roster_sources`](@ref). Call it from the `__init__` of the slice that
owns the store. A second registration under a name replaces the first.

# Example

    register_roster_source!(:log, link -> CollectionItems(get_session_message_log().entries);
                            description = "the lines of the log of the window")
"""
function register_roster_source!(name::Symbol, make_source; description::AbstractString = "")
    _ROSTER_SOURCES[name] = (make_source = make_source, description = String(description))
    nothing
end

"""
    get_roster_source_names() -> Vector{Symbol}

The names of the stores that the loaded slices registered as sources, in the order
of their names.
"""
get_roster_source_names() = sort!(collect(keys(_ROSTER_SOURCES)))

"""
    StoreRecords(name::Symbol)

The records of the store that a slice registered under `name`
([`register_roster_source!`](@ref)), such as `:tasks` or `:log`. A name that no
loaded slice registered is an `ArgumentError` when the roster gathers its items.

Use it to give a roster the records of a store, such as the log.

# Example

    show_roster!(StoreRecords(:log); columns = ["level", "message"])

See also `show_roster!` and `describe_roster_sources`.
"""
struct StoreRecords
    name::Symbol
end

is_pred_constructible(::Type{StoreRecords}) = true

function _find_store_source(source::StoreRecords, link)
    entry = get(_ROSTER_SOURCES, source.name, nothing)
    entry === nothing &&
        throw(ArgumentError(string("No loaded slice offers a store named :", source.name, ". The stores are: ",
                                   join((string(":", name) for name in get_roster_source_names()), ", "), ".")))
    entry.make_source(link)
end

collect_roster_parts(source::StoreRecords, link) =
    (inner = _find_store_source(source, link); Any[(inner, part) for part in collect_roster_parts(inner, link)])

collect_roster_items(source::StoreRecords, link, part) = collect_roster_items(first(part), link, last(part))
