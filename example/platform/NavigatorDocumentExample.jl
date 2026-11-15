# Navigator example documents: a navigator, and the copy of its address that the
# bar shows and a person edits.

# A navigator on the vertical layout example, which shows the whole layout.
make_navigator_document_example() = Navigator(make_vertical_layout_document_example())

# The address copy of a navigator while a person edits it in the path view:
# `.children[2]`, a field and an element.
make_navigator_address_document_example() =
    NavigatorAddress(; steps = CellVector(Cell[Cell(FieldReferenceStep("children")), Cell(RangeReferenceStep(1, 2))]),
                     view = :path, edited = true)
