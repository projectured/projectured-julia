# Three strings with an entry at the whole collection that keeps the first two.
function make_arrangement_document_example()
    items = CellVector(Any[PrimitiveString("gamma"), PrimitiveString("alpha"), PrimitiveString("beta")])
    ArrangementDocument(items, ArrangementEntry[ArrangementEntry(EmptyReference(), Any[ArrangementFirst(2)])])
end

# The chips of an entry that keeps the first two items, with two items shown of three.
make_arrangement_chips_document_example() =
    ArrangementChips(ArrangementEntry(EmptyReference(), Any[ArrangementFirst(2)]), 2, 3)
