# Atomic document for the catalog: three representative gesture rows — one that can
# run, one that cannot right now (the help window greys it out), and one with no
# gesture at all, reached only by name. A row carries the operation it would apply;
# `nothing` is what "cannot run" means.

make_gesture_map_document_example() =
    GestureMap(rows = [
        GestureRow("Ctrl+C", "Copy the selection", "clipboard", DoNothingOperation()),
        GestureRow("Ctrl+V", "Paste", "clipboard", nothing),
        GestureRow("", "Sort the entries", "clipboard", DoNothingOperation()),
    ])

# A command palette with the query "sort" over three rows, one of which cannot run.
make_command_palette_document_example() =
    CommandPalette(query = "sort", rows = [
        GestureRow("Ctrl+C", "Copy the selection", "clipboard", DoNothingOperation()),
        GestureRow("", "Sort the entries", "clipboard", DoNothingOperation()),
        GestureRow("Ctrl+V", "Paste", "clipboard", nothing),
    ])
