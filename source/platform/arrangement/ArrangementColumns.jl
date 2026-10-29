# Fragment of `ArrangementModule` — what the header of a column of a table shows
# and writes in the entry of its place: the filter text of the column, its sort
# key, and the entry itself, found from the printer context of the table.

# ── The place of a table ─────────────────────────────────────────────────────

# The arrangement in `context`, and the path of the place that prints there below
# the document of the arrangement, as `(arrangement, relative)`; `nothing` when
# the place prints outside an arrangement.
function _find_printed_place(context)
    arrangement = get_property(context, :arrangement, nothing)
    arrangement === nothing && return nothing
    relative = _find_relative_reference(arrangement.base[], context.reference[])
    relative === nothing ? nothing : (arrangement, relative)
end

"""
    is_arranged_place(context) -> Bool

Whether the document that prints at `context` prints inside an arrangement, below
its document, so that it can have an entry.

Use it to decide whether a table draws the header of a filter and a sort or a
plain header.

See also `find_arranged_entry`.
"""
is_arranged_place(context) = context !== nothing && _find_printed_place(context) !== nothing

"""
    find_arranged_entry(context) -> ArrangementEntry or nothing

The entry of the arrangement in `context` that arranges the place where the
document prints: the same entry that the dispatch (`find_arranged_projection`)
chose for the collection. The items of the place print below the steps that a
stage of its chain puts above them (`get_arranged_wrap_steps`), so the place is
the source of the pick that has this path. `nothing` when the place prints
outside an arrangement or has no entry.

Use it from the printer of the items of a collection, to read the filter and the
sort that arrange them.

See also `is_arranged_place`.
"""
function find_arranged_entry(context)
    found = _find_printed_place(context)
    found === nothing && return nothing
    (arrangement, relative) = found
    picks = get_property(context, :arranged_picks, Any[])
    own = findlast(pick -> pick.paths[].place == relative, picks)
    if own !== nothing
        relative = picks[own].paths[].source
        picks = picks[1:(own - 1)]
    end
    relative = _find_source_reference(relative, picks)
    entries = arrangement.arrangement.entries
    something(_find_entry_at(entries, relative, Reference), _find_entry_at(entries, relative, AbstractVector),
              Some(nothing))
end

# ── The filter of a column ───────────────────────────────────────────────────

# The first filter of `entry`, or `nothing`.
function _find_first_filter(entry)
    entry === nothing && return nothing
    for description in entry.projections
        description isa ArrangementFilter && return description
    end
    nothing
end

# Whether the key of a condition is `key`, a path made by `_make_key`.
_is_column_key(condition_key, key) = condition_key isa Reference && strip_reference_types(condition_key) == key

# The place in `conditions` of the first condition on `key`, or `nothing`.
_find_column_condition(conditions, key) =
    findfirst(condition -> _is_column_key(condition.key, key), collect(conditions))

# The filter text that says `condition`: the text of a `:matches` condition, and
# for another operator the text of its form in the language of a filter.
function _get_condition_filter_text(condition)
    operator, value = condition.operator, condition.value
    operator === :matches && return string(value)
    operator === :contains && return string(value)
    operator === :equal && return "= " * _get_listed_value_text(value)
    operator === :not_equal && return "!= " * _get_listed_value_text(value)
    prefix = operator === :less ? "<" : operator === :greater ? ">" : operator === :at_most ? "<=" : ">="
    prefix * " " * string(value)
end

"""
    find_column_filter_text(entry, name) -> String

The filter text of the column `name` in the first filter of `entry`: the value of
a `:matches` condition on that column, or the text of the form that another
operator says (`= v`, `!= v`, `< v`, `> v`, `<= v`, `>= v`, and the text of
`:contains`). The empty text when `entry` is `nothing`, has no filter, or the
filter has no condition on the column.

Use it to fill the filter field under the header of a column.

# Example

    find_column_filter_text(entry, "status")    # "= failed, error"

See also `make_column_filter`.
"""
function find_column_filter_text(entry, name::String)
    filter = _find_first_filter(entry)
    filter === nothing && return ""
    conditions = collect(filter.conditions)
    place = _find_column_condition(conditions, _make_key(name))
    place === nothing ? "" : _get_condition_filter_text(conditions[place])
end

"""
    make_column_filter(entry, name, text) -> ArrangementFilter

The first filter of `entry` with the condition on the column `name` made a
`:matches` condition of `text`: in the place of the condition of that column, or
after the others when the column has none. An empty `text` takes the condition of
the column away. The other conditions stay. A filter with no condition is the
empty filter, which `ArrangeCollectionOperation` takes away.

Use it to write the edit of a filter field under the header of a column.

# Example

    ArrangeCollectionOperation(EmptyReference(), make_column_filter(entry, "status", "= failed"))

See also `find_column_filter_text`.
"""
function make_column_filter(entry, name::String, text::AbstractString)
    old = _find_first_filter(entry)
    conditions = old === nothing ? Any[] : Any[condition for condition in old.conditions]
    key = _make_key(name)
    place = _find_column_condition(conditions, key)
    if isempty(text)
        place === nothing || deleteat!(conditions, place)
    else
        condition = ArrangementCondition(key, :matches, String(text))
        place === nothing ? push!(conditions, condition) : (conditions[place] = condition)
    end
    ArrangementFilter(conditions)
end

# ── The sort of a column ─────────────────────────────────────────────────────

# The name of a column that `key` stands for: the field names of the path with
# dots, which `_make_key` reads back.
function _get_key_name(key)
    key isa Reference || return string(key)
    steps = get_reference_steps(strip_reference_types(key))
    all(step -> step isa FieldReferenceStep, steps) ? join((step.name for step in steps), '.') : string(key)
end

# The first sort of `entry`, or `nothing`.
function _find_first_sort(entry)
    entry === nothing && return nothing
    for description in entry.projections
        description isa ArrangementSort && return description
    end
    nothing
end

"""
    get_column_sort_keys(entry) -> Vector{Tuple{String,Bool}}

The keys of the first sort of `entry` as `(column, descending)` pairs in the order
of the sort; none when `entry` is `nothing` or has no sort.

Use it to draw the sort glyph of the header of each column, and to compute the
keys after a click on it (`compute_clicked_sort_keys`).

See also `make_column_sort`.
"""
function get_column_sort_keys(entry)
    sort = _find_first_sort(entry)
    sort === nothing && return Tuple{String,Bool}[]
    Tuple{String,Bool}[(_get_key_name(key.key), key.direction === :descending) for key in sort.keys]
end

"""
    make_column_sort(entry, keys) -> ArrangementSort

A sort of the `keys`, `(column, descending)` pairs. A key of a column that the first
sort of `entry` already sorts keeps its path. No key is the empty sort, which
`ArrangeCollectionOperation` takes away.

Use it to write the edit of a click on the sort glyph of a header.

# Example

    ArrangeCollectionOperation(EmptyReference(), make_column_sort(entry, [("delay", true)]))

See also `get_column_sort_keys`.
"""
function make_column_sort(entry, keys)
    old = _find_first_sort(entry)
    known = old === nothing ? Dict{String,Any}() :
            Dict{String,Any}(_get_key_name(key.key) => key.key for key in old.keys)
    ArrangementSort(Any[ArrangementSortKey(get(() -> _make_key(name), known, name),
                                           descending ? :descending : :ascending)
                        for (name, descending) in keys])
end

# ── The values of a column ───────────────────────────────────────────────────

"""
    collect_column_values(items, name) -> Vector{Any}

The value of the column `name` in each of `items`, as a filter reads it: the value
at the key of the column (`find_arrangement_key_value`), and `missing` for an item
that has none.

Use it to list the values of a column in a dialog, over every item of a collection.

See also `compute_value_counts`.
"""
function collect_column_values(items, name::String)
    key = _make_key(name)
    Any[something(find_arrangement_key_value(item, key), missing) for item in items]
end
