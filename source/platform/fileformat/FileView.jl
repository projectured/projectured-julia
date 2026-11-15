# Fragment of `FileFormatModule` — the view of a file document: the state of one
# place that shows it, apart from the file, which every place shares.

"""
    FileView(file, scroll)

The view of a file document at one place, a tab or a card: `file`, the file that it
shows, and `scroll`, the scroll pane of this place, which keeps where this place is
scrolled to. The file keeps its content, its hash and its band once
([`FileDiskState`](@ref)), and each place that shows it keeps a view of its own, so
a scroll in one tab leaves the card that shows the same file where it is. The view
draws the band of the file above the file in its scroll pane
([`FileViewToWidget`](@ref)).

A walk reaches the file through `file` (`get_edited_field`), and not through
`scroll`, which holds the file for the pane only. A holder holds the view, and the
view holds the file ([`make_file_view`](@ref)); `make_document_view` of a file
answers one.

# Example

    view = make_file_view(make_file_tab("notes.txt"))
"""
@document struct FileView
    file::Any
    scroll::Any
end

get_edited_field(::FileView) = :file
get_document_title(view::FileView) = get_document_title(view.file)
get_document_decoration(view::FileView) = get_document_decoration(view.file)
is_field_walked(::FileView, name::Symbol) = name !== :scroll

"""
    make_file_view(file) -> FileView

The view of `file` for a new place, with its own scroll pane that grows on its
height, as a file does, so a table on a Markdown page is as tall as its rows and the
place scrolls it. Its selection follows the selection of the file
([`follow_content_selection!`](@ref)).

Use it where a file shows, such as a tab that opens a file.
"""
make_file_view(file::FileDocument) = follow_content_selection!(make_document_view(file))

make_document_view(file::FileDocument) =
    FileView(file, WidgetScrollPane(file; grows = (width = false, height = true)))

# A view holds its file, so the file watches the disk while a place shows it.
acquire_document!(editor, view::FileView) = hold_documents!(editor, view, Any[view.file])

release_document!(editor, view::FileView) = release_held_documents!(editor, view, Any[view.file])

# A holder saves a view as the file that it shows.
find_held_file(view::FileView) = view.file
