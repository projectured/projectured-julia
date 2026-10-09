# Fragment of `ArrangementModule` — what the menu of a value offers: the nearest
# collection that holds the value, and the edits that filter or sort it by the
# value, of an arrangement that exists or of a first one.

"""
    find_arranged_item(document, path) -> NamedTuple or nothing

The nearest collection on `path`, a path inside `document` to a value that a
person points at: `(at, index, key, value)`, the path of the collection, the
number of the item that holds the value, the path of the value inside the item,
and the value, read with `get_arrangement_value`; `nothing` when no collection
holds it. A step that names no field and no item, such as a place inside a
text, ends the path of the value.
"""
function find_arranged_item(document, path)
    path isa Reference || return nothing
    steps = ReferenceStep[step for step in get_reference_steps(strip_reference_types(path))]
    last = findfirst(step -> !_is_item_step(step) && !(step isa FieldReferenceStep), steps)
    last === nothing || (steps = steps[1:last - 1])
    for k in length(steps) - 1:-1:0
        step = steps[k + 1]
        _is_item_step(step) || continue
        at = extend_reference(EmptyReference(), steps[1:k]...)
        collection = try_evaluate_reference(document, at, nothing)
        _is_arrangeable_collection(collection) || continue
        index = step.start + 1
        (1 <= index <= length(collection)) || continue
        key = extend_reference(EmptyReference(), steps[k + 2:end]...)
        return (at = at, index = index, key = key, value = _find_key_value(collection[index], key))
    end
    nothing
end

_is_item_step(step) = step isa RangeReferenceStep && is_element_reference_step(step)
_is_arrangeable_collection(value) = is_element_collection(value) || (value isa AbstractVector && !(value isa AbstractString))

"""
    make_arrangement_edits(arrangement, item) -> Vector{Tuple{String,Operation}}

The edits that the menu of a value offers, for `item` from
[`find_arranged_item`](@ref) inside the document of `arrangement`: show only the
items like it, hide them, sort by it either way, for a number keep the greater or
the smaller ones, a quick text field where the collection has none, and Show all
where the collection has an entry. Each edit names its own document, as an item
of a menu of a part around the part under the pointer must.
"""
function make_arrangement_edits(arrangement::ArrangementDocument, item)
    entry = _find_entry_at(arrangement.entries, item.at, Reference)
    edits = Tuple{String,Operation}[]
    for (label, condition) in _make_item_conditions(item)
        push!(edits, (label, _make_condition_edit(arrangement, entry, item.at, condition)))
    end
    for (label, key) in _make_item_sort_keys(item)
        push!(edits, (label, _make_sort_edit(arrangement, entry, item.at, key)))
    end
    _has_quick_text(entry) ||
        push!(edits, (_QUICK_TEXT_LABEL, _make_condition_edit(arrangement, entry, item.at, _make_quick_text_condition())))
    entry === nothing || push!(edits, ("Show all", make_entry_removal_edit(arrangement, entry)))
    edits
end

"""
    make_first_arrangement_edits(document, item, wrap) -> Vector{Tuple{String,Operation}}

The edits that the menu of a value offers where no arrangement is around
`document` yet: each makes the first one, an `ArrangementDocument` of `document`
with one entry at the collection of `item`, and `wrap(arrangement)` is the edit
that puts it where `document` is, made by the place that shows `document`.
"""
function make_first_arrangement_edits(document, item, wrap::Function)
    edits = Tuple{String,Operation}[]
    first_entry(description) = ArrangementDocument(document, [ArrangementEntry(item.at, Any[description])])
    for (label, condition) in _make_item_conditions(item)
        push!(edits, (label, wrap(first_entry(ArrangementFilter(Any[condition])))))
    end
    for (label, key) in _make_item_sort_keys(item)
        push!(edits, (label, wrap(first_entry(ArrangementSort(Any[key])))))
    end
    push!(edits, (_QUICK_TEXT_LABEL, wrap(first_entry(ArrangementFilter(Any[_make_quick_text_condition()])))))
    edits
end

const _QUICK_TEXT_LABEL = "Filter by text…"

# A quick text condition with no text yet, which keeps every item.
_make_quick_text_condition() = ArrangementCondition(nothing, :contains, "")

# Whether `entry` has a quick text condition.
_has_quick_text(entry) =
    entry !== nothing && any(description -> description isa ArrangementFilter &&
                                            any(is_quick_text_condition, description.conditions),
                             entry.projections)

function _make_item_conditions(item)
    conditions = Tuple{String,Any}[
        ("Show only items like this", ArrangementCondition(item.key, :equal, item.value)),
        ("Hide items like this", ArrangementCondition(item.key, :not_equal, item.value))]
    if item.value isa Real
        push!(conditions, ("Show only items greater than this", ArrangementCondition(item.key, :greater, item.value)))
        push!(conditions, ("Show only items less than this", ArrangementCondition(item.key, :less, item.value)))
    end
    conditions
end

_make_item_sort_keys(item) = Tuple{String,Any}[
    ("Sort by this, ascending", ArrangementSortKey(item.key, :ascending)),
    ("Sort by this, descending", ArrangementSortKey(item.key, :descending))]

# The edit that adds `condition`: to the filter of the entry, to a new filter at
# the start of the entry, or in a new entry.
function _make_condition_edit(arrangement, entry, at, condition)
    entry === nothing && return _make_splice(arrangement, "entries", length(arrangement.entries),
                                             length(arrangement.entries),
                                             Any[ArrangementEntry(at, Any[ArrangementFilter(Any[condition])])])
    filter = findfirst(d -> d isa ArrangementFilter, collect(entry.projections))
    filter === nothing && return _make_splice(entry, "projections", 0, 0, Any[ArrangementFilter(Any[condition])])
    description = entry.projections[filter]
    n = length(description.conditions)
    _make_splice(description, "conditions", n, n, Any[condition])
end

# The edit that sorts by `key` alone: the keys of the sort of the entry, a new
# sort at the end of the entry, or a new entry.
function _make_sort_edit(arrangement, entry, at, key)
    entry === nothing && return _make_splice(arrangement, "entries", length(arrangement.entries),
                                             length(arrangement.entries),
                                             Any[ArrangementEntry(at, Any[ArrangementSort(Any[key])])])
    sort = findfirst(d -> d isa ArrangementSort, collect(entry.projections))
    n = length(entry.projections)
    sort === nothing && return _make_splice(entry, "projections", n, n, Any[ArrangementSort(Any[key])])
    description = entry.projections[sort]
    _make_splice(description, "keys", 0, length(description.keys), Any[key])
end

# The edit of `document` that puts `items` in place of the elements
# `start + 1:stop` of its field `field`, named by `document` itself.
_make_splice(document, field::String, start::Int, stop::Int, items) =
    ReplaceReferencedValueOperation(document,
        extend_reference(EmptyReference(), FieldReferenceStep(field), RangeReferenceStep(start, stop)), items)
