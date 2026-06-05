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

function Base.show(io::IO, b::BookBook)
    print(io, "BookBook(title=", repr(b.title),
          ", elements=", length(b.elements), ")")
end

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

function Base.show(io::IO, b::BookChapter)
    print(io, "BookChapter(title=", repr(b.title),
          ", numbering=", repr(b.numbering),
          ", elements=", length(b.elements), ")")
end

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

function Base.show(io::IO, b::BookParagraph)
    print(io, "BookParagraph(alignment=", b.alignment, ", content=", b.content, ")")
end

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

function Base.show(io::IO, b::BookList)
    print(io, "BookList(elements=", length(b.elements), ")")
end

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

function Base.show(io::IO, b::BookPicture)
    print(io, "BookPicture(title=", repr(b.title),
          ", alignment=", b.alignment, ")")
end

end # module
