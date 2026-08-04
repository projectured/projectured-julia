function make_collection_document_example()
    CellVector(
        PrimitiveString("banana     (1)"),
        PrimitiveString("apple      (2)"),
        PrimitiveString("cherry     (3)"),
        PrimitiveString("elderberry (4)"),
        PrimitiveString("date       (5)"),
    )
end

# The two-dimensional form. Row 1 is the column headers and the rest the body,
# which is the shape `CellTableToWidgetTable` reads; the cells are plain values
# because that projection wraps them as Primitive documents on the way out.
make_cell_table_document_example() =
    CellTable(["name" "age"; "Alice" 30; "Bob" 25])

# A doubly-linked list, held by its head — the node you hold IS the head, and
# `push!` grows the `next` tail, so this is a chain rather than a lone node.
function make_list_node_document_example()
    head = ListNode(PrimitiveString("alpha"))
    push!(head, PrimitiveString("beta"))
    push!(head, PrimitiveString("gamma"))
    head
end
