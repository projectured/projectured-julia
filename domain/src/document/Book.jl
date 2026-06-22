"""
    BookModule

The book document domain. Models structured prose: books, chapters,
paragraphs, lists, and pictures. Every node subtypes the abstract
BookDocument base (itself a Document) and carries a reactive `collapsed`
Cell.
"""
module BookModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
import ..TextModule: TextText, TextString
export BookDocument, BookInsertion, BookBook, BookChapter, BookParagraph, BookList, BookPicture, setfn!,
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
    value::Any
    selection::Reference
end
BookInsertion() = BookInsertion(Cell(nothing), Cell(nothing))

# ── BookBook ───────────────────────────────────────────────────────────────

"""
    BookBook(elements; title, author, collapsed)

The top-level book document.  `elements` holds the sequence of child
nodes (typically `BookChapter`s)..
"""
@document struct BookBook <: BookDocument
    title::String
    author::Any
    elements::CellVector
    collapsed::Bool
    selection::Reference
end

function BookBook(elements::Vector;
                  title::AbstractString="",
                  author=nothing,
                  collapsed::Bool=false)
    BookBook(Cell(String(title)), Cell(author),
             CellVector(Cell[Cell(x) for x in elements]),
             Cell(collapsed), Cell(nothing))
end

BookBook(; kwargs...) = BookBook(BookDocument[]; kwargs...)

setfn!(b::BookBook, f::Function) = (setfn!(getfield(b.elements, :elements), () -> Cell[Cell(x) for x in f()]); b)

# ── BookChapter ────────────────────────────────────────────────────────────

"""
    BookChapter(elements; title, numbering, collapsed)

A chapter grouping child nodes..
"""
@document struct BookChapter <: BookDocument
    title::String
    numbering::String
    elements::CellVector
    collapsed::Bool
    selection::Reference
end

function BookChapter(elements::Vector;
                     title::AbstractString="",
                     numbering::AbstractString="",
                     collapsed::Bool=false)
    BookChapter(Cell(String(title)), Cell(String(numbering)),
                CellVector(Cell[Cell(x) for x in elements]),
                Cell(collapsed), Cell(nothing))
end

BookChapter(; kwargs...) = BookChapter(BookDocument[]; kwargs...)

setfn!(b::BookChapter, f::Function) = (setfn!(getfield(b.elements, :elements), () -> Cell[Cell(x) for x in f()]); b)

# ── BookParagraph ──────────────────────────────────────────────────────────

"""
    BookParagraph(content; alignment, collapsed)

A prose paragraph.  `content` is typically a `TextText` value
`alignment` is one of `:left`, `:center`, `:right`, or `:justified`.
"""
@document struct BookParagraph <: BookDocument
    alignment::Symbol
    content::Any
    collapsed::Bool
    selection::Reference
end

function BookParagraph(content;
                       alignment::Symbol=:left,
                       collapsed::Bool=false)
    BookParagraph(Cell(alignment), Cell(content),
                  Cell(collapsed), Cell(nothing))
end

setfn!(b::BookParagraph, f::Function) = (setfn!(getfield(b, :content), f); b)

# ── BookList ───────────────────────────────────────────────────────────────

"""
    BookList(elements; collapsed)

An unordered list of child nodes..
"""
@document struct BookList <: BookDocument
    elements::CellVector
    collapsed::Bool
    selection::Reference
end

function BookList(elements::Vector; collapsed::Bool=false)
    BookList(CellVector(Cell[Cell(x) for x in elements]), Cell(collapsed), Cell(nothing))
end

BookList(; kwargs...) = BookList(BookDocument[]; kwargs...)

setfn!(b::BookList, f::Function) = (setfn!(getfield(b.elements, :elements), () -> Cell[Cell(x) for x in f()]); b)

# ── BookPicture ────────────────────────────────────────────────────────────

"""
    BookPicture(content; title, alignment, collapsed)

A figure with an optional title.  `content` is an image value
`alignment` is one of `:left`, `:center`, `:right`, or `:justified`.
"""
@document struct BookPicture <: BookDocument
    title::String
    alignment::Symbol
    content::Any
    collapsed::Bool
    selection::Reference
end

function BookPicture(content;
                     title::AbstractString="",
                     alignment::Symbol=:left,
                     collapsed::Bool=false)
    BookPicture(Cell(String(title)), Cell(alignment), Cell(content),
                Cell(collapsed), Cell(nothing))
end

setfn!(b::BookPicture, f::Function) = (setfn!(getfield(b, :content), f); b)

# Text-replace edits for the book domain are handled generically by
# `splice_value!` (see OperationApiModule): `title`/`author`/`numbering` are
# plain strings (string representation), and a paragraph's `content` is a
# `TextText` (the TextText representation defined in TextModule locates and
# splices the right span). No per-type method is needed.

end # module
