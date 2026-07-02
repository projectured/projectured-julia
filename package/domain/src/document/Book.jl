"""
    BookModule

The book document domain. Models structured prose: books, chapters,
paragraphs, lists, and pictures. Every node subtypes the abstract
BookDocument base (itself a Document) and carries a reactive `collapsed`
Cell.
"""
module BookModule

import ..ReactiveModule: Cell
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
export BookDocument, BookInsertion, BookBook, BookChapter, BookParagraph, BookList, BookPicture,
       IBookInsertion, IBookBook, IBookChapter, IBookParagraph, IBookList, IBookPicture

# ── BookDocument (abstract base) ───────────────────────────────────────────────

"""
    BookDocument

Abstract base type for all book document nodes.  Every concrete subtype
carries a `collapsed::Cell` and a `selection::Reference`.
"""
abstract type BookDocument <: Document end

# ── BookInsertion ───────────────────────────────────────────────────────

@document struct BookInsertion <: BookDocument
    value::Any = nothing
    selection::Reference = nothing
end

# ── BookBook ───────────────────────────────────────────────────────────────

"""
    BookBook(title, author, elements)

The top-level book document.  `title` is required (a leading positional
argument, so `elements` reaches the `CellVector`-wrapping constructor);
`author`/`elements` and the `collapsed`/`selection` state all default. The
projection renders an author line only when `author !== nothing`.  `elements`
holds the sequence of child nodes (typically `BookChapter`s).
"""
@document struct BookBook <: BookDocument
    title::String
    author::Any = nothing
    elements::CellVector = CellVector()
    collapsed::Bool = false
    selection::Reference = nothing
end

# ── BookChapter ────────────────────────────────────────────────────────────

"""
    BookChapter(title, numbering, elements)

A chapter grouping child nodes.  `title` is the required leading argument (so
`elements` reaches the `CellVector`-wrapping constructor); `numbering` (e.g.
`"1"`, `""` for none) and the `collapsed`/`selection` state default.
"""
@document struct BookChapter <: BookDocument
    title::String
    numbering::String = ""
    elements::CellVector = CellVector()
    collapsed::Bool = false
    selection::Reference = nothing
end

# ── BookParagraph ──────────────────────────────────────────────────────────

"""
    BookParagraph(content)

A prose paragraph.  `content` is the required leading argument (typically a
`TextText` value); `alignment` — one of `:left`, `:center`, `:right`, or
`:justified` — and the `collapsed`/`selection` state default.
"""
@document struct BookParagraph <: BookDocument
    content::Any
    alignment::Symbol = :left
    collapsed::Bool = false
    selection::Reference = nothing
end

# ── BookList ───────────────────────────────────────────────────────────────

"""
    BookList(elements)

An unordered list of child nodes.  Every field defaults, so the sole
`CellVector` accepts a bracketed vector (`BookList([…])`) or a variadic run of
nodes.
"""
@document struct BookList <: BookDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
    selection::Reference = nothing
end

# ── BookPicture ────────────────────────────────────────────────────────────

"""
    BookPicture(content)

A figure with an optional title.  `content` is the required leading argument
(an image value or path); `title` and `alignment` — one of `:left`, `:center`,
`:right`, or `:justified` — and the `collapsed`/`selection` state default.
"""
@document struct BookPicture <: BookDocument
    content::Any
    title::String = ""
    alignment::Symbol = :left
    collapsed::Bool = false
    selection::Reference = nothing
end

# Text-replace edits for the book domain are handled generically by
# `splice_value!` (see OperationApiModule): `title`/`author`/`numbering` are
# plain strings (string representation), and a paragraph's `content` is a
# `TextText` (the TextText representation defined in TextModule locates and
# splices the right span). No per-type method is needed.

end # module
