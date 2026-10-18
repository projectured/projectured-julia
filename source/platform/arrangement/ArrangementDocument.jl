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

# An arrangement is transparent on the screen, and a real node in the tree.
# Anything that reads the tree rather than the picture, as a save of a file does,
# asks for the document that it stands for and gets what it holds. A person edits
# that document, and a document read again goes into the arrangement, which keeps
# its entries.
get_wrapped_document(arrangement::ArrangementDocument) = get_wrapped_document(arrangement.document)
get_edited_field(::ArrangementDocument) = :document
function replace_wrapped_document!(arrangement::ArrangementDocument, document)
    arrangement.document = replace_wrapped_document!(arrangement.document, document)
    arrangement
end

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

"""
    ArrangementGroup(keys, aggregates)

A group that a person placed at a collection: one row for each value that the
items have at the paths of `keys`, in the order in which the first item of each
group comes, with the value of each `ArrangementAggregate` of `aggregates` over
the items of the group ([`ArrangementGroupRow`](@ref)). The bar shows the group
as one chip.
"""
@document struct ArrangementGroup
    keys::CellVector
    aggregates::CellVector
end

"""
    ArrangementAggregate(key, operator)

One value of each group: `operator` over the values at the path `key` inside the
items of the group. `:count` counts the items, and `:sum`, `:mean`, `:minimum`
and `:maximum` take the numbers among the values; a slice adds an operator with
a method of [`compute_arrangement_aggregate`](@ref).
"""
@document struct ArrangementAggregate
    key::Any
    operator::Symbol
end

"""
    ArrangementFirst(count)

The first `count` items of a collection, in the order that the projections before
it give. The bar shows it as one chip.
"""
@document struct ArrangementFirst
    count::Int
end

"""
    ArrangementGroupRow(columns, values, members)

One row that a group makes: the names of its columns, the keys of the group and
then its aggregates (`columns`), the value of each (`values`), and the indices of
the items of the group among the items that the group read (`members`). A filter,
a sort and the first items after a group act on these rows, and a key of a row
is the name of a column.
"""
@document struct ArrangementGroupRow
    columns::Any
    values::Any
    members::Any
end

# An arrangement says what the document that it wraps says, and that a filter or
# a sort hides or orders its items. A document that shows a collection of its own,
# as a roster shows its rows, counts the items that the arrangement shows.
function get_document_decoration(arrangement::ArrangementDocument)
    base = get_document_decoration(arrangement.document)
    arranged = any(entry -> !isempty(entry.projections), arrangement.entries)
    counts = _count_arranged_items(arrangement, base.counts)
    (arranged || counts !== base.counts) || return base
    DocumentDecoration(; icon = base.icon,
                       conditions = arranged ? [base.conditions..., DocumentCondition(:filtered)] : base.conditions,
                       counts, detail = base.detail, tooltip = base.tooltip, work_item = base.work_item)
end

# The count of the items that `arrangement` shows of the collection that its
# document shows (`get_arranged_collection_steps`), in the colour that they share,
# in place of `counts`, the counts of the document; `counts` when the document
# shows no collection of its own. No item shows no count.
function _count_arranged_items(arrangement::ArrangementDocument, counts)
    steps = get_arranged_collection_steps(arrangement.document)
    isempty(steps) && return counts
    found = find_arranged_collection(arrangement, extend_reference(EmptyReference(), steps...))
    found === nothing && return counts
    shown = collect_shown_items(found.entry, found.items)
    isempty(shown) && return DocumentCount[]
    [DocumentCount(string(length(shown)); role = find_shared_decoration_tint(shown))]
end
