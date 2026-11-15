# The documents of the explorer slice: a section of entries, the explorer that
# shows it as a tree beside a navigator, a search below its root, and a dashboard
# of cards. The entries are outlines and a dashboard, plain documents, so a test
# makes them with no editor and no folder.

# A dashboard of one card, which shows an outline as a tree.
make_dashboard_document_example() =
    Dashboard("Study", Any[DashboardCard("Concepts",
                                         DocumentTree(_make_outline_item("Concepts",
                                                                         _make_outline_item("Cells"),
                                                                         _make_outline_item("References"))))])

# A section of an outline of notes and of a dashboard.
make_explorer_section_document_example() =
    ExplorerSection("Explorer", Any[_make_outline_item("Notes",
                                                       _make_outline_item("Cells"),
                                                       _make_outline_item("Cell faults")),
                                    make_dashboard_document_example()])

# The explorer of that section, with the root of its tree open, on the page of the
# section.
make_explorer_document_example() = Explorer(make_explorer_section_document_example())

# The search for "cell" below the root of that section: the two nodes of the notes.
make_explorer_search_document_example() =
    ExplorerSearch(make_explorer_section_document_example(), Any[], "cell"; identifier = "S1")
