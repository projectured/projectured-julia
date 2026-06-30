"""
    BookToSyntaxModule

Book → SyntaxDocument projection. Maps each Book node type to a matching
syntax tree shape. BookBook/BookChapter/BookList produce SyntaxNodes whose
children are recursively projected sub-documents; BookParagraph and
BookPicture produce SyntaxLeaf terminals. The node projections map references
by peeling the one step they own (title/author/numbering structural rewrites)
and delegating each element tail through the stored child IO maps, so they do
not dispatch on the element types — see the "Mapping references when the printer
recurses" section of documentation/projection-system.md.
"""
module BookToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..BookModule: BookDocument, BookInsertion, BookBook, BookChapter, BookParagraph, BookList, BookPicture
import ..TextModule: TextDocument, TextString, TextText
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20, font_ubuntu_monospace_italic_20
import ..ColorModule: StyleColor, color_black, color_default, color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_cyan, color_solarized_yellow, color_solarized_gray
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference,
                         ProjectionReference, ReferencePath, EmptyReferencePath, append_reference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: StringReplaceRangeOperation
import ..SyntaxToTextModule: SyntaxNodeToText, _syntax_to_flat
import ..PrinterContextModule: child_context

export BookInsertionToSyntaxLeaf, BookBookToSyntaxNode, BookChapterToSyntaxNode, BookParagraphToSyntaxLeaf,
       BookListToSyntaxNode, BookPictureToSyntaxLeaf, BookToSyntax

# ── BookInsertionToSyntaxLeaf ─────────────────────────────────────────────────
#
# Maps BookInsertion → SyntaxLeaf. "insert here" is a projection-introduced
# placeholder with no editable input value (same rationale as
# JsonInsertionToSyntaxLeaf), so the default proj-unwrapping forward mapper is
# correct and the iomap is threaded canonically.

@projection struct BookInsertionToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

function projection_print(p::BookInsertionToSyntaxLeaf, recursion, b::BookInsertion, ctx)
    output_selection = Cell(() -> map_reference_forward(p, nothing, b.selection))
    SimpleIoMap(p, b, SyntaxLeaf(TextString("insert here", p.style); selection=output_selection))
end

# ── BookBookToSyntaxNode ──────────────────────────────────────────────────────
#
# Maps BookBook → SyntaxNode.  Children layout:
#   [1]            title leaf
#   [2]            author leaf  (only when b.author !== nothing)
#   [1+offset…]    recursively projected elements  (offset = 1 or 2)
#
# Selection forward mapping:
#   .title[k]         → .children[1].value[k]
#   .author[k]        → .children[2].value[k]  (when author present)
#   .elements[i].…    → .children[i+offset].…  (via element iomap)

@projection struct BookBookToSyntaxNode
    title::StyleText        = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    author_prefix::StyleText = StyleText(font_ubuntu_monospace_italic_20, color_solarized_gray)
    author::StyleText       = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end


function projection_print(p::BookBookToSyntaxNode, recursion, b::BookBook, ctx)
    element_iomaps = Cell(() -> [projection_printer_recurse(recursion, e,
                                     child_context(ctx, @reference ^(ctx.reference).elements[i]))
                                 for (i, e) in enumerate(b.elements)])

    title_sel = Cell(() -> begin
        @reference_case b.selection begin
            title.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
        end
    end)

    author_sel = Cell(() -> begin
        @reference_case b.selection begin
            author.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
        end
    end)

    title_leaf = SyntaxLeaf(TextString(() -> b.title, p.title); selection=title_sel)

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
            @reference ::SyntaxNode.children[1].^(ts)
        elseif name == "author" && b.author !== nothing
            as_ = author_sel[]
            as_ === nothing && return nothing
            @reference ::SyntaxNode.children[2].^(as_)
        elseif name == "elements"
            rest = path.tail
            rest isa ConcreteReferencePath || return nothing
            h2 = rest.head
            h2 isa RangeReference || return nothing
            child_i = h2.start + 1
            offset = b.author !== nothing ? 2 : 1
            iomaps = element_iomaps[]
            child_i > length(iomaps) && return nothing
            child_sel = iomaps[child_i].output.selection
            child_sel === nothing && return nothing
            child_idx = child_i + offset
            @reference ::SyntaxNode.children[child_idx].^(child_sel)
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
                TextString(() -> string(b.author), p.author);
                open=TextString("Written by ", p.author_prefix),
                selection=author_sel)
            push!(result, a_leaf)
        end
        for im in iomaps
            push!(result, im.output)
        end
        result
    end)

    # Flush-left prose blocks: indentation=0 drops the depth-based indent (an
    # indent before every chapter/paragraph is atypical for English text), while
    # a newline `sep` still puts each child (title, author, chapters, paragraphs)
    # on its own line. Embedded code fragments are separate SyntaxNodes, so they
    # keep their own internal indentation.
    output = SyntaxNode(children_cv; indentation=0,
                        sep=TextString("\n", font_ubuntu_monospace_regular_20, color_black),
                        collapsed=b.collapsed, selection=sel)
    ChildrenIoMap(p, b, output, element_iomaps)
end

# Selection mapping (School A). title/author are projection-introduced leaves
# (structural rewrites); each element tail is delegated through the stored child
# IO maps. Output child offset is 3 when an author leaf is present, else 2.
function map_reference_forward(p::BookBookToSyntaxNode,
                                iomap::ChildrenIoMap, reference)
    b = iomap.input
    @reference_case reference begin
        ::BookBook.title.rest...     => rest isa ConcreteReferencePath && rest.head isa RangeReference ? (@reference ::SyntaxNode.children[1].value::TextString.^(rest)) : nothing
        ::BookBook.author.rest...    => (b.author !== nothing && rest isa ConcreteReferencePath && rest.head isa RangeReference) ? (@reference ::SyntaxNode.children[2].value::TextString.^(rest)) : nothing
        ::BookBook.elements{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            child_i > length(iomaps) && return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            offset = b.author !== nothing ? 2 : 1
            child_idx = child_i + offset
            @reference ::SyntaxNode.children[child_idx].^(inner)
        end
    end
end

function map_reference_backward(p::BookBookToSyntaxNode,
                                 iomap::ChildrenIoMap, reference)
    b = iomap.input
    @reference_case reference begin
        ::SyntaxNode.children{s:_}.rest... => begin
            child_i = s + 1
            if child_i == 1
                @reference_case rest begin
                    value.tail... => @reference ::BookBook.title::String.^(tail)
                end
            elseif child_i == 2 && b.author !== nothing
                @reference_case rest begin
                    value.tail... => @reference ::BookBook.author.^(tail)
                end
            else
                offset = b.author !== nothing ? 2 : 1
                elem_i = child_i - offset
                elem_i < 1 && return nothing
                iomaps = iomap.child_iomaps[]
                elem_i > length(iomaps) && return nothing
                child = iomaps[elem_i]
                translated = map_reference_backward(child.projection, child, rest)
                translated === nothing && return nothing
                @reference ::BookBook.elements[elem_i].^(translated)
            end
        end
    end
end

function projection_read(p::BookBookToSyntaxNode,
                          iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

# Type-in: translate a `.value[s:e]` / element `.…[s:e]` edit back to the book
# domain (`.title`, `.author`, `.elements[i].…`) through map_reference_backward,
# the single definition reused for selection reads.
function projection_read(p::BookBookToSyntaxNode,
                          iomap::ChildrenIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

# ── BookChapterToSyntaxNode ───────────────────────────────────────────────────
#
# Maps BookChapter → SyntaxNode.  Children layout:
#   [1]    title leaf  (prefixed with numbering when present)
#   [2…]   recursively projected elements
#
# When numbering is non-empty, the displayed string is "numbering  title".
# Backward mapping subtracts length(numbering)+2 from character indices.

@projection struct BookChapterToSyntaxNode
    title::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    # Reserved for styling the numbering prefix distinctly; the title leaf
    # currently renders "numbering  title" in the title style.
    numbering::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end


function projection_print(p::BookChapterToSyntaxNode, recursion, b::BookChapter, ctx)
    element_iomaps = Cell(() -> [projection_printer_recurse(recursion, e,
                                     child_context(ctx, @reference ^(ctx.reference).elements{i}))
                                 for (i, e) in enumerate(b.elements)])

    # The title leaf renders "numbering  title" (when numbering is present), so a
    # `.title[k]` cursor shifts right by length(numbering)+2 while a
    # `.numbering[k]` cursor maps straight onto the value span's leading region.
    title_sel = Cell(() -> begin
        @reference_case b.selection begin
            title{s:_}.tail... => begin
                offset = let num = b.numbering; isempty(num) ? 0 : length(num) + 2 end
                adj = s + offset
                @reference value{adj}.^(tail)
            end
            numbering{s:_}.tail... => @reference value{s}.^(tail)
        end
    end)

    title_leaf = SyntaxLeaf(
        TextString(() -> begin
            num = b.numbering
            t   = b.title
            isempty(num) ? t : "$num  $t"
        end, p.title);
        selection=title_sel)

    sel = Cell(() -> begin
        path = b.selection
        path isa ConcreteReferencePath || return nothing
        h = path.head
        if h isa ProjectionReference
            return path
        end
        h isa FieldReference || return nothing
        name = h.name
        if name == "title" || name == "numbering"
            ts = title_sel[]
            ts === nothing && return nothing
            @reference ::SyntaxNode.children[1].^(ts)
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
            @reference ::SyntaxNode.children[child_idx].^(child_sel)
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

    # Flush-left prose blocks: indentation=0 drops the depth-based indent (an
    # indent before every chapter/paragraph is atypical for English text), while
    # a newline `sep` still puts each child (title, author, chapters, paragraphs)
    # on its own line. Embedded code fragments are separate SyntaxNodes, so they
    # keep their own internal indentation.
    output = SyntaxNode(children_cv; indentation=0,
                        sep=TextString("\n", font_ubuntu_monospace_regular_20, color_black),
                        collapsed=b.collapsed, selection=sel)
    ChildrenIoMap(p, b, output, element_iomaps)
end

# Selection mapping (School A). The title leaf is projection-introduced and may
# carry a numbering prefix, so title char offsets shift by length(numbering)+2;
# each element tail is delegated through the stored child IO maps.
function map_reference_forward(p::BookChapterToSyntaxNode,
                                iomap::ChildrenIoMap, reference)
    b = iomap.input
    @reference_case reference begin
        ::BookChapter.title{s:_}.rest... => begin
            offset = let num = b.numbering; isempty(num) ? 0 : length(num) + 2 end
            adj = s + offset
            @reference ::SyntaxNode.children[1].value::TextString{adj}.^(rest)
        end
        ::BookChapter.numbering{s:_}.rest... => @reference ::SyntaxNode.children[1].value::TextString{s}.^(rest)
        ::BookChapter.elements{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            child_i > length(iomaps) && return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            child_idx = child_i + 1
            @reference ::SyntaxNode.children[child_idx].^(inner)
        end
    end
end

function map_reference_backward(p::BookChapterToSyntaxNode,
                                 iomap::ChildrenIoMap, reference)
    b = iomap.input
    @reference_case reference begin
        ::SyntaxNode.children{s:_}.rest... => begin
            child_i = s + 1
            if child_i == 1
                @reference_case rest begin
                    value{s2:e2}.tail... => begin
                        num = b.numbering
                        if !isempty(num) && e2 <= length(num)
                            # leading region of the value span is the numbering
                            @reference ::BookChapter.numbering::String{s2:e2}.^(tail)
                        else
                            offset = isempty(num) ? 0 : length(num) + 2
                            adj_s = s2 - offset
                            adj_e = e2 - offset
                            adj_s < 0 && return nothing
                            @reference ::BookChapter.title::String{adj_s:adj_e}.^(tail)
                        end
                    end
                end
            else
                elem_i = child_i - 1
                iomaps = iomap.child_iomaps[]
                elem_i > length(iomaps) && return nothing
                child = iomaps[elem_i]
                translated = map_reference_backward(child.projection, child, rest)
                translated === nothing && return nothing
                @reference ::BookChapter.elements[elem_i].^(translated)
            end
        end
    end
end

function projection_read(p::BookChapterToSyntaxNode,
                          iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

# Type-in: a `.value[s:e]` edit on the title leaf maps back to `.title[s':e']`
# (shifted by the numbering prefix); element edits delegate through the child IO
# maps. map_reference_backward owns the shift and the range stays intact.
function projection_read(p::BookChapterToSyntaxNode,
                          iomap::ChildrenIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

# ── BookParagraphToSyntaxLeaf ─────────────────────────────────────────────────
#
# Maps BookParagraph → SyntaxLeaf.  The paragraph content (a TextText or
# plain string) is rendered flat into the leaf value span.
#
# Selection forward:  .content → .value

@projection struct BookParagraphToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_black)
    # Reserved for an empty-content placeholder hint (not yet rendered).
    placeholder::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

function projection_print(p::BookParagraphToSyntaxLeaf, recursion, b::BookParagraph, ctx)
    content_sel = Cell(() -> begin
        @reference_case b.selection begin
            content.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
        end
    end)
    leaf = SyntaxLeaf(TextString(() -> _render_paragraph_content(b.content), p.style); selection=content_sel)
    SimpleIoMap(p, b, leaf)
end

function map_reference_forward(::BookParagraphToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ::BookParagraph.content.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
    end
end

function map_reference_backward(::BookParagraphToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ::SyntaxLeaf.value.rest... => @reference ::BookParagraph.content.^(rest)
    end
end

function projection_read(p::BookParagraphToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing ? ReplaceSelectionOperation(result) : nothing
end

# Type-in: `.value[s:e]` → `.content[s:e]` (the paragraph's flat content range).
function projection_read(p::BookParagraphToSyntaxLeaf, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
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

@projection struct BookListToSyntaxNode
    bullet::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    indentation::Int = 2
end


function projection_print(p::BookListToSyntaxNode, recursion, b::BookList, ctx)
    element_iomaps = Cell(() -> [projection_printer_recurse(recursion, e,
                                     child_context(ctx, @reference ^(ctx.reference).elements{i}))
                                 for (i, e) in enumerate(b.elements)])

    sel = Cell(() -> begin
        path = b.selection
        path isa ConcreteReferencePath && path.head isa ProjectionReference && return b.selection
        @reference_case path begin
            elements{s:_}.rest... => begin
                child_i = s + 1
                iomaps  = element_iomaps[]
                child_i > length(iomaps) && return nothing
                child_sel = iomaps[child_i].output.selection
                child_sel === nothing && return nothing
                @reference ::SyntaxNode.children[child_i].children[1].^(child_sel)
            end
        end
    end)

    children_cv = CellVector(() -> begin
        iomaps = element_iomaps[]
        SyntaxDocument[
            SyntaxNode(SyntaxDocument[im.output]; open=TextString("• ", p.bullet))
            for im in iomaps
        ]
    end)

    output = SyntaxNode(children_cv; indentation=p.indentation, collapsed=b.collapsed, selection=sel)
    ChildrenIoMap(p, b, output, element_iomaps)
end

# Selection mapping (School A). Each element i is wrapped in a bullet SyntaxNode
# whose sole child (index 1) is the projected element, so .elements[i] maps to
# .children[i].children[1] and the tail is delegated through the child IO map.
function map_reference_forward(p::BookListToSyntaxNode,
                                iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ::BookList.elements{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            child_i > length(iomaps) && return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children[child_i].children[1].^(inner)
        end
    end
end

function map_reference_backward(p::BookListToSyntaxNode,
                                 iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ::SyntaxNode.children{s:_}.children[1].tail... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            child_i > length(iomaps) && return nothing
            child = iomaps[child_i]
            translated = map_reference_backward(child.projection, child, tail)
            translated === nothing && return nothing
            @reference ::BookList.elements[child_i].^(translated)
        end
    end
end

function projection_read(p::BookListToSyntaxNode,
                          iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

# Type-in: each bullet wraps its element at `.children[i].children[1]`; the edit
# delegates through the child IO map back to `.elements[i].…`.
function projection_read(p::BookListToSyntaxNode,
                          iomap::ChildrenIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

# ── BookPictureToSyntaxLeaf ───────────────────────────────────────────────────
#
# Maps BookPicture → SyntaxNode with two leaves: a caption leaf (the title) and
# a content leaf (the file path / image). Both are editable; each maps onto its
# own value span:
#   .title[k]   → .children[1].value[k]
#   .content[k] → .children[2].value[k]
# An empty title renders a gray placeholder so the caption still has a cursor;
# an empty content renders the path placeholder.

@projection struct BookPictureToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    placeholder::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

function projection_print(p::BookPictureToSyntaxLeaf, recursion, b::BookPicture, ctx)
    title_sel = Cell(() -> begin
        @reference_case b.selection begin
            title.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
        end
    end)
    content_sel = Cell(() -> begin
        @reference_case b.selection begin
            content.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
        end
    end)
    title_leaf = SyntaxLeaf(
        TextString(() -> begin
            t = b.title
            isempty(t) ? "untitled" : t
        end, p.style);
        selection=title_sel)
    content_leaf = SyntaxLeaf(
        TextString(() -> begin
            c = b.content
            c === nothing ? "enter picture path" : string(c)
        end, p.style);
        selection=content_sel)
    node = SyntaxNode(
        CellVector(Cell[Cell(title_leaf), Cell(content_leaf)]);
        sep=TextString(": ", p.placeholder))
    SimpleIoMap(p, b, node)
end

function map_reference_forward(::BookPictureToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ::BookPicture.title.rest...   => @reference ::SyntaxNode.children[1].value::TextString.^(rest)
        ::BookPicture.content.rest... => @reference ::SyntaxNode.children[2].value::TextString.^(rest)
    end
end

function map_reference_backward(::BookPictureToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ::SyntaxNode.children{s:_}.value.rest... => begin
            child_i = s + 1
            child_i == 1 ? (@reference ::BookPicture.title::String.^(rest)) :
            child_i == 2 ? (@reference ::BookPicture.content.^(rest)) : nothing
        end
    end
end

function projection_read(p::BookPictureToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing ? ReplaceSelectionOperation(result) : nothing
end

# Type-in: `.value[s:e]` → `.content[s:e]` (the picture path string range).
function projection_read(p::BookPictureToSyntaxLeaf, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

# ── Compound convenience constructor ─────────────────────────────────────────

function BookToSyntax()
    TypeDispatchingProjection(
        BookInsertion => BookInsertionToSyntaxLeaf(),
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
    for span in content.elements
        span isa TextString && print(buf, span.content)
    end
    String(take!(buf))
end

end # module
