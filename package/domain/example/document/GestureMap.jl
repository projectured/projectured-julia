# Atomic document for the catalog: three representative gesture rows — one
# applicable, one not (the help window greys out an inapplicable row), and one with
# no gesture at all, which a user runs by name.

make_gesture_map_document_example() =
    GestureMap(rows = [
        GestureRow("Ctrl+C", "Copy the selection", "clipboard", true, nothing, false),
        GestureRow("Ctrl+V", "Paste", "clipboard", false, nothing, false),
        GestureRow("", "Sort the entries", "clipboard", true, "Sort the entries", true),
    ])
