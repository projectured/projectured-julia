function make_tabular_document_example()
    TabularGrid(CellVector([
        TabularRow(CellVector([
            TabularCell("Title"),
            TabularCell("Author"),
            TabularCell("Year"),
            TabularCell("Pages"),
        ])),
        TabularRow(CellVector([
            TabularCell("Dune"),
            TabularCell("Frank Herbert"),
            TabularCell(1965),
            TabularCell(412),
        ])),
        TabularRow(CellVector([
            TabularCell("Neuromancer"),
            TabularCell("William Gibson"),
            TabularCell(1984),
            TabularCell(271),
        ])),
        TabularRow(CellVector([
            TabularCell("Foundation"),
            TabularCell("Isaac Asimov"),
            TabularCell(1951),
            TabularCell(244),
        ])),
    ]), 4)
end
