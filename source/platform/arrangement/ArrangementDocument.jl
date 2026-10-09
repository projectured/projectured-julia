# Fragment of `ArrangementModule` — the documents of an arrangement: a document
# that a person arranged, and what the person placed at its parts.

"""
    ArrangementDocument(document, entries)

A `document` and what a person placed at its parts. Each `ArrangementEntry`
names a place in `document` and the projections that show what is there, such
as a filter and a sort of a collection. The entries are no part of the data: no
entry changes `document`, and a save of `document` saves no entry.

The first entry that a person makes puts an `ArrangementDocument` around the
document that a place shows, and the removal of the last entry takes it away.

# Example

    ArrangementDocument(runs, [ArrangementEntry(@reference(results), Any[filter])])
"""
@document struct ArrangementDocument
    document::Any
    entries::CellVector
end

# The title of an arrangement is the title of the document that it holds.
get_document_title(arrangement::ArrangementDocument) =
    something(get_document_title(arrangement.document), "Arrangement")

"""
    ArrangementEntry(at, projections)

A place in the document of an `ArrangementDocument`, `at`, a path from the root
of that document, and the projections that a person placed there, in the order
of their chain. Each element of `projections` is a document that
[`make_arrangement_projection`](@ref) turns into a projection, so an entry is
saved, copied and undone as any document.
"""
@document struct ArrangementEntry
    at::Any
    projections::CellVector
end

"""
    ArrangementChips(entry, shown, total)

What the bar of a place shows: the chips of `entry`, a chip for each condition of
a filter and each key of a sort, and the count of the items, `shown` of `total`.
`shown` and `total` are cells that follow the place.
"""
@document struct ArrangementChips
    entry::Any
    shown::Any
    total::Any
end

"""
    ArrangementFilter(conditions)

A filter that a person placed at a collection: it keeps the items for which every
`ArrangementCondition` of `conditions` holds, in their order. Each condition is a
chip.
"""
@document struct ArrangementFilter
    conditions::CellVector
end

"""
    ArrangementCondition(key, operator, value)

A condition on one item: the value at the path `key` inside the item, read with
[`get_arrangement_value`](@ref), compared with `value` by `operator`, one of
`:equal`, `:not_equal`, `:less`, `:greater`, `:at_most`, `:at_least` and
`:contains`. The empty path is the item itself, and a `key` that is `nothing`
stands for any value inside the item.
"""
@document struct ArrangementCondition
    key::Any
    operator::Symbol
    value::Any
end

"""
    is_quick_text_condition(condition) -> Bool

Whether `condition` is the condition of a quick text field: any value inside an
item contains its text, a key that is `nothing` and the operator `:contains`. A
bar shows it as a field at its end, not as a chip.
"""
is_quick_text_condition(condition) =
    condition isa ArrangementCondition && condition.key === nothing && condition.operator === :contains

"""
    ArrangementSort(keys)

A sort that a person placed at a collection: the items in the order of the first
`ArrangementSortKey` of `keys`, then of the next one for items that are equal, and
in their own order for items that are equal in every key. Each key is a chip.
"""
@document struct ArrangementSort
    keys::CellVector
end

"""
    ArrangementSortKey(key, direction)

The value at the path `key` inside an item, read with `get_arrangement_value`, in
the `direction` `:ascending` or `:descending`. Numbers come before text, text
before other values, and a missing value last in either direction.
"""
@document struct ArrangementSortKey
    key::Any
    direction::Symbol
end

"""
    ArrangementFind(text)

What a person finds in a collection: the items where any value contains `text`.
It hides no item and changes no order. The bar shows `text` in a field, and a
command moves the selection to the next or the previous item that holds it, in
the order in which the items show (`make_find_move`).
"""
@document struct ArrangementFind
    text::Any
end
