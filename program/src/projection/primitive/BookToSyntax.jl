"""
    BookToSyntaxModule

Book → SyntaxDocument projection. Maps each Book node type to a matching
syntax tree shape. BookBook/BookChapter/BookList produce SyntaxNodes whose
children are recursively projected sub-documents; BookParagraph and
BookPicture produce SyntaxLeaf terminals. Reference tracking follows the
same forward/backward pattern as JsonToSyntax.
"""
module BookToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..BookModule: BookDocument, BookBook, BookChapter, BookParagraph, BookList, BookPicture
import ..TextModule: TextDocument, TextString, TextText
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24, font_ubuntu_monospace_italic_24
import ..ColorModule: StyleColor, color_black, color_default, color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_cyan, color_solarized_yellow, color_solarized_gray
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference,
                         ProjectionReference, ReferencePath, EmptyReferencePath, append_reference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation
import ..SyntaxToTextModule: SyntaxNodeToText, _syntax_to_flat

export BookBookToSyntaxNode, BookChapterToSyntaxNode, BookParagraphToSyntaxLeaf,
       BookListToSyntaxNode, BookPictureToSyntaxLeaf, BookToSyntax

# ── BookBookToSyntaxNode ──────────────────────────────────────────────────────
#
# Maps BookBook → SyntaxNode.  Children layout:
#   [1]       title leaf
#   [2]       author leaf  (only when b.author !== nothing)
#   [offset…] recursively projected elements  (offset = 2 or 3)
#
# Selection forward mapping:
#   .title[k]         → .children[1].value[k]
#   .author[k]        → .children[2].value[k]  (when author present)
#   .elements[i].…    → .children[i+offset].…  (via element iomap)

struct BookBookToSyntaxNode <: Projection
    title_font::StyleFont
    title_color::StyleColor
    author_prefix_font::StyleFont
    author_prefix_color::StyleColor
    author_font::StyleFont
    author_color::StyleColor
end
BookBookToSyntaxNode(;
        title_font=font_ubuntu_monospace_bold_24,   title_color=color_solarized_blue,
        author_prefix_font=font_ubuntu_monospace_italic_24, author_prefix_color=color_solarized_gray,
        author_font=font_ubuntu_monospace_regular_24,    author_color=color_solarized_cyan) =
    BookBookToSyntaxNode(title_font, title_color, author_prefix_font, author_prefix_color,
                         author_font, author_color)


function projection_print(p::BookBookToSyntaxNode, b::BookBook, recursion, reference)
    element_iomaps = Cell(() -> [projection_print(recursion, e, recursion,
                                     @reference ^(reference).elements[i])
                                 for (i, e) in enumerate(b.elements)])

    title_sel = Cell(() -> begin
        @reference_case b.selection begin
            title.rest... => @reference value.^(rest)
        end
    end)

    author_sel = Cell(() -> begin
        @reference_case b.selection begin
            author.rest... => @reference value.^(rest)
        end
    end)

    title_leaf = SyntaxLeaf(TextString("", p.title_font, color_default), TextString("", p.title_font, color_default),
        TextString(() -> b.title, p.title_font, p.title_color),
        0, Cell(false), title_sel)

    sel = Cell(() -> begin
        path = b.selection
        path isa ConcreteReferencePath || return nothing
        h = path.head
        if h isa ProjectionReference
            return path
        end
        h isa FieldReference || return nothing
        name = h.name
        if name == "title"
            ts = title_sel[]
            ts === nothing && return nothing
            @reference children[1].^(ts)
        elseif name == "author" && b.author !== nothing
            as_ = author_sel[]
            as_ === nothing && return nothing
            @reference children[2].^(as_)
        elseif name == "elements"
            rest = path.tail
            rest isa ConcreteReferencePath || return nothing
            h2 = rest.head
            h2 isa RangeReference || return nothing
            child_i = h2.start + 1
            offset = b.author !== nothing ? 3 : 2
            iomaps = element_iomaps[]
            child_i > length(iomaps) && return nothing
            child_sel = iomaps[child_i].output.selection
            child_sel === nothing && return nothing
            child_idx = child_i + offset
            @reference children[child_idx].^(child_sel)
        else
            nothing
        end
    end)

    children_cv = CellVector(() -> begin
        author = b.author
        iomaps  = element_iomaps[]
        result  = SyntaxDocument[title_leaf]
        if author !== nothing
            a_leaf = SyntaxLeaf(
                TextString("Written by ", p.author_prefix_font, p.author_prefix_color),
                TextString("", p.author_prefix_font, color_default),
                TextString(() -> string(b.author), p.author_font, p.author_color),
                0, Cell(false), author_sel)
            push!(result, a_leaf)
        end
        for im in iomaps
            push!(result, im.output)
        end
        result
    end)

    output = SyntaxNode(TextString("", p.title_font, color_default), TextString("", p.title_font, color_default), TextString("", p.title_font, color_default),
                        children_cv, 1, b.collapsed, sel)
    ChildrenIoMap(p, b, output, element_iomaps)
end

function map_reference_forward(::BookBookToSyntaxNode,
                                iomap::ChildrenIoMap, reference)
    return _forward_book_path(iomap.input, reference)
end

function map_reference_backward(::BookBookToSyntaxNode,
                                 iomap::ChildrenIoMap, reference)
    return _backward_book_path(iomap.input, reference)
end

function projection_read(p::BookBookToSyntaxNode,
                          iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = _backward_book_path(iomap.input, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

# ── BookChapterToSyntaxNode ───────────────────────────────────────────────────
#
# Maps BookChapter → SyntaxNode.  Children layout:
#   [1]    title leaf  (prefixed with numbering when present)
#   [2…]   recursively projected elements
#
# When numbering is non-empty, the displayed string is "numbering  title".
# Backward mapping subtracts length(numbering)+2 from character indices.

struct BookChapterToSyntaxNode <: Projection
    title_font::StyleFont
    title_color::StyleColor
    numbering_font::StyleFont
    numbering_color::StyleColor
end
BookChapterToSyntaxNode(;
        title_font=font_ubuntu_monospace_bold_24,     title_color=color_solarized_blue,
        numbering_font=font_ubuntu_monospace_bold_24, numbering_color=color_solarized_magenta) =
    BookChapterToSyntaxNode(title_font, title_color, numbering_font, numbering_color)


function projection_print(p::BookChapterToSyntaxNode, b::BookChapter, recursion, reference)
    element_iomaps = Cell(() -> [projection_print(recursion, e, recursion,
                                     @reference ^(reference).elements{i})
                                 for (i, e) in enumerate(b.elements)])

    title_sel = Cell(() -> begin
        @reference_case b.selection begin
            title{s:_}.tail... => begin
                offset = let num = b.numbering; isempty(num) ? 0 : length(num) + 2 end
                adj = s + offset
                @reference value{adj}.^(tail)
            end
        end
    end)

    title_leaf = SyntaxLeaf(TextString("", p.title_font, color_default), TextString("", p.title_font, color_default),
        TextString(() -> begin
            num = b.numbering
            t   = b.title
            isempty(num) ? t : "$num  $t"
        end, p.title_font, p.title_color),
        0, Cell(false), title_sel)

    sel = Cell(() -> begin
        path = b.selection
        path isa ConcreteReferencePath || return nothing
        h = path.head
        if h isa ProjectionReference
            return path
        end
        h isa FieldReference || return nothing
        name = h.name
        if name == "title"
            ts = title_sel[]
            ts === nothing && return nothing
            @reference children{1}.^(ts)
        elseif name == "elements"
            rest = path.tail
            rest isa ConcreteReferencePath || return nothing
            h2 = rest.head
            h2 isa RangeReference || return nothing
            child_i = h2.start + 1
            iomaps  = element_iomaps[]
            child_i > length(iomaps) && return nothing
            child_sel = iomaps[child_i].output.selection
            child_sel === nothing && return nothing
            child_idx = child_i + 1
            @reference children{child_idx}.^(child_sel)
        else
            nothing
        end
    end)

    children_cv = CellVector(() -> begin
        iomaps = element_iomaps[]
        result = SyntaxDocument[title_leaf]
        for im in iomaps
            push!(result, im.output)
        end
        result
    end)

    output = SyntaxNode(TextString("", p.title_font, color_default), TextString("", p.title_font, color_default), TextString("", p.title_font, color_default),
                        children_cv, 1, b.collapsed, sel)
    ChildrenIoMap(p, b, output, element_iomaps)
end

function map_reference_forward(::BookChapterToSyntaxNode,
                                iomap::ChildrenIoMap, reference)
    return _forward_book_path(iomap.input, reference)
end

function map_reference_backward(::BookChapterToSyntaxNode,
                                 iomap::ChildrenIoMap, reference)
    return _backward_book_path(iomap.input, reference)
end

function projection_read(p::BookChapterToSyntaxNode,
                          iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = _backward_book_path(iomap.input, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

# ── BookParagraphToSyntaxLeaf ─────────────────────────────────────────────────
#
# Maps BookParagraph → SyntaxLeaf.  The paragraph content (a TextText or
# plain string) is rendered flat into the leaf value span.
#
# Selection forward:  .content → .value

struct BookParagraphToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
    placeholder_color::StyleColor
end
BookParagraphToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24,  color=color_solarized_green,
        placeholder_color=color_solarized_gray) =
    BookParagraphToSyntaxLeaf(font, color, placeholder_color)

function projection_print(p::BookParagraphToSyntaxLeaf, b::BookParagraph, recursion, reference)
    content_sel = Cell(() -> begin
        @reference_case b.selection begin
            content.rest... => @reference value.^(rest)
        end
    end)
    leaf = SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default),
        TextString(() -> _render_paragraph_content(b.content), p.font, p.color),
        0, Cell(false), content_sel)
    SimpleIoMap(p, b, leaf)
end

function map_reference_forward(::BookParagraphToSyntaxLeaf, iomap::SimpleIoMap, reference)
    return _forward_book_path(iomap.input, reference)
end

function map_reference_backward(::BookParagraphToSyntaxLeaf, iomap::SimpleIoMap, reference)
    return _backward_book_path(iomap.input, reference)
end

function projection_read(::BookParagraphToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    result = _backward_book_path(iomap.input, op.path)
    result !== nothing ? ReplaceSelectionOperation(result) : nothing
end

# ── BookListToSyntaxNode ──────────────────────────────────────────────────────
#
# Maps BookList → SyntaxNode.  Each element i is wrapped in a bullet
# SyntaxNode whose sole child is the recursively projected element:
#
#   SyntaxNode("", "", "", [
#     SyntaxNode("• ", "", "", [element_output]),  ← child i
#     ...
#   ])
#
# Selection forward:  .elements[i].… → .children[i].children[1].…

struct BookListToSyntaxNode <: Projection
    bullet_font::StyleFont
    bullet_color::StyleColor
    indentation::Int
end
BookListToSyntaxNode(; bullet_font=font_ubuntu_monospace_regular_24, bullet_color=color_solarized_yellow,
        indentation=2) =
    BookListToSyntaxNode(bullet_font, bullet_color, indentation)


function projection_print(p::BookListToSyntaxNode, b::BookList, recursion, reference)
    element_iomaps = Cell(() -> [projection_print(recursion, e, recursion,
                                     @reference ^(reference).elements{i})
                                 for (i, e) in enumerate(b.elements)])

    sel = Cell(() -> begin
        path = b.selection
        path isa ConcreteReferencePath && path.head isa ProjectionReference && return path
        @reference_case path begin
            elements{s:_}.rest... => begin
                child_i = s + 1
                iomaps  = element_iomaps[]
                child_i > length(iomaps) && return nothing
                child_sel = iomaps[child_i].output.selection
                child_sel === nothing && return nothing
                @reference children{child_i}.children{1}.^(child_sel)
            end
        end
    end)

    children_cv = CellVector(() -> begin
        iomaps = element_iomaps[]
        SyntaxDocument[
            SyntaxNode(
                TextString("• ", p.bullet_font, p.bullet_color),
                TextString("", p.bullet_font, color_default), TextString("", p.bullet_font, color_default),
                SyntaxDocument[im.output]; indentation=0)
            for im in iomaps
        ]
    end)

    output = SyntaxNode(TextString("", p.bullet_font, color_default), TextString("", p.bullet_font, color_default), TextString("", p.bullet_font, color_default),
                        children_cv, p.indentation, b.collapsed, sel)
    ChildrenIoMap(p, b, output, element_iomaps)
end

function map_reference_forward(::BookListToSyntaxNode,
                                iomap::ChildrenIoMap, reference)
    return _forward_book_path(iomap.input, reference)
end

function map_reference_backward(::BookListToSyntaxNode,
                                 iomap::ChildrenIoMap, reference)
    return _backward_book_path(iomap.input, reference)
end

function projection_read(p::BookListToSyntaxNode,
                          iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = _backward_book_path(iomap.input, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

# ── BookPictureToSyntaxLeaf ───────────────────────────────────────────────────
#
# Maps BookPicture → SyntaxLeaf.  The content (typically a file path string
# or an image document) is shown as a plain string.  When content is nothing
# or empty, a placeholder string is shown instead.
#
# Selection forward:  .content → .value

struct BookPictureToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
    placeholder_color::StyleColor
end
BookPictureToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_magenta,
        placeholder_color=color_solarized_gray) =
    BookPictureToSyntaxLeaf(font, color, placeholder_color)

function projection_print(p::BookPictureToSyntaxLeaf, b::BookPicture, recursion, reference)
    content_sel = Cell(() -> begin
        @reference_case b.selection begin
            content.rest... => @reference value.^(rest)
        end
    end)
    leaf = SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default),
        TextString(() -> begin
            c = b.content
            c === nothing ? "enter picture path" : string(c)
        end, p.font, p.color),
        0, Cell(false), content_sel)
    SimpleIoMap(p, b, leaf)
end

function map_reference_forward(::BookPictureToSyntaxLeaf, iomap::SimpleIoMap, reference)
    return _forward_book_path(iomap.input, reference)
end

function map_reference_backward(::BookPictureToSyntaxLeaf, iomap::SimpleIoMap, reference)
    return _backward_book_path(iomap.input, reference)
end

function projection_read(::BookPictureToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    result = _backward_book_path(iomap.input, op.path)
    result !== nothing ? ReplaceSelectionOperation(result) : nothing
end

# ── Compound convenience constructor ─────────────────────────────────────────

function BookToSyntax()
    TypeDispatchingProjection(
        BookBook      => BookBookToSyntaxNode(),
        BookChapter   => BookChapterToSyntaxNode(),
        BookParagraph => BookParagraphToSyntaxLeaf(),
        BookList      => BookListToSyntaxNode(),
        BookPicture   => BookPictureToSyntaxLeaf(),
    )
end

# ── Utility ───────────────────────────────────────────────────────────────────

function _render_paragraph_content(content)
    content === nothing && return ""
    content isa TextText || return string(content)
    buf = IOBuffer()
    for span in content
        span isa TextString && print(buf, span.content)
    end
    String(take!(buf))
end

# ── Type-dispatched reference helpers ────────────────────────────────────────
#
# _forward_book_path  — book-domain path  → syntax-domain path
# _backward_book_path — syntax-domain path → book-domain path
#
# Each method dispatches on the concrete book document type and recurses into
# child elements when needed, mirroring the _forward_json_path pattern.

function _forward_book_path(b::BookBook, path::ReferencePath)
    @reference_case path begin
        title.rest...     => rest isa ConcreteReferencePath && rest.head isa RangeReference ? (@reference children{1}.value.^(rest)) : nothing
        author.rest...    => (b.author !== nothing && rest isa ConcreteReferencePath && rest.head isa RangeReference) ? (@reference children{2}.value.^(rest)) : nothing
        elements{s:_}.rest... => begin
            child_i = s + 1
            elems = b.elements
            child_i > length(elems) && return nothing
            inner = _forward_book_path(elems[child_i], rest)
            inner === nothing && return nothing
            offset = b.author !== nothing ? 3 : 2
            child_idx = child_i + offset
            @reference children{child_idx}.^(inner)
        end
    end
end

function _forward_book_path(b::BookChapter, path::ReferencePath)
    @reference_case path begin
        title{s:_}.rest... => begin
            offset = let num = b.numbering; isempty(num) ? 0 : length(num) + 2 end
            adj = s + offset
            @reference children{1}.value{adj}.^(rest)
        end
        elements{s:_}.rest... => begin
            child_i = s + 1
            elems = b.elements
            child_i > length(elems) && return nothing
            inner = _forward_book_path(elems[child_i], rest)
            inner === nothing && return nothing
            child_idx = child_i + 1
            @reference children{child_idx}.^(inner)
        end
    end
end

function _forward_book_path(b::BookParagraph, path::ReferencePath)
    @reference_case path begin
        content.rest... => @reference value.^(rest)
    end
end

function _forward_book_path(b::BookList, path::ReferencePath)
    @reference_case path begin
        elements{s:_}.rest... => begin
            child_i = s + 1
            elems = b.elements
            child_i > length(elems) && return nothing
            inner = _forward_book_path(elems[child_i], rest)
            inner === nothing && return nothing
            @reference children{child_i}.children{1}.^(inner)
        end
    end
end

function _forward_book_path(b::BookPicture, path::ReferencePath)
    @reference_case path begin
        content.rest... => @reference value.^(rest)
    end
end

function _backward_book_path(b::BookBook, path::ReferencePath)
    @reference_case path begin
        children{s:_}.rest... => begin
            child_i = s + 1
            if child_i == 1
                @reference_case rest begin
                    value.tail... => @reference title.^(tail)
                end
            elseif child_i == 2 && b.author !== nothing
                @reference_case rest begin
                    value.tail... => @reference author.^(tail)
                end
            else
                offset = b.author !== nothing ? 3 : 2
                elem_i = child_i - offset
                elem_i < 1 && return nothing
                elems = b.elements
                elem_i > length(elems) && return nothing
                translated = _backward_book_path(elems[elem_i], rest)
                translated === nothing && return nothing
                @reference elements{elem_i}.^(translated)
            end
        end
    end
end

function _backward_book_path(b::BookChapter, path::ReferencePath)
    @reference_case path begin
        children{s:_}.rest... => begin
            child_i = s + 1
            if child_i == 1
                @reference_case rest begin
                    value{s2:_}.tail... => begin
                        offset = let num = b.numbering; isempty(num) ? 0 : length(num) + 2 end
                        adj = s2 - offset
                        adj < 0 && return nothing
                        @reference title{adj}.^(tail)
                    end
                end
            else
                elem_i = child_i - 1
                elems = b.elements
                elem_i > length(elems) && return nothing
                translated = _backward_book_path(elems[elem_i], rest)
                translated === nothing && return nothing
                @reference elements{elem_i}.^(translated)
            end
        end
    end
end

function _backward_book_path(b::BookParagraph, path::ReferencePath)
    @reference_case path begin
        value.rest... => @reference content.^(rest)
    end
end

function _backward_book_path(b::BookList, path::ReferencePath)
    @reference_case path begin
        children{s:_}.children{1}.tail... => begin
            child_i = s + 1
            elems = b.elements
            child_i > length(elems) && return nothing
            translated = _backward_book_path(elems[child_i], tail)
            translated === nothing && return nothing
            @reference elements{child_i}.^(translated)
        end
    end
end

function _backward_book_path(b::BookPicture, path::ReferencePath)
    @reference_case path begin
        value.rest... => @reference content.^(rest)
    end
end

end # module
