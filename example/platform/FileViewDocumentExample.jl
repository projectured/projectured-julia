# The view of a text file that is not on disk: the file in its scroll pane, with no
# band above it, so a test reads no file.
make_file_view_document_example() = make_file_view(TextFile("notes.txt", "A note."))
