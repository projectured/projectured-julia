# Fragment of `BookModule`.
#
# Book → SyntaxDocument projection. Maps each Book node type to a matching
# syntax tree shape.
#
# The simple rules are written with `@projection_template` (like JsonToSyntax /
# XmlToSyntax): `BookInsertion` is an opaque placeholder leaf, `BookParagraph` a
# single `bound(:content)` leaf, and `BookPicture` a fixed-children node with a
# `bound(:title)` caption leaf and a `bound(:content)` figure leaf. The engine
# records the wiring, strips the markers, and derives the reference mappers and
# readers generically.
#
# `BookBook`, `BookChapter`, and `BookList` remain hand-written because their
# mapping cannot be expressed by the template markers — a conditional author leaf
# in front of a spliced collection (BookBook), a title leaf fusing numbering+title
# with a character offset (BookChapter), and a per-item bullet decorator wrapping
# each whole projected element (BookList); see the note above each. They map
# references by peeling the one step they own (title/author/numbering structural
# rewrites) and delegating each element tail through the stored child IO maps, so
# they do not dispatch on the element types — see the "Mapping references when the
# printer recurses" section of package/kernel/doc/projection-system.md.
# ── BookInsertionToSyntaxLeaf ─────────────────────────────────────────────────
#
# Maps BookInsertion → SyntaxLeaf. "insert here" is a projection-introduced
# placeholder with no editable input value (same rationale as
# JsonInsertionToSyntaxLeaf / XmlInsertionToSyntaxLeaf), so it is an opaque
# `@projection_template` leaf (no `bound`): the engine wires ∅↔∅ and nothing else.

@projection UntrackedCell struct BookInsertionToSyntaxLeaf
    style::StyleText = get_book_style(nothing, :placeholder_text)
end

@projection_template BookInsertionToSyntaxLeaf BookInsertion (prj, doc) ->
    SyntaxLeaf(TextString("insert here", prj.style))

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
#
# Kept hand-written (not @projection_template): the author leaf is *conditional*
# and precedes a spliced element collection, so the collection's child offset is 1
# or 2 depending on `author`. No template wiring expresses a conditional prefix
# combined with a spliced collection — the mixed node has a static prefix, and the
# conditional (F2) node has no spliced collection.

# Titles use a proportional (sans) font, distinct from the monospace body, and a
# larger size; the author line is italic.
@projection UntrackedCell struct BookBookToSyntaxNode
    title::StyleText         = get_book_style(nothing, :title_text)
    author_prefix::StyleText = get_book_style(nothing, :author_prefix_text)
    author::StyleText        = get_book_style(nothing, :author_text)
    sep_style::StyleText     = get_book_style(nothing, :paragraph_text)
end


function print_document(p::BookBookToSyntaxNode, recursion, b::BookBook, ctx)
    element_iomaps = Cell(@computation([print_child(recursion, e,
                                    make_child_context(ctx, b, (@reference_step elements), (@reference_step [i])))
                                 for (i, e) in enumerate(b.elements)]))

    title_sel = Cell(@computation begin
        @reference_case b.selection begin
            ::BookBook.title.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
        end
    end)

    author_sel = Cell(@computation begin
        @reference_case b.selection begin
            ::BookBook.author.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
        end
    end)

    title_leaf = SyntaxLeaf(TextString(() -> b.title, p.title); selection=title_sel)

    iomap_cell = Cell(nothing)
    mouse_target = Cell(@computation(map_mouse_target_forward(b, path -> begin
        iomap = iomap_cell[]
        iomap === nothing ? nothing : map_reference_forward(p, iomap, path)
    end)))
    sel = Cell(@computation begin
        path = b.selection
        path isa ConcreteReference || return nothing
        h = path.head
        h isa ProjectionReferenceStep && return find_introduced_path(p, path)
        h isa FieldReferenceStep || return nothing
        name = h.name
        if name == "title"
            ts = title_sel[]
            ts === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[1].^(ts)
        elseif name == "author" && b.author !== nothing
            as_ = author_sel[]
            as_ === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[2].^(as_)
        elseif name == "elements"
            rest = path.tail
            rest isa ConcreteReference || return nothing
            h2 = rest.head
            h2 isa RangeReferenceStep || return nothing
            child_i = h2.start + 1
            offset = b.author !== nothing ? 2 : 1
            iomaps = element_iomaps[]
            child_i > length(iomaps) && return nothing
            child_sel = iomaps[child_i].output.selection
            child_sel === nothing && return nothing
            child_idx = child_i + offset
            @reference ::SyntaxNode.children::CellVector[child_idx].^(child_sel)
        else
            nothing
        end
    end)

    children_cv = CellVector(@computation begin
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
                        sep=TextString("\n\n", p.sep_style),
                        collapsed=b.collapsed, selection=sel, mouse_target)
    iomap = ChildrenIoMap(p, b, output, element_iomaps)
    iomap_cell[] = iomap
    iomap
end

# Selection mapping (School A). title/author are projection-introduced leaves
# (structural rewrites); each element tail is delegated through the stored child
# IO maps. Output child offset is 3 when an author leaf is present, else 2.
function map_reference_forward(p::BookBookToSyntaxNode,
                                iomap::ChildrenIoMap, reference)
    b = iomap.input
    @reference_case reference begin
        proj(^(p), inner) => inner
        ::BookBook.title.rest...     => rest isa ConcreteReference && rest.head isa RangeReferenceStep ? (@reference ::SyntaxNode.children::CellVector[1]::SyntaxLeaf.value::TextString.^(rest)) : nothing
        ::BookBook.author.rest...    => (b.author !== nothing && rest isa ConcreteReference && rest.head isa RangeReferenceStep) ? (@reference ::SyntaxNode.children::CellVector[2]::SyntaxLeaf.value::TextString.^(rest)) : nothing
        ::BookBook.elements{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps
            child_i > length(iomaps) && return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            offset = b.author !== nothing ? 2 : 1
            child_idx = child_i + offset
            @reference ::SyntaxNode.children::CellVector[child_idx].^(inner)
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
                    __ => make_introduced_reference(p, iomap, reference)
                end
            elseif child_i == 2 && b.author !== nothing
                @reference_case rest begin
                    value.tail... => @reference ::BookBook.author.^(tail)
                    __ => make_introduced_reference(p, iomap, reference)
                end
            else
                offset = b.author !== nothing ? 2 : 1
                elem_i = child_i - offset
                elem_i < 1 && return make_introduced_reference(p, iomap, reference)
                iomaps = iomap.child_iomaps
                elem_i > length(iomaps) && return make_introduced_reference(p, iomap, reference)
                child = iomaps[elem_i]
                translated = map_reference_backward(child.projection, child, rest)
                translated === nothing && return nothing
                @reference ::BookBook.elements::CellVector[elem_i].^(translated)
            end
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::BookBookToSyntaxNode,
                          iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

# Type-in: translate a `.value[s:e]` / element `.…[s:e]` edit back to the book
# domain (`.title`, `.author`, `.elements[i].…`) through map_reference_backward,
# the single definition reused for selection reads.
function read_intent(p::BookBookToSyntaxNode,
                          iomap::ChildrenIoMap, op::ReplaceStringRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    (new_ref === nothing || has_introduced_step(new_ref)) && return nothing
    ReplaceStringRangeOperation(new_ref, op.replacement)
end

# ── BookChapterToSyntaxNode ───────────────────────────────────────────────────
#
# Maps BookChapter → SyntaxNode.  Children layout:
#   [1]    title leaf  (prefixed with numbering when present)
#   [2…]   recursively projected elements
#
# When numbering is non-empty, the displayed string is "numbering  title".
# Backward mapping subtracts length(numbering)+2 from character indices.
#
# Kept hand-written (not @projection_template): the title leaf fuses *two* input
# fields (`numbering` and `title`) into one value span with a character offset, so
# both `.title[k]` (shifted right by length(numbering)+2) and `.numbering[k]` map
# into the same leaf. A `bound(:field)`/KeySlot binds a single field with no offset.

@projection UntrackedCell struct BookChapterToSyntaxNode
    title::StyleText     = get_book_style(nothing, :chapter_title_text)
    # Reserved for styling the numbering prefix distinctly; the title leaf
    # currently renders "numbering  title" in the title style.
    numbering::StyleText = get_book_style(nothing, :numbering_text)
    sep_style::StyleText = get_book_style(nothing, :paragraph_text)
end


function print_document(p::BookChapterToSyntaxNode, recursion, b::BookChapter, ctx)
    element_iomaps = Cell(@computation([print_child(recursion, e,
                                    make_child_context(ctx, b, (@reference_step elements), (@reference_step {i})))
                                 for (i, e) in enumerate(b.elements)]))

    # The title leaf renders "numbering  title" (when numbering is present), so a
    # `.title[k]` cursor shifts right by length(numbering)+2 while a
    # `.numbering[k]` cursor maps straight onto the value span's leading region.
    title_sel = Cell(@computation begin
        @reference_case b.selection begin
            ::BookChapter.title{s:_}.tail... => begin
                offset = let num = b.numbering; isempty(num) ? 0 : length(num) + 2 end
                adj = s + offset
                @reference ::SyntaxLeaf.value::TextString{adj}.^(tail)
            end
            ::BookChapter.numbering{s:_}.tail... => @reference ::SyntaxLeaf.value::TextString{s}.^(tail)
        end
    end)

    title_leaf = SyntaxLeaf(
        TextString(() -> begin
            num = b.numbering
            t   = b.title
            isempty(num) ? t : "$num  $t"
        end, p.title);
        selection=title_sel)

    iomap_cell = Cell(nothing)
    mouse_target = Cell(@computation(map_mouse_target_forward(b, path -> begin
        iomap = iomap_cell[]
        iomap === nothing ? nothing : map_reference_forward(p, iomap, path)
    end)))
    sel = Cell(@computation begin
        path = b.selection
        path isa ConcreteReference || return nothing
        h = path.head
        h isa ProjectionReferenceStep && return find_introduced_path(p, path)
        h isa FieldReferenceStep || return nothing
        name = h.name
        if name == "title" || name == "numbering"
            ts = title_sel[]
            ts === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[1].^(ts)
        elseif name == "elements"
            rest = path.tail
            rest isa ConcreteReference || return nothing
            h2 = rest.head
            h2 isa RangeReferenceStep || return nothing
            child_i = h2.start + 1
            iomaps  = element_iomaps[]
            child_i > length(iomaps) && return nothing
            child_sel = iomaps[child_i].output.selection
            child_sel === nothing && return nothing
            child_idx = child_i + 1
            @reference ::SyntaxNode.children::CellVector[child_idx].^(child_sel)
        else
            nothing
        end
    end)

    children_cv = CellVector(@computation begin
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
                        sep=TextString("\n\n", p.sep_style),
                        collapsed=b.collapsed, selection=sel, mouse_target)
    iomap = ChildrenIoMap(p, b, output, element_iomaps)
    iomap_cell[] = iomap
    iomap
end

# Selection mapping (School A). The title leaf is projection-introduced and may
# carry a numbering prefix, so title char offsets shift by length(numbering)+2;
# each element tail is delegated through the stored child IO maps.
function map_reference_forward(p::BookChapterToSyntaxNode,
                                iomap::ChildrenIoMap, reference)
    b = iomap.input
    @reference_case reference begin
        proj(^(p), inner) => inner
        ::BookChapter.title{s:_}.rest... => begin
            offset = let num = b.numbering; isempty(num) ? 0 : length(num) + 2 end
            adj = s + offset
            @reference ::SyntaxNode.children::CellVector[1]::SyntaxLeaf.value::TextString{adj}.^(rest)
        end
        ::BookChapter.numbering{s:_}.rest... => @reference ::SyntaxNode.children::CellVector[1]::SyntaxLeaf.value::TextString{s}.^(rest)
        ::BookChapter.elements{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps
            child_i > length(iomaps) && return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            child_idx = child_i + 1
            @reference ::SyntaxNode.children::CellVector[child_idx].^(inner)
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
                            adj_s < 0 && return make_introduced_reference(p, iomap, reference)
                            @reference ::BookChapter.title::String{adj_s:adj_e}.^(tail)
                        end
                    end
                    __ => make_introduced_reference(p, iomap, reference)
                end
            else
                elem_i = child_i - 1
                iomaps = iomap.child_iomaps
                elem_i > length(iomaps) && return make_introduced_reference(p, iomap, reference)
                child = iomaps[elem_i]
                translated = map_reference_backward(child.projection, child, rest)
                translated === nothing && return nothing
                @reference ::BookChapter.elements::CellVector[elem_i].^(translated)
            end
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::BookChapterToSyntaxNode,
                          iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

# Type-in: a `.value[s:e]` edit on the title leaf maps back to `.title[s':e']`
# (shifted by the numbering prefix); element edits delegate through the child IO
# maps. map_reference_backward owns the shift and the range stays intact.
function read_intent(p::BookChapterToSyntaxNode,
                          iomap::ChildrenIoMap, op::ReplaceStringRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    (new_ref === nothing || has_introduced_step(new_ref)) && return nothing
    ReplaceStringRangeOperation(new_ref, op.replacement)
end

# ── BookParagraphToSyntaxLeaf ─────────────────────────────────────────────────
#
# Maps BookParagraph → SyntaxLeaf.  The paragraph content (a TextBlock or
# plain string) is rendered flat into the leaf value span.
#
# Selection forward:  .content → .value

@projection UntrackedCell struct BookParagraphToSyntaxLeaf
    style::StyleText = get_book_style(nothing, :paragraph_text)
    # Reserved for an empty-content placeholder hint (not yet rendered).
    placeholder::StyleText = get_book_style(nothing, :placeholder_text)
end

# A single bound leaf (like XmlTextToSyntaxLeaf / MarkdownTextToSyntaxLeaf): the
# `.content` field is rendered flat into the leaf's `.value` span, so a `.content`
# cursor maps to `.value` and back. The engine derives every reader from the
# `bound(:content, …)` wiring. Type-in on the flat span is spliced back into the
# paragraph's `content` (a TextBlock) generically by `splice_value!`.
@projection_template BookParagraphToSyntaxLeaf BookParagraph (prj, doc) ->
    SyntaxLeaf(bound(:content, String,
                     TextString(() -> _render_paragraph_content(doc.content), prj.style)))

# ── BookListToSyntaxNode ──────────────────────────────────────────────────────
#
# Maps BookList → SyntaxNode.  Each element i is wrapped in a bullet
# SyntaxNode whose sole child is the recursively projected element:
#
#   SyntaxNode([
#     SyntaxNode([element_output]; open = "• "),  ← child i
#     ...
#   ])
#
# Selection forward:  .elements[i].… → .children[i].content.… (the bullet is a delimitation)
#
# Kept hand-written (not @projection_template): each element is wrapped in a
# per-item bullet decorator node around the *whole* projected element (School A
# delegation to the element's own projection, like MarkdownListToStyledNode). The
# template's homogeneous `collection(:elements)` maps `.elements[i]→.children[i]`
# with no per-item wrapper, and its element-builder form (`collection(:f) do x`)
# builds a node from x's *fields* — neither expresses "wrap the whole element".

@projection UntrackedCell struct BookListToSyntaxNode
    bullet::StyleText = get_book_style(nothing, :bullet_text)
    indentation::Int = 2
end


function print_document(p::BookListToSyntaxNode, recursion, b::BookList, ctx)
    element_iomaps = Cell(@computation([print_child(recursion, e,
                                    make_child_context(ctx, b, (@reference_step elements), (@reference_step {i})))
                                 for (i, e) in enumerate(b.elements)]))

    iomap_cell = Cell(nothing)
    mouse_target = Cell(@computation(map_mouse_target_forward(b, path -> begin
        iomap = iomap_cell[]
        iomap === nothing ? nothing : map_reference_forward(p, iomap, path)
    end)))
    sel = Cell(@computation begin
        path = b.selection
        is_introduced_reference(path) && return find_introduced_path(p, path)
        @reference_case path begin
            ::BookList.elements{s:_}.rest... => begin
                child_i = s + 1
                iomaps  = element_iomaps[]
                child_i > length(iomaps) && return nothing
                child_sel = iomaps[child_i].output.selection
                child_sel === nothing && return nothing
                @reference ::SyntaxNode.children::CellVector[child_i]::SyntaxDelimitation.content.^(child_sel)
            end
        end
    end)

    children_cv = CellVector(@computation begin
        iomaps = element_iomaps[]
        SyntaxDocument[
            SyntaxDelimitation(im.output; opening_delimiter=TextString("• ", p.bullet))
            for im in iomaps
        ]
    end)

    output = SyntaxNode(children_cv; indentation=p.indentation, collapsed=b.collapsed, selection=sel, mouse_target)
    iomap = ChildrenIoMap(p, b, output, element_iomaps)
    iomap_cell[] = iomap
    iomap
end

# Selection mapping (School A). Each element i is wrapped in a bullet SyntaxNode
# whose sole child (index 1) is the projected element, so .elements[i] maps to
# .children[i].content and the tail is delegated through the child IO map.
function map_reference_forward(p::BookListToSyntaxNode,
                                iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        proj(^(p), inner) => inner
        ::BookList.elements{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps
            child_i > length(iomaps) && return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[child_i]::SyntaxDelimitation.content.^(inner)
        end
    end
end

function map_reference_backward(p::BookListToSyntaxNode,
                                 iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ::SyntaxNode.children{s:_}.content.tail... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps
            child_i > length(iomaps) && return make_introduced_reference(p, iomap, reference)
            child = iomaps[child_i]
            translated = map_reference_backward(child.projection, child, tail)
            translated === nothing && return nothing
            @reference ::BookList.elements::CellVector[child_i].^(translated)
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::BookListToSyntaxNode,
                          iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

# Type-in: each bullet wraps its element at `.children[i].content`; the edit
# delegates through the child IO map back to `.elements[i].…`.
function read_intent(p::BookListToSyntaxNode,
                          iomap::ChildrenIoMap, op::ReplaceStringRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    (new_ref === nothing || has_introduced_step(new_ref)) && return nothing
    ReplaceStringRangeOperation(new_ref, op.replacement)
end

# ── BookPictureToSyntaxLeaf ───────────────────────────────────────────────────
#
# Maps BookPicture → SyntaxNode with two leaves: a caption leaf (the title) and
# a content leaf (the file path / image). Both are editable; each maps onto its
# own value span:
#   .title[k]   → .children[1].value[k]
#   .content[k] → .children[2].value[k]
# An empty title renders "untitled"; an empty content renders the path
# placeholder. Written as an `@projection_template` fixed-children node.

@projection UntrackedCell struct BookPictureToSyntaxLeaf
    style::StyleText       = get_book_style(nothing, :picture_text)
    placeholder::StyleText = get_book_style(nothing, :placeholder_text)
end

# The value span for a picture's content: when the content is a path to an image
# file on disk, an inline `TextGraphics` carrying a lazily-decoded `ImageFile`
# (which `SyntaxToText`/`WordWrapping`/`TextToGraphics` render as an image, sized
# to its natural extent capped at `max_w`); otherwise the path/placeholder text.
# The field type on `SyntaxLeaf.value` is only a hint — the Cell holds either.
function _picture_leaf_value(content, placeholder::StyleText; max_w::Int = 640)
    if content isa GraphicsDocument
        # A pre-projected sub-document (e.g. a `WidgetTable` run through
        # `WidgetToGraphics`, or any ad-hoc `GraphicsCanvas`): embed the graphics
        # live, exactly like an image span but WITHOUT rasterizing — TextToGraphics
        # splices the canvas in as a nested, real graphics element. Sized to the
        # canvas's own `w`/`h` (a `GraphicsCanvas` carries them; else zero).
        gw = Cell(@computation Int32(hasproperty(content, :w) ? Int(content.w) : 0))
        gh = Cell(@computation Int32(hasproperty(content, :h) ? Int(content.h) : 0))
        return TextGraphics(Cell(content), gw, gh, Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    end
    if content isa AbstractString && !isempty(content) && isfile(String(content))
        path = String(content)
        img  = ImageFile(path)
        raw  = getfield(img, :raw)
        set_cell_computation!(raw, () -> (try decode_image(path) catch; nothing end))
        _nat(i, fb) = (r = raw[]; (r isa Tuple && length(r) == 3) ? Int(r[i]) : fb)
        dw = Cell(@computation Int32(min(_nat(2, 720), max_w)))
        dh = Cell(@computation begin w = min(_nat(2, 720), max_w); Int32(round(Int, _nat(3, 460) * w / _nat(2, 720))) end)
        return TextGraphics(Cell(img), dw, dh, Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    end
    TextString(content === nothing ? "enter picture path" : string(content), placeholder)
end

# A fixed-children node with two bound leaves (like MarkdownImageToSyntaxNode's
# source form / XmlElement's `name="value"` attributes): the caption leaf is
# `bound(:title)`, the figure leaf `bound(:content)`. The engine wires each
# `.field{k} ↔ .children[k].value{k}` and derives the readers. The content leaf's
# value is a live image / graphics span or the path text (`_picture_leaf_value`);
# the fixed-node KeySlot mapping keys on the field name only, so it is agnostic to
# whether the rendered value is a `TextString` or a `TextGraphics`.
@projection_template BookPictureToSyntaxLeaf BookPicture (prj, doc) ->
    SyntaxNode(nothing, nothing, TextString("\n", prj.placeholder),
        [ SyntaxLeaf(bound(:title, String,
                           TextString(() -> isempty(doc.title) ? "untitled" : doc.title, prj.style))),
          SyntaxLeaf(bound(:content, String,
                           _picture_leaf_value(doc.content, prj.placeholder))) ],
        0, false, nothing)

# The newline `sep` between caption and figure is a projection-introduced position
# with no input pre-image. The generic template `ReplaceSelectionOperation`
# fallback would wrap such an unmapped caret in a `ProjectionReferenceStep`, which
# `strip_reference_types` cannot collapse — growing the path without bound on every
# navigation round-trip (the reason XmlElementToSyntaxNode adds a flat-offset
# reader). Match the previous behaviour instead: an unmapped caret yields nothing
# (that position is simply not selectable), which keeps navigation bounded.
# Everything else — the printer, both reference mappers, and the type-in reader —
# comes from the template.
function read_intent(p::BookPictureToSyntaxLeaf, iomap::TemplateIoMap,
                     op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing ? make_path_operation(op, result) : nothing
end

# ── Compound convenience constructor ─────────────────────────────────────────

"""
    BookToSyntax(; theme = nothing)

Build the Book → Syntax projection: one rule per document type. The builder
gives each projection the style of its role with `get_book_style`, from
`theme`, a `BookTheme` scaled or not, or the default styles for `nothing`.
"""
function BookToSyntax(; theme = nothing)
    get_style(name) = get_book_style(theme, name)
    TypeDispatchingProjection(
        BookInsertion => BookInsertionToSyntaxLeaf(; style = get_style(:placeholder_text)),
        BookBook      => BookBookToSyntaxNode(; title = get_style(:title_text),
                                                 author_prefix = get_style(:author_prefix_text),
                                                 author = get_style(:author_text),
                                                 sep_style = get_style(:paragraph_text)),
        BookChapter   => BookChapterToSyntaxNode(; title = get_style(:chapter_title_text),
                                                    numbering = get_style(:numbering_text),
                                                    sep_style = get_style(:paragraph_text)),
        BookParagraph => BookParagraphToSyntaxLeaf(; style = get_style(:paragraph_text),
                                                      placeholder = get_style(:placeholder_text)),
        BookList      => BookListToSyntaxNode(; bullet = get_style(:bullet_text)),
        BookPicture   => BookPictureToSyntaxLeaf(; style = get_style(:picture_text),
                                                    placeholder = get_style(:placeholder_text)),
    )
end

# ── Utility ───────────────────────────────────────────────────────────────────

# The string of a paragraph. Of a `TextBlock`, the flat string, so an offset in
# the leaf is an offset of the caret space, the space in which `splice_value!`
# writes an edit back into the block.
function _render_paragraph_content(content)
    content === nothing && return ""
    content isa TextBlock || return string(content)
    get_flat_string(content)
end

# ── Natural-projection registration ─────────────────────────────────────────
# The row that teaches the render-anything projection what this domain is. The
# factory form, so every renderer builds its own projection instance.

function __init__()
    register_natural_syntax!(:book, (; appearance) -> Pair{Type,Any}[
        BookDocument => BookToSyntax(theme = get_scaled_theme!(appearance, BookTheme))])
end
