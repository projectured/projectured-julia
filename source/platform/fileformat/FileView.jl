# Fragment of `FileFormatModule` — the view of a file document: the state of one
# place that shows it, apart from the file, which every place shares.

"""
    FileView(file, scroll)
    FileView(file, scroll, content)

The view of a file document at one place, a tab or a card: `file`, the file that it
shows, and `scroll`, the scroll pane of this place, which keeps where this place is
scrolled to. `content` is the view of what the file holds, when the place shows the
file through views ([`make_file_view`](@ref)), and `nothing` otherwise. With
`content`, the caret of the place is a path of the views, such as
`.content.content.elements[2]`, and the file and what it holds keep no caret. With no
view there, the place shows the file, and a path of the place goes through `file`. The file keeps its content, its hash and its band once
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
    content::Any = nothing
end

get_edited_field(::FileView) = :file
get_document_title(view::FileView) = get_document_title(view.file)
get_document_decoration(view::FileView) = get_document_decoration(view.file)
is_field_walked(::FileView, name::Symbol) = name !== :scroll

"""
    is_file_shown_through_views(file) -> Bool

Whether a new view of `file` shows the file through views when the caller does not
say ([`make_file_view`](@ref)). The default answers `false`: the place shows the
file, and the caret is in what the file holds. The package of a file format whose
documents have views answers `true` for its file.

Use it to turn the views on for the files of one format.

# Example

    is_file_shown_through_views(::JsonFile) = true
"""
function is_file_shown_through_views end

is_file_shown_through_views(file) = false

"""
    make_file_part_note(file, path) -> TooltipNote or nothing

The note of `file` about its part at `path`, a path from `file`: what the tooltip
of a view of the file says about the part under the pointer. The default answers
`nothing`. The package of a file format whose files show through views adds a
method, because such a file keeps no pointer of its own, and its view gives the
path.

Use it for a file format that says what the pointer is on.

# Example

    make_file_part_note(file::JsonFile, path) = make_json_part_note(file, path)
"""
function make_file_part_note end

make_file_part_note(file, path) = nothing

"""
    make_file_view(file; views = is_file_shown_through_views(file)) -> FileView

The view of `file` for a new place, with its own scroll pane that grows on its
height, as a file does, so a table on a Markdown page is as tall as its rows and the
place scrolls it. Its selection follows the selection of the file
([`follow_content_selection!`](@ref)).

With `views`, the place shows the file through views. The default comes from the
file ([`is_file_shown_through_views`](@ref)). The field `content` of the
view holds the view of what the file holds now (`make_content_view`), the scroll
pane shows that view, and the selection of the file view is its own: a second
place that shows the same file keeps another caret. While what the file holds has
no view, the place shows the file as with no `views`.

Use it where a file shows, such as a tab that opens a file.

# Example

    view = make_file_view(make_file_tab("people.json", UndoBuffer); views = true)
    view.content            # the view of the undo buffer of the file
    view.content.content    # the view of the JSON document
"""
make_file_view(file::FileDocument; views::Bool = is_file_shown_through_views(file)) =
    follow_content_selection!(make_document_view(file; views))

function make_document_view(file::FileDocument; views::Bool = is_file_shown_through_views(file))
    scroll = WidgetScrollPane(file; grows = (width = false, height = true))
    views || return FileView(file, scroll)
    view = FileView(file, scroll, Cell(Computation(make_slot_view_computation(() -> get_file_content(file)))))
    set_cell_computation!(scroll, () -> _get_shown_document(view))
    view
end

# Whether `view` shows its file through views: its field `content` follows what the
# file holds.
_shows_file_views(view::FileView) = get_cell_computation(getfield(view, :content)) !== nothing

# What the scroll pane of `view` shows: the view of what the file holds, or the file
# when there is no such view.
_get_shown_document(view::FileView) = (shown = view.content; shown === nothing ? view.file : shown)

# A file view that shows its file through views keeps its own caret. Any other file
# view takes the caret of its file.
follow_content_selection!(view::FileView) =
    _shows_file_views(view) ? view : invoke(follow_content_selection!, Tuple{Any}, view)

# The paths of a file view that shows its file through views. The file holds what it
# holds at `content`, and the view holds the view of that at `content` too. So a path
# of the file that starts with `content` keeps that step below the view, and the view
# of what the file holds changes the rest. The whole file is the whole view. Any other
# path of the file goes through the field `file`, where no view shows it.
function get_view_path(view::FileView, path)
    shown = view.content
    shown === nothing && return invoke(get_view_path, Tuple{Any, Any}, view, path)
    path isa ConcreteReference || return EmptyReference()
    steps = get_reference_steps(strip_reference_types(path))
    first(steps) == _FILE_VIEW_CONTENT_STEP || return invoke(get_view_path, Tuple{Any, Any}, view, path)
    _make_shown_path(get_view_path(shown, length(steps) == 1 ? EmptyReference() : Reference(steps[2:end]...)))
end

function get_content_path(view::FileView, path)
    shown = view.content
    shown === nothing && return invoke(get_content_path, Tuple{Any, Any}, view, path)
    path isa ConcreteReference || return EmptyReference()
    steps = get_reference_steps(strip_reference_types(path))
    first(steps) == _FILE_VIEW_CONTENT_STEP || return invoke(get_content_path, Tuple{Any, Any}, view, path)
    _make_shown_path(get_content_path(shown, length(steps) == 1 ? EmptyReference() : Reference(steps[2:end]...)))
end

# `rest` below the step `content`, with no types.
_make_shown_path(rest) =
    rest isa ConcreteReference ? Reference(_FILE_VIEW_CONTENT_STEP, get_reference_steps(strip_reference_types(rest))...) :
                                 Reference(_FILE_VIEW_CONTENT_STEP)

# A view holds its file, so the file watches the disk while a place shows it.
acquire_document!(editor, view::FileView) = hold_documents!(editor, view, Any[view.file])

release_document!(editor, view::FileView) = release_held_documents!(editor, view, Any[view.file])

# A holder saves a view as the file that it shows.
find_held_file(view::FileView) = view.file
