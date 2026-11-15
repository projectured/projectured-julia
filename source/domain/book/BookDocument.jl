# Fragment of `BookModule` — the book document types: the abstract
# `BookDocument`, its insertion cursor, and the nodes a book tree holds.

"""
    BookDocument

The abstract supertype of the documents of a book. Its main members are `BookBook`, `BookChapter`, `BookParagraph`, `BookList`, `BookPicture`.

Use it to recognise the documents of a book when you walk a document: a part is one of them when `part isa BookDocument`.

# Example

    parts_1 = search_documents(get_edited_document(find_pane("book")), part -> part isa BookDocument)
    found_1 = search_documents(get_edited_document(find_pane("book")), part -> part isa BookChapter)

See also `search_documents`, `find_pane`, `describe_document` and `BookChapter`.

For the assistant.
"""
abstract type BookDocument <: Document end

# ── Insertion cursor ─────────────────────────────────────────────────────

"""
A placeholder for a book node being entered (the insert-by-typing cursor);
type-to-replace swaps it for concrete content.
"""
@document struct BookInsertion <: BookDocument
    value::Any = nothing
end

# ── Structure ────────────────────────────────────────────────────────────

"""
The top-level book document — a `title`, an optional `author`, and a sequence
of child nodes (typically `BookChapter`s). `collapsed` hides them behind a
marker in the projection.
"""
@document struct BookBook <: BookDocument
    title::String
    author::Any = nothing
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

"""
A chapter grouping child nodes under a `title` and optional `numbering` (e.g.
`"1"`). `collapsed` hides them in the projection.
"""
@document struct BookChapter <: BookDocument
    title::String
    numbering::String = ""
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

# ── Content ──────────────────────────────────────────────────────────────

"""
A prose paragraph. `content` is typically a `TextBlock`; `alignment` is one of
`:left`, `:center`, `:right`, or `:justified`.
"""
@document struct BookParagraph <: BookDocument
    content::Any
    alignment::Symbol = :left
    collapsed::Bool = false
end

"""
An unordered list of child nodes. `collapsed` hides them in the projection.
"""
@document struct BookList <: BookDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

"""
A figure with an optional `title`. `content` is an image value, a picture file or
a path; `alignment` is one of `:left`, `:center`, `:right`, or `:justified`.
`picture` is the editor's file document of the picture that a path in `content`
names, with the path that named it, as `path => file`, or `nothing`: the open and
each load of the file of the book give it, and no save writes it.
"""
@document struct BookPicture <: BookDocument
    content::Any
    title::String = ""
    alignment::Symbol = :left
    collapsed::Bool = false
    picture::Any = nothing
end

# Text-replace edits need no per-type method: `title`/`author`/`numbering` are
# plain strings, and a paragraph's `content` is a `TextBlock` whose representation
# locates and splices the right span.

# ── The pictures of the pictures ───────────────────────────────────────────
# A picture holds the editor's one file document of the picture file that it shows,
# as an image of a Markdown page does: a picture file in `content`, which a `.pred`
# file gives from `file("…")`, or the file that a path in `content` names, which the
# open and each load of the file of the book give it, against the folder of that file.
# The book holds its pictures while a holder holds the file, and each picture holds
# its file. A url of the web and a path of a file that is not a picture name no
# picture. An edit changes no hold.

get_view_state_fields(::Type{<:BookPicture}) = (:picture,)

function splice_named_file!(node::BookPicture, find_file)
    path = node.content
    (path isa AbstractString && find_web_url(path) === nothing && is_picture_file_path(path)) || return nothing
    file = find_file(path)
    file isa ImageFile && (node.picture = String(path) => file)
    nothing
end

acquire_document!(editor, node::BookPicture) = hold_documents!(editor, node, _collect_held_pictures(node))
release_document!(editor, node::BookPicture) =
    release_held_documents!(editor, node, _collect_held_pictures(node))

# The picture file that `node` shows, as the only element.
function _collect_held_pictures(node::BookPicture)
    file = find_book_picture_file(node)
    file === nothing ? Any[] : Any[file]
end

# The picture file that `node` shows: its content, or the file that it holds for the
# path in its content; `nothing` for any other content.
function find_book_picture_file(node::BookPicture)
    content = node.content
    content isa ImageFile && return content
    content isa AbstractString ? find_held_picture(node.picture, content) : nothing
end

acquire_document!(editor, book::BookBook) = hold_documents!(editor, book, _collect_book_pictures(book))
release_document!(editor, book::BookBook) = release_held_documents!(editor, book, _collect_book_pictures(book))

# Each picture of `book`, at any depth.
_collect_book_pictures(book::BookBook) =
    Any[walk_document(DocumentWalk(), book, node -> node isa BookPicture; limit = nothing, enter_matches = false)...]
