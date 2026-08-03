"""
    BookModule

The book document domain. Models structured prose: books, chapters,
paragraphs, lists, and pictures.

The domain includes:
- **Structure**: `BookBook`, `BookChapter`
- **Content**: `BookParagraph`, `BookList`, `BookPicture`
- **Utility types**: `BookInsertion` for cursor positioning
"""
module BookModule

import ..CellModule: Cell, ComputedCell
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
export BookDocument

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
A figure with an optional `title`. `content` is an image value or path;
`alignment` is one of `:left`, `:center`, `:right`, or `:justified`.
"""
@document struct BookPicture <: BookDocument
    content::Any
    title::String = ""
    alignment::Symbol = :left
    collapsed::Bool = false
end

# Text-replace edits need no per-type method: `title`/`author`/`numbering` are
# plain strings, and a paragraph's `content` is a `TextBlock` whose representation
# locates and splices the right span.

end # module
