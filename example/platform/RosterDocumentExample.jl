# A roster of two strings, a row for each, with the column of their value.
function make_roster_document_example()
    items = CellVector(Any[PrimitiveString("alpha"), PrimitiveString("beta")])
    link_roster!(Roster(CollectionItems(items); columns = ["value"], title = "Values"), items)
end
