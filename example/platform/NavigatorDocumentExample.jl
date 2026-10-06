# Navigator example documents: a navigator, the copy of its address that the bar
# shows and a person edits, and the list of the choices at a step of it.

# A navigator on the vertical layout example, which shows the whole layout.
make_navigator_document_example() = Navigator(make_vertical_layout_document_example())

# The address copy of a navigator while a person edits it in the path view:
# `.children[2]`, a field and an element.
make_navigator_address_document_example() =
    NavigatorAddress(; steps = CellVector(Cell[Cell(FieldReferenceStep("children")), Cell(RangeReferenceStep(1, 2))]),
                     view = :path, edited = true)

# The list of the choices at an element step, with two choices, the first of
# them the current one.
function make_navigator_choice_list_document_example()
    choices = Pair{String,ReferenceStep}["one" => RangeReferenceStep(0, 1), "two" => RangeReferenceStep(1, 2)]
    NavigatorChoiceList(; current = RangeReferenceStep(0, 1),
                        find = query -> filter(choice -> occursin(query, first(choice)), choices))
end
