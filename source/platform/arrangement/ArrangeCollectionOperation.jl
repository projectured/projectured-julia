# Fragment of `ArrangementModule` — the operation that arranges a collection from
# a part inside it, and the edits that the holder of the document makes of it.

"""
    ArrangeCollectionOperation(at, description)

Put `description`, such as an `ArrangementFilter` or an `ArrangementSort`, at the
collection `at`, a path from the input of the reader that holds the operation. A
description of the same kind that is there gives way to it, and an empty one
takes that kind away. `description === nothing` takes every projection at `at`
away, as Show all does.

A part inside the collection makes it, such as the sort glyph of a header or a
verb of the assistant, and the readers around the part carry it out, rerooted and
mapped as a path. The nearest reader that holds an arrangement of the document
makes the edit of the arrangement ([`make_arrangement_change_edit`](@ref)). A
reader that holds a document that nobody arranged, such as the reader of a tab,
puts the first arrangement in its place ([`make_first_arrangement`](@ref)). One
that reaches the root does nothing.
"""
struct ArrangeCollectionOperation <: Operation
    at::Reference
    description::Any
end

operation_reference(operation::ArrangeCollectionOperation) = operation.at
retarget_operation(operation::ArrangeCollectionOperation, reference) =
    ArrangeCollectionOperation(reference, operation.description)

"""
    make_arrangement_change_edit(arrangement, operation) -> Operation or nothing

The edit of `arrangement` that `operation`, an `ArrangeCollectionOperation` whose
`at` is a path in the document of `arrangement`, makes: a new entry at `at`, the
description of the entry of `at` that gives way, a new description in that entry
(a filter first, any other kind last), the removal of a description, or the
removal of the entry when it keeps no description. A description that gives way
keeps its identity and takes the conditions or the keys of the new one, so the
chain of its place is not built again. `nothing` when nothing changes.
"""
function make_arrangement_change_edit(arrangement::ArrangementDocument, operation::ArrangeCollectionOperation)
    at = strip_reference_types(operation.at)
    description = operation.description
    entry = _find_entry_at(arrangement.entries, at, Reference)
    if description === nothing
        return entry === nothing ? nothing : make_entry_removal_edit(arrangement, entry)
    end
    empty = _is_empty_description(description)
    if entry === nothing
        empty && return nothing
        n = length(arrangement.entries)
        return _make_splice(arrangement, "entries", n, n, Any[ArrangementEntry(at, Any[description])])
    end
    projections = collect(entry.projections)
    d = findfirst(old -> nameof(typeof(old)) === nameof(typeof(description)), projections)
    if d === nothing
        empty && return nothing
        place = description isa ArrangementFilter ? 0 : length(projections)
        return _make_splice(entry, "projections", place, place, Any[description])
    end
    if empty
        length(projections) == 1 && return make_entry_removal_edit(arrangement, entry)
        return _make_splice(entry, "projections", d - 1, d, Any[])
    end
    _make_description_change(entry, d, projections[d], description)
end

"""
    make_first_arrangement(document, operation) -> ArrangementDocument or nothing

The first arrangement of `document`, which nobody arranged yet, that `operation`,
an `ArrangeCollectionOperation` whose `at` is a path in `document`, makes: one
entry at `at` with the description of `operation`. `nothing` when the
description is empty or `nothing`. The holder of `document` puts it in the place
of `document`.
"""
function make_first_arrangement(document, operation::ArrangeCollectionOperation)
    description = operation.description
    (description === nothing || _is_empty_description(description)) && return nothing
    ArrangementDocument(document, [ArrangementEntry(strip_reference_types(operation.at), Any[description])])
end

"""
    make_entry_removal_edit(arrangement, entry) -> Operation or nothing

The edit that takes `entry` away from `arrangement`, named by `arrangement`
itself; `nothing` when `entry` is not one of its entries. The reader of the
arrangement turns the removal of the last entry into the edit that takes the
arrangement away.
"""
function make_entry_removal_edit(arrangement::ArrangementDocument, entry)
    e = findfirst(other -> other === entry, collect(arrangement.entries))
    e === nothing && return nothing
    _make_splice(arrangement, "entries", e - 1, e, Any[])
end

_is_empty_description(filter::ArrangementFilter) = isempty(filter.conditions)
_is_empty_description(sort::ArrangementSort) = isempty(sort.keys)
_is_empty_description(description) = false

# The edit that makes `old`, the `d`-th description of `entry`, say what `new`
# says: the conditions or the keys of `new` in `old`, or `new` in the place of
# `old` for a kind that has no such method.
_make_description_change(entry, d, old::ArrangementFilter, new::ArrangementFilter) =
    _make_splice(old, "conditions", 0, length(old.conditions), Any[condition for condition in new.conditions])
_make_description_change(entry, d, old::ArrangementSort, new::ArrangementSort) =
    _make_splice(old, "keys", 0, length(old.keys), Any[key for key in new.keys])
_make_description_change(entry, d, old, new) = _make_splice(entry, "projections", d - 1, d, Any[new])
