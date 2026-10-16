# The page of a text file that is not on disk: the file in its scroll pane, with no
# band above it, so a test reads no file.
make_file_page_document_example() =
    FilePage(; content = WidgetScrollPane(TextFile("notes.txt", "A note.")))
