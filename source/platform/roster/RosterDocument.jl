# Fragment of `RosterModule` — the documents of a roster: the roster itself, its
# rows, the value of a column of a row, and the key of a row in an arrangement.

"""
    RosterItem(item, within = nothing)

One item that a source of a roster gives, and the item of an outer source that
holds it, or `nothing`. `ItemsWithin` gives the file of each call it finds, so a
row of a call can show its file.
"""
struct RosterItem
    item::Any
    within::Any
end

RosterItem(item) = RosterItem(item, nothing)

"""
    RosterRow

One row of a roster: its `item`, the item of the outer source that holds it
(`within`), the keys of the columns (`columns`), and one computed cell for each
column (`values`). A value cell reads the item, so it computes again only when
what it reads of its item changes, and a change of one item computes no other
row. [`make_roster_row`](@ref) makes one.

In an arrangement, a key of a row is a key of a column: a filter or a sort reads
the value cell of that column ([`find_arrangement_key_value`](@ref)).
"""
@document struct RosterRow
    item::Any
    within::Any
    columns::Any
    values::Any
end

"""
    make_roster_row(item, within, columns) -> RosterRow

The row of `item`, held by `within`, with one value cell for each key of
`columns`, which [`compute_roster_value`](@ref) computes.
"""
function make_roster_row(item, within, columns)
    row = RosterRow(Cell(item), Cell(within), Cell(columns), Cell(nothing), Cell(nothing))
    row.values = CellVector(Cell[Cell(Computation(() -> compute_roster_value(row, key))) for key in columns])
    row
end

"""
    compute_roster_value(row, key) -> Any

The value of the column `key` of `row`. A key is names with dots between them.
`within` names the item of the outer source, and the names after it a key of that
item. A first name that is a facet of the type of the item
([`collect_item_facets`](@ref)) names the value of the facet, and the names after
it a path inside that value. Any other key is a path of fields inside the item.
A path that reaches nothing gives `nothing`.
"""
function compute_roster_value(row::RosterRow, key::AbstractString)
    names = split(key, '.')
    String(names[1]) == "within" && return _compute_key_value(row.within, names, 2)
    _compute_key_value(row.item, names, 1)
end

# The value at the key `names[from:end]` of `item`: a facet and a path inside it,
# or a path of fields.
function _compute_key_value(item, names, from::Int)
    (from > length(names) || item === nothing) && return item
    head = String(names[from])
    _has_item_facet(typeof(item), head) &&
        return _follow_names(compute_item_facet(item, Val(Symbol(head))), names, from + 1)
    _follow_names(item, names, from)
end

# The value at the names `names[from:end]` inside `value`, a path of fields.
function _follow_names(value, names, from::Int)
    from > length(names) && return value
    value === nothing && return nothing
    path = extend_reference(EmptyReference(), (FieldReferenceStep(String(name)) for name in names[from:end])...)
    try_evaluate_reference(value, path, nothing)
end

"""
    collect_item_facets(type::Type) -> Vector{Pair{String,String}}

The facets of the items of `type`: those that `type` declares and those that each
of its supertypes declares ([`get_item_facets`](@ref)), each as its name and the
words that say what it is. A field of `type` wins over a facet of the same name
that a supertype declares, so a key names the field. A facet that `type` itself
declares with the name of one of its fields is an `ArgumentError`, because a key
could not name it.
"""
function collect_item_facets(type::Type)
    facets = Pair{String,String}[]
    fields = _get_own_field_names(type)
    current = type
    while current !== nothing
        for declaring in _get_declaring_types(current)
            for facet in get_item_facets(declaring)
                if Symbol(first(facet)) in fields
                    current === type &&
                        throw(ArgumentError(string("The facet \"", first(facet), "\" of ", type,
                                                   " has the name of one of its fields, so a key can not name it.")))
                    continue
                end
                any(f -> first(f) == first(facet), facets) || push!(facets, facet)
            end
        end
        current = _find_supertype(current)
    end
    facets
end

# The names of the fields of a type that has fields, and none for any other.
function _get_own_field_names(type::Type)
    unwrapped = Base.unwrap_unionall(type)
    (unwrapped isa DataType && !isabstracttype(unwrapped)) ? fieldnames(unwrapped) : ()
end

# Every document has a type, which a roster of documents of many kinds groups by.
get_item_facets(::Type{Document}) =
    ["type" => "the name of the type of the document that a person sees, through the layers that wrap it"]
compute_item_facet(document::Document, ::Val{:type}) = String(nameof(typeof(get_wrapped_document(document))))

# The types that can declare the facets of `type`: `type` itself, and the name of a
# parametric type, as `@document` makes one, whose instances are of a type with
# parameters, such as `JsonString{…}` of `JsonString`.
function _get_declaring_types(type::Type)
    unwrapped = Base.unwrap_unionall(type)
    unwrapped isa DataType || return (type,)
    wrapper = unwrapped.name.wrapper
    wrapper === type ? (type,) : (type, wrapper)
end

# The supertype of `type`, or `nothing` above `Any`.
function _find_supertype(type::Type)
    type === Any && return nothing
    unwrapped = Base.unwrap_unionall(type)
    unwrapped isa DataType ? supertype(unwrapped) : Any
end

_has_item_facet(type::Type, name::AbstractString) = any(facet -> first(facet) == name, collect_item_facets(type))

# A key of an arrangement as the key of a column: its names with dots between
# them, or `nothing` for a path that has a step other than a field.
function _get_key_name(key::Reference)
    steps = get_reference_steps(strip_reference_types(key))
    all(step -> step isa FieldReferenceStep, steps) || return nothing
    join((step.name for step in steps), ".")
end

function find_arrangement_key_value(row::RosterRow, key::Reference)
    key isa EmptyReference && return get_arrangement_value(row)
    name = _get_key_name(key)
    name === nothing && return get_arrangement_value(try_evaluate_reference(row, key, nothing))
    index = findfirst(==(name), row.columns)
    get_arrangement_value(index === nothing ? compute_roster_value(row, name) : row.values[index])
end

# What a row is as one value, which "any value" of a quick text reads: the value of
# each of its columns as the table shows it. So a quick text finds what a person
# sees, and does not walk into a large document that a column holds.
get_arrangement_value(row::RosterRow) = Any[_get_shown_value(value) for value in row.values]

_get_shown_value(value::PrimitiveDocument) = get_arrangement_value(value)
_get_shown_value(value::Document) = format_roster_value(value)
_get_shown_value(value) = value

"""
    format_roster_value(value) -> String

The text that a cell of a roster shows for a value that is not a document: empty
for `nothing`, the text of a string or a symbol, and `string(value)` for any
other value. A document shows its title, or the name of its type.
"""
format_roster_value(::Nothing) = ""
format_roster_value(value::AbstractString) = String(value)
format_roster_value(value::Symbol) = String(value)
format_roster_value(value::Document) = something(get_document_title(value), string(nameof(typeof(value))))
format_roster_value(value) = string(value)

"""
    Roster(source; columns = String[], title = "Roster")

A list of the members of one kind, gathered from anywhere in a session: the items
of `source`, one row for each item ([`RosterRow`](@ref)), with the columns named
by the keys of `columns`. `title` is the title of its tab.

`rows` is a `CellVector{RosterRow}` that keeps its identity: its elements compute
from the parts of the source, and the roster keeps one cell for each part and one
row for each item. So a change inside one part gathers that part again, and a row
of an item that stays keeps its cells. An item that two parts give is one row.

`link` is the document of the window that shows the roster, which a source reads,
such as the tabs of the window; `nothing` until the window links it
([`link_roster!`](@ref)), and a roster with no link has no rows. No document holds
the editor, and the link is no editor.

A filter, a sort, a group and the first items of an arrangement act on `rows` as
on any collection.
"""
@document struct Roster <: Document
    source::Any
    columns::Any
    title::String
    rows::Any
    link::Any
end

function Roster(source; columns = String[], title::AbstractString = "Roster")
    roster = Roster(Cell(source), Cell(collect(String, columns)), Cell(String(title)), Cell(nothing),
                    Cell(nothing), Cell(nothing))
    rows = CellVector{RosterRow}()
    memo = _RosterMemo(nothing, nothing, nothing, IdDict{Any,Any}(), IdDict{Any,Any}())
    set_cell_computation!(getfield(rows, :elements), () -> _compute_roster_slots(roster, memo))
    roster.rows = rows
    roster
end

get_document_title(roster::Roster) = roster.title

# The rows are the items of other places, which a walk of the documents reaches
# there, so a walk does not go into a roster.
is_walk_opaque(::Roster) = true

# A file keeps what a roster is, not what it shows: its source, its columns and
# its title. The rows are the items of other places, and the link belongs to the
# window that shows the roster, so a roster read from a file has no link until a
# window links it.
pred_arguments(roster::Roster) =
    (roster.source,), Pair{Symbol,Any}[:columns => roster.columns, :title => roster.title]
make_pred_document(::Type{<:Roster}, positional, keywords) = Roster(positional...; keywords...)

"""
    link_roster!(roster, link) -> roster

Give `roster` the document of the window that shows it, which its source reads.
`nothing` takes the link away, and the roster then has no rows.
"""
function link_roster!(roster::Roster, link)
    roster.link = link
    roster
end

# What the rows of a roster keep from one computation to the next: the cell of the
# items of each part, and the slot of the row of each item. A change of the
# source, of the columns or of the link starts them again.
mutable struct _RosterMemo
    source::Any
    columns::Any
    link::Any
    parts::IdDict{Any,Any}
    rows::IdDict{Any,Any}
end

# The slots of the rows: the parts of the source, the items of each part, and one
# row for each item, the same slot for an item that stays. The memo is a cache of
# what the computation made, so a computation that runs twice leaves the same
# rows: it holds no state that the result does not follow.
function _compute_roster_slots(roster::Roster, memo::_RosterMemo)
    link = roster.link
    source = roster.source
    columns = roster.columns
    link === nothing && return Cell[]
    if !(memo.source === source && memo.columns === columns && memo.link === link)
        memo.source, memo.columns, memo.link = source, columns, link
        memo.parts = IdDict{Any,Any}()
        memo.rows = IdDict{Any,Any}()
    end
    parts = IdDict{Any,Any}()
    rows = IdDict{Any,Any}()
    slots = Cell[]
    for part in collect_roster_parts(source, link)
        items = get(memo.parts, part, nothing)
        items === nothing && (items = Cell(Computation(() -> collect_roster_items(source, link, part))))
        parts[part] = items
        for entry in items[]
            haskey(rows, entry.item) && continue
            slot = get(memo.rows, entry.item, nothing)
            (slot === nothing || peek(getfield(peek(slot), :within)) !== entry.within) &&
                (slot = Cell(make_roster_row(entry.item, entry.within, columns)))
            rows[entry.item] = slot
            push!(slots, slot)
        end
    end
    memo.parts = parts
    memo.rows = rows
    slots
end
