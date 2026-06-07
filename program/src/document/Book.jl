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
import ..OperationApiModule: _apply_string_replace!
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

# ── String-replace operations ────────────────────────────────────────────
#
# Type-in targets for the book domain. Each method mirrors the leaf the
# corresponding BookToSyntax projection renders into, so the reference arriving
# from the projection (`.title[s:e]`, `.author[s:e]`, `.content[s:e]`) lands on
# the right field. Boundaries are 0-based character offsets.

function _apply_string_replace!(target::BookBook, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    if field_name == "title"
        target.title = _book_slice_replace(target.title::AbstractString, s, e, replacement)
    elseif field_name == "author"
        old = target.author === nothing ? "" : string(target.author)
        target.author = _book_slice_replace(old, s, e, replacement)
    else
        error("BookBook supports only fields 'title', 'author', got: $field_name")
    end
end

function _apply_string_replace!(target::BookChapter, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    if field_name == "title"
        target.title = _book_slice_replace(target.title::AbstractString, s, e, replacement)
    elseif field_name == "numbering"
        target.numbering = _book_slice_replace(target.numbering::AbstractString, s, e, replacement)
    else
        error("BookChapter supports only fields 'title', 'numbering', got: $field_name")
    end
end

function _apply_string_replace!(target::BookParagraph, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    field_name == "content" || error("BookParagraph supports only field 'content', got: $field_name")
    content = target.content
    if content isa TextText
        _book_texttext_replace!(content, s, e, replacement)
    else
        old = content === nothing ? "" : string(content)
        target.content = _book_slice_replace(old, s, e, replacement)
    end
end

function _apply_string_replace!(target::BookPicture, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    if field_name == "content"
        old = target.content === nothing ? "" : string(target.content)
        target.content = _book_slice_replace(old, s, e, replacement)
    elseif field_name == "title"
        target.title = _book_slice_replace(target.title::AbstractString, s, e, replacement)
    else
        error("BookPicture supports only fields 'content', 'title', got: $field_name")
    end
end

# Character-aware replacement helper (positions are 0-based char offsets).
function _book_slice_replace(old::AbstractString, s::Int, e::Int, replacement::AbstractString)
    n = length(old)
    left  = s <= 0 ? "" : first(old, s)
    right = e >= n ? "" : last(old, n - e)
    String(left) * replacement * String(right)
end

# A paragraph renders its `TextText` content flattened into a single syntax
# leaf, so the incoming `[s:e]` is a flat offset across the concatenated spans.
# Locate the single `TextString` span the range falls inside and edit it; an
# empty paragraph grows a fresh span. Ranges that straddle two spans are left
# for a later multi-span editing pass (the leaf-local decision in the type-in
# plan).
function _book_texttext_replace!(tt::TextText, s::Int, e::Int, replacement::AbstractString)
    pos = 0
    have_span = false
    for span in tt
        span isa TextString || continue
        have_span = true
        len = length(span.content)
        if s >= pos && e <= pos + len
            span.content = _book_slice_replace(span.content, s - pos, e - pos, replacement)
            return
        end
        pos += len
    end
    have_span || push!(tt, TextString(replacement))
end

end # module
