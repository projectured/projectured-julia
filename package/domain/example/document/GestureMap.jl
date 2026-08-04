# Atomic document for the catalog: a couple of representative gesture rows,
# one applicable and one not (the help window greys out an inapplicable row).

make_gesture_map_document_example() =
    GestureMap(rows = [
        GestureRow("Ctrl+C", "Copy the selection", "clipboard", true),
        GestureRow("Ctrl+V", "Paste", "clipboard", false),
    ])
