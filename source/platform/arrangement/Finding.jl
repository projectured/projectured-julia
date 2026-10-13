# Fragment of `ArrangementModule` — find in an arranged collection: the place of
# the selection, the caret in the field of a find, and the move of the selection
# to the next item that holds its text.

"""
    compute_shown_rows(entry, items) -> Vector{Int}

The indices in `items` of the items that the place of `entry` shows, in the order
in which they show: the rows that the filters, the sorts and the first items of
`entry` pick, one after the other, as the chain of the entry picks them. A group
shows groups and not items, so the picks stop at a group, and the answer is the
items that the group reads.
"""
function compute_shown_rows(entry, items)
    rows = collect(1:length(items))
    for description in entry.projections
        description isa ArrangementGroup && break
        picked = _compute_description_rows(description, Any[items[r] for r in rows])
        picked === nothing || (rows = rows[picked])
    end
    rows
end

_compute_description_rows(filter::ArrangementFilter, items) = compute_filter_rows(filter, items)
_compute_description_rows(sort::ArrangementSort, items) = compute_sort_rows(sort, items)
_compute_description_rows(first::ArrangementFirst, items) = collect(1:min(max(first.count, 0), length(items)))
_compute_description_rows(description, items) = nothing

"""
    make_field_caret_reference(entry, place, i, steps, position) -> Reference

The caret at `position` in the text of a field of the bar of `entry`: the
introduced step of the bar, whose path in the layout of the bar goes through the
entry to its `i`-th description and then by `steps` to the text, such as
`(FieldReferenceStep("text"),)` for a find. The path is relative to `place`, the
collection of `entry`.
"""
function make_field_caret_reference(entry, place, i::Int, steps::Tuple, position::Int)
    output = extend_reference(EmptyReference(), FieldReferenceStep("children"), ElementReferenceStep(1),
                              FieldReferenceStep("entry"), FieldReferenceStep("projections"),
                              ElementReferenceStep(i), steps..., RangeReferenceStep(position, position))
    make_introduced_reference(ArrangementBarProjection(entry), place, output)
end

"""
    find_arranged_place(arrangement) -> NamedTuple or nothing

Where the selection of `arrangement` is, for a command of find: `(at, index,
entry)`, the path of the collection in the document, the index in the source of
the item that holds the selection or `nothing`, and the entry at `at` or
`nothing`. A caret in a field of the bar of an entry is at the place of that
entry. `nothing` when the selection is in no collection.
"""
function find_arranged_place(arrangement::ArrangementDocument)
    selection = get_selection(arrangement)
    selection isa Reference || return nothing
    rest = @reference_case strip_reference_types(selection) begin
        document.rest... => rest
        __ => nothing
    end
    rest === nothing && return nothing
    steps = collect(get_reference_steps(rest))
    bar = findfirst(step -> step isa ProjectionReferenceStep && step.projection isa ArrangementBarProjection, steps)
    bar === nothing || return (at = extend_reference(EmptyReference(), steps[1:bar - 1]...), index = nothing,
                               entry = steps[bar].projection.entry)
    item = find_arranged_item(arrangement.document, rest)
    item === nothing && return nothing
    (at = item.at, index = item.index, entry = _find_entry_at(arrangement.entries, item.at, Reference))
end

"""
    is_in_find_field(arrangement) -> Bool

Whether the caret of `arrangement` is in the field of a find, where Return moves
to the next item that holds its text.
"""
function is_in_find_field(arrangement::ArrangementDocument)
    selection = get_selection(arrangement)
    selection isa Reference || return false
    for step in get_reference_steps(strip_reference_types(selection))
        (step isa ProjectionReferenceStep && step.projection isa ArrangementBarProjection) || continue
        entry = step.projection.entry
        return @reference_case strip_reference_types(step.output_path) begin
            children[1].entry.projections[i].text.rest... =>
                1 <= i <= length(entry.projections) && entry.projections[i] isa ArrangementFind
            __ => false
        end
    end
    false
end

"""
    make_find_field_selection(arrangement) -> Operation or nothing

The answer to Ctrl+F in `arrangement`: the caret at the end of the text of the
find of the collection that holds the selection. When the entry of the
collection has no find, the edit that adds one comes first, and when the
collection has no entry, the edit that adds the entry. `nothing` when the
selection is in no collection.
"""
function make_find_field_selection(arrangement::ArrangementDocument)
    place = find_arranged_place(arrangement)
    place === nothing && return nothing
    collection = try_evaluate_reference(arrangement.document, place.at, nothing)
    collection === nothing && return nothing
    caret(entry, i, position) =
        ReplaceSelectionOperation(concat_references(_make_document_reference(place.at),
                                                    make_field_caret_reference(entry, collection, i, _FIND_TEXT, position)))
    entry = place.entry
    if entry === nothing
        entry = ArrangementEntry(place.at, Any[ArrangementFind("")])
        n = length(arrangement.entries)
        return CompoundOperation(Any[_make_splice(arrangement, "entries", n, n, Any[entry]), caret(entry, 1, 0)])
    end
    i = findfirst(description -> description isa ArrangementFind, collect(entry.projections))
    i === nothing || return caret(entry, i, length(string(entry.projections[i].text)))
    n = length(entry.projections)
    CompoundOperation(Any[_make_splice(entry, "projections", n, n, Any[ArrangementFind("")]), caret(entry, n + 1, 0)])
end

"""
    make_first_find(document, at) -> (ArrangementDocument, Reference)

The first arrangement of `document`, which nobody arranged yet, for Ctrl+F in the
collection at `at`: one entry with an empty find, and the caret in its field,
relative to the arrangement. The holder of `document` puts the arrangement in its
place and then the caret.
"""
function make_first_find(document, at::Reference)
    entry = ArrangementEntry(strip_reference_types(at), Any[ArrangementFind("")])
    collection = try_evaluate_reference(document, at, nothing)
    (ArrangementDocument(document, [entry]),
     concat_references(_make_document_reference(at), make_field_caret_reference(entry, collection, 1, _FIND_TEXT, 0)))
end

"""
    make_find_move(arrangement, backward) -> Operation or nothing

The answer to F3, or to Shift+F3 with `backward`: the selection of the next item,
or the previous one, of the collection that holds the selection, in the order in
which the items show, where any value contains the text of the find of its entry.
After the last item the move goes on from the first. `nothing` when the entry has
no find, its text is empty, or no item holds it.
"""
function make_find_move(arrangement::ArrangementDocument, backward::Bool)
    place = find_arranged_place(arrangement)
    (place === nothing || place.entry === nothing) && return nothing
    i = findfirst(description -> description isa ArrangementFind, collect(place.entry.projections))
    i === nothing && return nothing
    text = string(place.entry.projections[i].text)
    isempty(text) && return nothing
    items = try_evaluate_reference(arrangement.document, place.at, nothing)
    items === nothing && return nothing
    shown = compute_shown_rows(place.entry, items)
    n = length(shown)
    condition = ArrangementCondition(nothing, :contains, text)
    start = place.index === nothing ? nothing : findfirst(==(place.index), shown)
    for step in 1:n
        j = start === nothing ? (backward ? n + 1 - step : step) : mod1(start + (backward ? -step : step), n)
        is_condition_holding(condition, items[shown[j]]) || continue
        return ReplaceSelectionOperation(extend_reference(_make_document_reference(place.at),
                                                          ElementReferenceStep(shown[j])))
    end
    nothing
end

# The steps from a find to its text.
const _FIND_TEXT = (FieldReferenceStep("text"),)

# The path in an arrangement of the path `at` in its document.
_make_document_reference(at::Reference) =
    extend_reference(EmptyReference(), FieldReferenceStep("document"), get_reference_steps(at)...)
