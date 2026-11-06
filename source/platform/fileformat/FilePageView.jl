# Fragment of `FileFormatModule` — the view of a page of a file: the state of one
# place that shows it, apart from the page, which every place shares.

"""
    FilePageView(page, scroll)

The view of a [`FilePage`](@ref) at one place, a tab or a card: `page`, the page
that it shows, and `scroll`, the scroll pane of this place, which keeps where this
place is scrolled to. The page keeps the file, its hash and its band once, and each
place that shows it keeps a view of its own, so a scroll in one tab leaves the
card that shows the same file where it is. The view draws the band of the page
above the file in its scroll pane ([`FilePageToWidget`](@ref)).

A walk reaches the file through `page` (`get_edited_field`), and not through
`scroll`, which holds the file for the pane only. A holder holds the view, and the
view holds the page ([`make_file_page_view`](@ref)).

# Example

    view = make_file_page_view(make_file_page(make_file_tab("notes.txt")))
"""
@document struct FilePageView
    page::Any
    scroll::Any
end

get_edited_field(::FilePageView) = :page
get_document_title(view::FilePageView) = get_document_title(view.page)
get_document_decoration(view::FilePageView) = get_document_decoration(view.page)
is_field_walked(::FilePageView, name::Symbol) = name !== :scroll

"""
    make_file_page_view(page) -> FilePageView

The view of `page` for a new place, with its own scroll pane that grows on its
height, as a page does, so a table on a Markdown page is as tall as its rows and
the place scrolls it. Its selection follows the selection of the page
([`follow_content_selection!`](@ref)).

Use it where a page shows, such as a tab that opens a file.
"""
make_file_page_view(page::FilePage) = follow_content_selection!(make_document_view(page))

make_document_view(page::FilePage) =
    FilePageView(page, WidgetScrollPane(page.content; grows = (width = false, height = true)))

# A view holds its page, and the page holds its file, so the file watches the disk
# while a place shows it.
acquire_document!(editor, view::FilePageView) = hold_documents!(editor, view, Any[view.page])

release_document!(editor, view::FilePageView) = release_held_documents!(editor, view, Any[view.page])

# A holder saves a view as the file that it shows.
find_held_file(view::FilePageView) = find_held_file(view.page)
