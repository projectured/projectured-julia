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
