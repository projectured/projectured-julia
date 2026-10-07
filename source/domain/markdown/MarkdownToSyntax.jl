# Fragment of `MarkdownModule`.
#
# Markdown → SyntaxDocument projection with two presentations, selected by
# `MarkdownToSyntax(; style)`:
#
# - `:source` (default) — colourised **raw markdown**: `#` headings, `**bold**`,
#   `` `code` ``, `[text](url)`, `- ` bullets, ` ``` ` fences, `>` quotes, `---`.
#   Every marker is an editable text span. Written entirely with
#   `@projection_template`, so the reader is derived from the wiring.
# - `:rendered` — **formatted markdown**, marker-free: big bold headings, real
#   bold/italic, plain inline code, `•` bullets, `▏` quote bars, `───` rules, blue
#   links. Inline font weight/size cascades from a container to its descendant text
#   via an ambient `:md_style` carried in the printer context (School A: containers
#   delegate to their children and only *augment* the ambient style; the leaf reads
#   it). This mirrors YAML's `YamlToSyntax(; style)`: most rules stay on
#   `@projection_template` (rendered field values), only the cascading nodes
#   (Text/Strong/Emphasis/Heading/Link) are hand-written.
#
# Every rule holds its styles as fields; `MarkdownToSyntax` fills them with
# `get_markdown_style`, from `theme`, scaled or not (`MarkdownTheme.jl`). With no
# theme a projection holds the plain values of the default theme.
#
# Blocks stack flush-left (`indentation=0` + a newline `sep`, the BookToSyntax
# idiom); inline runs concatenate (a `SyntaxConcatenation`).

# ══════════════════════════════════════════════════════════════════════════════
# Source view (style = :source) — colourised raw markdown, all @projection_template
# ══════════════════════════════════════════════════════════════════════════════

# ── MarkdownInsertionToSyntaxLeaf ─────────────────────────────────────────────

@projection UntrackedCell struct MarkdownInsertionToSyntaxLeaf
    style::StyleText = get_markdown_style(nothing, :marker_text)
end

@projection_template MarkdownInsertionToSyntaxLeaf MarkdownInsertion (prj, doc) ->
    SyntaxLeaf(TextString("insert markdown here", prj.style))

# ── MarkdownTextToSyntaxLeaf ──────────────────────────────────────────────────

@projection UntrackedCell struct MarkdownTextToSyntaxLeaf
    style::StyleText = get_markdown_style(nothing, :source_text)
end

@projection_template MarkdownTextToSyntaxLeaf MarkdownText (prj, doc) ->
    SyntaxLeaf(bound(:content, String,
                     make_hinted_text(() -> doc.content;
                                      empty_thunk = () -> isempty(doc.content),
                                      placeholder = "text",
                                      style = prj.style)))

# ── MarkdownCodeToSyntaxLeaf ──────────────────────────────────────────────────
# `tick` is the delimiter shown around the code (`` ` `` in source, "" rendered).

@projection UntrackedCell struct MarkdownCodeToSyntaxLeaf
    value_style::StyleText = get_markdown_style(nothing, :code_text)
    tick_style::StyleText  = get_markdown_style(nothing, :marker_text)
    tick::String           = "`"
end

@projection_template MarkdownCodeToSyntaxLeaf MarkdownCode (prj, doc) ->
    SyntaxLeaf(bound(:content, String,
                     make_hinted_text(() -> doc.content;
                                      empty_thunk = () -> isempty(doc.content),
                                      placeholder = "code",
                                      style = prj.value_style));
               open=TextString(prj.tick, prj.tick_style),
               close=TextString(prj.tick, prj.tick_style))

# ── MarkdownThematicBreakToSyntaxLeaf ─────────────────────────────────────────
# `text` is "---" in source, a `───` rule (DejaVu box-drawing) when rendered.

@projection UntrackedCell struct MarkdownThematicBreakToSyntaxLeaf
    style::StyleText = get_markdown_style(nothing, :marker_text)
    text::String     = "---"
end

@projection_template MarkdownThematicBreakToSyntaxLeaf MarkdownThematicBreak (prj, doc) ->
    SyntaxLeaf(TextString(prj.text, prj.style))

# ── MarkdownEmphasisToSyntaxNode / MarkdownStrongToSyntaxNode (source) ─────────

@projection UntrackedCell struct MarkdownEmphasisToSyntaxNode
    marker_style::StyleText = get_markdown_style(nothing, :marker_text)
end

@projection_template MarkdownEmphasisToSyntaxNode MarkdownEmphasis (prj, doc) ->
    SyntaxNode(collection(:content);
               open=TextString("*", prj.marker_style),
               close=TextString("*", prj.marker_style))

@projection UntrackedCell struct MarkdownStrongToSyntaxNode
    marker_style::StyleText = get_markdown_style(nothing, :marker_text)
end

@projection_template MarkdownStrongToSyntaxNode MarkdownStrong (prj, doc) ->
    SyntaxNode(collection(:content);
               open=TextString("**", prj.marker_style),
               close=TextString("**", prj.marker_style))

# ── MarkdownParagraphToSyntaxNode (shared by both styles) ─────────────────────

@projection struct MarkdownParagraphToSyntaxNode end

@projection_template MarkdownParagraphToSyntaxNode MarkdownParagraph (prj, doc) ->
    SyntaxNode(collection(:content); indentation=0)

# ── MarkdownHeadingToSyntaxNode (source; `#…` open marker) ─────────────────────

@projection UntrackedCell struct MarkdownHeadingToSyntaxNode
    hash_style::StyleText = get_markdown_style(nothing, :heading_marker_text)
end

@projection_template MarkdownHeadingToSyntaxNode MarkdownHeading (prj, doc) ->
    SyntaxNode(collection(:content);
               open=TextString(() -> "#"^clamp(doc.level, 1, 6) * " ", prj.hash_style),
               indentation=0)

# ── MarkdownQuoteToSyntaxNode ─────────────────────────────────────────────────
# `open_marker`/`sep_marker` prefix each quoted line (`> ` source, `▏ ` rendered).

@projection UntrackedCell struct MarkdownQuoteToSyntaxNode
    marker_style::StyleText = get_markdown_style(nothing, :marker_text)
    open_marker::String     = "> "
    sep_marker::String      = "\n> "
end

@projection_template MarkdownQuoteToSyntaxNode MarkdownQuote (prj, doc) ->
    SyntaxNode(collection(:elements);
               open=TextString(prj.open_marker, prj.marker_style),
               sep=TextString(prj.sep_marker, prj.marker_style),
               indentation=0)

# ── MarkdownListItemToSyntaxNode ──────────────────────────────────────────────
# `bullet` is `- ` (source) or `• ` (rendered). Ordered numbering is deferred.

@projection UntrackedCell struct MarkdownListItemToSyntaxNode
    bullet_style::StyleText = get_markdown_style(nothing, :marker_text)
    bullet::String          = "- "
end

@projection_template MarkdownListItemToSyntaxNode MarkdownListItem (prj, doc) ->
    SyntaxNode(collection(:elements);
               open=TextString(prj.bullet, prj.bullet_style),
               sep=TextString("\n  "),
               indentation=0)

# ── MarkdownListToSyntaxNode / MarkdownRootToSyntaxNode (shared) ───────────────

@projection struct MarkdownListToSyntaxNode end

@projection_template MarkdownListToSyntaxNode MarkdownList (prj, doc) ->
    SyntaxNode(collection(:items); sep=TextString("\n"), indentation=0)

# ── MarkdownTableRowToSyntaxNode / MarkdownTableToSyntaxNode (shared) ──────────
# A row is its entries between pipes. A table is its header over its body rows,
# and the delimiter row is the separator between the two: it is printed from
# `alignments`, so no position in it stands for a field of the table.

@projection UntrackedCell struct MarkdownTableRowToSyntaxNode
    pipe_style::StyleText = get_markdown_style(nothing, :marker_text)
end

@projection_template MarkdownTableRowToSyntaxNode MarkdownTableRow (prj, doc) ->
    SyntaxNode(collection(:elements);
               open=TextString("| ", prj.pipe_style),
               sep=TextString(" | ", prj.pipe_style),
               close=TextString(" |", prj.pipe_style),
               indentation=0)

# The delimiter row of a table: one `---` for each column, with a colon on the
# side the column aligns to.
_make_delimiter_row(alignments) =
    "| " * join((alignment === :left   ? ":---"  :
                 alignment === :center ? ":---:" :
                 alignment === :right  ? "---:"  : "---" for alignment in alignments), " | ") * " |"

@projection UntrackedCell struct MarkdownTableToSyntaxNode
    pipe_style::StyleText = get_markdown_style(nothing, :marker_text)
end

@projection_template MarkdownTableToSyntaxNode MarkdownTable (prj, doc) ->
    SyntaxNode(TextString("", prj.pipe_style), TextString("", prj.pipe_style),
               TextString(() -> "\n" * _make_delimiter_row(doc.alignments) * "\n", prj.pipe_style),
               [ project(:header),
                 SyntaxNode(collection(:rows); sep=TextString("\n"), indentation=0) ],
               0, false, nothing)

@projection UntrackedCell struct MarkdownRootToSyntaxNode
    style::StyleText = get_markdown_style(nothing, :source_text)
end

@projection_template MarkdownRootToSyntaxNode MarkdownRoot (prj, doc) ->
    SyntaxNode(collection(:elements);
               sep=TextString("\n\n", prj.style),
               indentation=0)

# ── MarkdownLinkToSyntaxNode (source `[content](url)`) ────────────────────────

@projection UntrackedCell struct MarkdownLinkToSyntaxNode
    bracket_style::StyleText = get_markdown_style(nothing, :marker_text)
    url_style::StyleText     = get_markdown_style(nothing, :url_text)
end

@projection_template MarkdownLinkToSyntaxNode MarkdownLink (prj, doc) ->
    SyntaxConcatenation([ SyntaxNode(collection(:content);
                                     open=TextString("[", prj.bracket_style),
                                     close=TextString("]", prj.bracket_style)),
                          SyntaxLeaf(bound(:url, String,
                                           make_hinted_text(() -> doc.url;
                                                            empty_thunk = () -> isempty(doc.url),
                                                            placeholder = "url",
                                                            style = prj.url_style));
                                     open=TextString("(", prj.bracket_style),
                                     close=TextString(")", prj.bracket_style)) ])

# ── MarkdownImageToSyntaxNode (source `![alt](url)`) ──────────────────────────

@projection UntrackedCell struct MarkdownImageToSyntaxNode
    bracket_style::StyleText = get_markdown_style(nothing, :marker_text)
    alt_style::StyleText     = get_markdown_style(nothing, :alt_text)
    url_style::StyleText     = get_markdown_style(nothing, :url_text)
end

@projection_template MarkdownImageToSyntaxNode MarkdownImage (prj, doc) ->
    SyntaxConcatenation([ SyntaxLeaf(bound(:alt, String,
                                           make_hinted_text(() -> doc.alt;
                                                            empty_thunk = () -> isempty(doc.alt),
                                                            placeholder = "alt",
                                                            style = prj.alt_style));
                                     open=TextString("![", prj.bracket_style),
                                     close=TextString("]", prj.bracket_style)),
                          SyntaxLeaf(bound(:url, String,
                                           make_hinted_text(() -> doc.url;
                                                            empty_thunk = () -> isempty(doc.url),
                                                            placeholder = "url",
                                                            style = prj.url_style));
                                     open=TextString("(", prj.bracket_style),
                                     close=TextString(")", prj.bracket_style)) ])

# ── MarkdownCodeBlockToSyntaxNode (fenced; shared) ────────────────────────────

@projection UntrackedCell struct MarkdownCodeBlockToSyntaxNode
    fence_style::StyleText = get_markdown_style(nothing, :marker_text)
    lang_style::StyleText  = get_markdown_style(nothing, :language_text)
    code_style::StyleText  = get_markdown_style(nothing, :code_text)
    open_fence::String     = "```"     # "" rendered
    close_fence::String    = "\n```"   # "" rendered
end

@projection_template MarkdownCodeBlockToSyntaxNode MarkdownCodeBlock (prj, doc) ->
    SyntaxNode(TextString(prj.open_fence, prj.fence_style), TextString(prj.close_fence, prj.fence_style), nothing,
        [ SyntaxLeaf(bound(:language, String,
                           make_hinted_text(() -> doc.language;
                                            empty_thunk = () -> isempty(doc.language),
                                            placeholder = "lang",
                                            style = prj.lang_style))),
          SyntaxLeaf(bound(:code, String,
                           make_hinted_text(() -> doc.code;
                                            empty_thunk = () -> isempty(doc.code),
                                            placeholder = "code",
                                            style = prj.code_style));
                     open=TextString("\n", prj.fence_style)) ],
        0, false, nothing)

# ══════════════════════════════════════════════════════════════════════════════
# Rendered view (style = :rendered) — cascading inline styles via ambient context
# ══════════════════════════════════════════════════════════════════════════════

# ── MarkdownStyledTextToSyntaxLeaf (rendered MarkdownText; reads ambient) ──────
# Same output shape and reference mapping as the source text leaf; the only
# differences are the font, taken from the ambient `:md_style` (or the theme's
# body default), and the pointer over a link, taken from `:md_pointer_shape`.

@projection UntrackedCell struct MarkdownStyledTextToSyntaxLeaf
    style::StyleText = get_markdown_style(nothing, :body_text)
end

function map_reference_forward(p::MarkdownStyledTextToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        proj(^(p), inner) => inner
        ::MarkdownText.content.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
    end
end

function map_reference_backward(p::MarkdownStyledTextToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        ∅ => EmptyReference(get_reference_node_type(iomap.input))
        ::SyntaxLeaf.value.rest... => @reference ::MarkdownText.content::String.^(rest)
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function print_document(p::MarkdownStyledTextToSyntaxLeaf, recursion, t::MarkdownText, ctx)
    style = get_property(ctx, :md_style, p.style)
    shape = get_property(ctx, :md_pointer_shape, nothing)
    paths = make_output_path_cells(t, path -> map_reference_forward(p, nothing, path))
    SimpleIoMap(p, t, SyntaxLeaf(TextString(() -> t.content, style, shape); paths...))
end

function read_intent(p::MarkdownStyledTextToSyntaxLeaf, iomap, op::ReplaceStringRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    (new_ref === nothing || has_introduced_step(new_ref)) && return nothing
    ReplaceStringRangeOperation(new_ref, op.replacement)
end

function read_intent(p::MarkdownStyledTextToSyntaxLeaf, iomap, op::ReplacePathOperation)
    path = map_reference_backward(p, iomap, op.path)
    path === nothing ? nothing : make_path_operation(op, path)
end

# ── MarkdownStyledInline (rendered Strong/Emphasis/Heading/Link) ───────────────
# A marker-free inline container that sets an ambient `:md_style` (its own
# themed font/color) and projects its `content` children through it (School A:
# containers delegate to their children and only *augment* the ambient style;
# the leaf reads it). Output shape: a `SyntaxNode` whose children are the
# recursively projected content, so the reference mapping is the standard
# "delegate to child i" (modeled on YamlSequenceToBlockSyntaxNode, minus the
# per-item wrapper).
#
# None of the four is declared with `@projection`: each needs a different set
# of resolved theme values (a font, a color, or four fonts and a color for a
# heading), so each holds exactly the `Any` fields it needs — a value or a cell
# that `get_markdown_style` returned — and reads it with `unwrap_cell`.

abstract type MarkdownStyledInline <: Projection end

struct MarkdownStrongToStyledNode <: MarkdownStyledInline
    bold_font::Any
    body_text::Any
end
MarkdownStrongToStyledNode(; theme = nothing) =
    MarkdownStrongToStyledNode(get_markdown_style(theme, :bold_font),
                               get_markdown_style(theme, :body_text))

struct MarkdownEmphasisToStyledNode <: MarkdownStyledInline
    italic_font::Any
    body_text::Any
end
MarkdownEmphasisToStyledNode(; theme = nothing) =
    MarkdownEmphasisToStyledNode(get_markdown_style(theme, :italic_font),
                                 get_markdown_style(theme, :body_text))

struct MarkdownLinkToStyledNode <: MarkdownStyledInline
    link_color::Any
    body_text::Any
end
MarkdownLinkToStyledNode(; theme = nothing) =
    MarkdownLinkToStyledNode(get_markdown_style(theme, :link_color),
                             get_markdown_style(theme, :body_text))

struct MarkdownHeadingToStyledNode <: MarkdownStyledInline
    heading_1_font::Any
    heading_2_font::Any
    heading_3_font::Any
    heading_font::Any
    heading_color::Any
    body_text::Any
end
MarkdownHeadingToStyledNode(; theme = nothing) =
    MarkdownHeadingToStyledNode(get_markdown_style(theme, :heading_1_font),
                                get_markdown_style(theme, :heading_2_font),
                                get_markdown_style(theme, :heading_3_font),
                                get_markdown_style(theme, :heading_font),
                                get_markdown_style(theme, :heading_color),
                                get_markdown_style(theme, :body_text))

# The font that `p` holds for a heading at `level` (1-based; every level past
# the third takes `heading_font`).
_get_heading_font(p::MarkdownHeadingToStyledNode, level::Int) =
    unwrap_cell(level <= 1 ? p.heading_1_font :
                level == 2 ? p.heading_2_font :
                level == 3 ? p.heading_3_font : p.heading_font)

# Augment the ambient style with what this container's mode draws. There is no
# bold-italic face, so nesting keeps the innermost weight (a documented v1
# limitation).
_mode_style(p::MarkdownStrongToStyledNode, ambient::StyleText, doc) =
    StyleText(unwrap_cell(p.bold_font), ambient.color)
_mode_style(p::MarkdownEmphasisToStyledNode, ambient::StyleText, doc) =
    StyleText(unwrap_cell(p.italic_font), ambient.color)
_mode_style(p::MarkdownLinkToStyledNode, ambient::StyleText, doc) =
    StyleText(ambient.font, unwrap_cell(p.link_color))

# The pointer over the text of a container: the hand over a link, which a click
# follows, and the pointer of the container around it elsewhere.
_mode_pointer_shape(::MarkdownLinkToStyledNode, ambient) = :pointing_hand
_mode_pointer_shape(::MarkdownStyledInline, ambient) = ambient
_mode_style(p::MarkdownHeadingToStyledNode, ambient::StyleText, doc) =
    StyleText(_get_heading_font(p, clamp(doc.level, 1, 6)), unwrap_cell(p.heading_color))

function print_document(p::MarkdownStyledInline, recursion, doc, ctx)
    ambient = get_property(ctx, :md_style, unwrap_cell(p.body_text))
    style = _mode_style(p, ambient, doc)
    shape = _mode_pointer_shape(p, get_property(ctx, :md_pointer_shape, nothing))
    child_iomaps = Cell(@computation([
        print_child(recursion, child,
            with_property(with_property(make_child_context(ctx, FieldReferenceStep("content"), ElementReferenceStep(i)),
                                        :md_style, style), :md_pointer_shape, shape))
        for (i, child) in enumerate(doc.content)]))
    items = CellVector(@computation SyntaxDocument[im.output for im in child_iomaps[]])
    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(doc, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)
    node = SyntaxNode(items; indentation=0, paths...)
    iomap = ChildrenIoMap(p, doc, node, child_iomaps)
    iomap_cell[] = iomap
    return iomap
end

# Forward is shared (input matched by the `content` field name, output is
# `::SyntaxNode`): no input-type literal is needed.
function map_reference_forward(p::MarkdownStyledInline, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
        content{s:e}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[child_i].^(inner)
        end
    end
end

# Backward needs the input node type for the folded whole-element (`∅`) form and
# the `content[i]` owner, so there is one tiny method per concrete type.
for (T, D) in ((:MarkdownStrongToStyledNode,   :MarkdownStrong),
               (:MarkdownEmphasisToStyledNode, :MarkdownEmphasis),
               (:MarkdownHeadingToStyledNode,  :MarkdownHeading),
               (:MarkdownLinkToStyledNode,     :MarkdownLink))
    @eval function map_reference_backward(p::$T, iomap::ChildrenIoMap, reference)
        @reference_case reference begin
            ∅ => EmptyReference($D)
            ::SyntaxNode.children{s:e}.rest... => begin
                child_i = s + 1
                iomaps = iomap.child_iomaps
                1 <= child_i <= length(iomaps) || return make_introduced_reference(p, iomap, reference)
                child = iomaps[child_i]
                inner = map_reference_backward(child.projection, child, rest)
                inner === nothing && return nothing
                @reference ::$D.content::CellVector[child_i].^(inner)
            end
            __ => make_introduced_reference(p, iomap, reference)
        end
    end
end

function read_intent(p::MarkdownStyledInline, iomap::ChildrenIoMap, op::ReplacePathOperation)
    r = map_reference_backward(p, iomap, op.path)
    r === nothing ? nothing : make_path_operation(op, r)
end

function read_intent(p::MarkdownStyledInline, iomap::ChildrenIoMap, op::ReplaceStringRangeOperation)
    r = map_reference_backward(p, iomap, op.reference)
    (r === nothing || has_introduced_step(r)) ? nothing : ReplaceStringRangeOperation(r, op.replacement)
end

# ── MarkdownImageToStyledNode (rendered; real image via TextGraphics) ─────────
# An `alt` caption above the decoded image (from `url`), falling back to the url
# text when the file is not on disk. Modelled on BookPictureToSyntaxLeaf.
#   .alt[k] → .children[1].value[k]   .url[k] → .children[2].value[k]

@projection UntrackedCell struct MarkdownImageToStyledNode
    caption_style::StyleText = get_markdown_style(nothing, :caption_text)
    placeholder::StyleText   = get_markdown_style(nothing, :marker_text)
end

# The image span: an inline `TextGraphics` with a lazily-decoded `ImageFile` when
# `url` names a file on disk (sized to its natural extent, capped at `max_w`);
# otherwise the url / a placeholder as text.
function _md_image_value(url, placeholder::StyleText; max_w::Int = 640)
    if url isa AbstractString && !isempty(url) && isfile(String(url))
        path = String(url)
        img  = ImageFile(path)
        raw  = getfield(img, :raw)
        set_cell_computation!(raw, () -> (try decode_image(path) catch; nothing end))
        _nat(i, fb) = (r = raw[]; (r isa Tuple && length(r) == 3) ? Int(r[i]) : fb)
        dw = Cell(@computation Int32(min(_nat(2, 720), max_w)))
        dh = Cell(@computation begin w = min(_nat(2, 720), max_w); Int32(round(Int, _nat(3, 460) * w / _nat(2, 720))) end)
        return TextGraphics(Cell(img), dw, dh, Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    end
    TextString(isempty(String(url)) ? "image" : String(url), placeholder)
end

function print_document(p::MarkdownImageToStyledNode, recursion, doc::MarkdownImage, ctx)
    alt_sel = Cell(@computation begin
        @reference_case doc.selection begin
            ::MarkdownImage.alt.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
        end
    end)
    url_sel = Cell(@computation begin
        @reference_case doc.selection begin
            ::MarkdownImage.url.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
        end
    end)
    alt_leaf = SyntaxLeaf(
        make_hinted_text(() -> doc.alt; empty_thunk = () -> isempty(doc.alt),
                         placeholder = "image",
                         style = p.caption_style);
        selection=alt_sel)
    img_leaf = SyntaxLeaf(_md_image_value(doc.url, p.placeholder); selection=url_sel)
    node = SyntaxNode(CellVector(Cell[Cell(alt_leaf), Cell(img_leaf)]); sep=TextString("\n", p.placeholder))
    SimpleIoMap(p, doc, node)
end

function map_reference_forward(::MarkdownImageToStyledNode, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ::MarkdownImage.alt.rest... => @reference ::SyntaxNode.children::CellVector[1]::SyntaxLeaf.value::TextString.^(rest)
        ::MarkdownImage.url.rest... => @reference ::SyntaxNode.children::CellVector[2]::SyntaxLeaf.value::TextString.^(rest)
    end
end

function map_reference_backward(::MarkdownImageToStyledNode, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ::SyntaxNode.children{s:_}.value.rest... => begin
            child_i = s + 1
            child_i == 1 ? (@reference ::MarkdownImage.alt::String.^(rest)) :
            child_i == 2 ? (@reference ::MarkdownImage.url::String.^(rest)) : nothing
        end
    end
end

function read_intent(p::MarkdownImageToStyledNode, iomap::SimpleIoMap, op::ReplacePathOperation)
    r = map_reference_backward(p, iomap, op.path)
    r === nothing ? nothing : make_path_operation(op, r)
end
function read_intent(p::MarkdownImageToStyledNode, iomap::SimpleIoMap, op::ReplaceStringRangeOperation)
    r = map_reference_backward(p, iomap, op.reference)
    (r === nothing || has_introduced_step(r)) ? nothing : ReplaceStringRangeOperation(r, op.replacement)
end

# ── MarkdownListToStyledNode (rendered; `1.` ordered / `•` unordered) ──────────
# The marker depends on the item index + `ordered`, which the template's
# homogeneous collection cannot inject, so this is hand-written like
# YamlSequenceToBlockSyntaxNode: each item is wrapped in a node whose `open` is the
# marker. Rendered `MarkdownListItem` carries no bullet (the List supplies it).
#   .items[i].rest ↔ .children[i].content.<item-mapped rest>

@projection UntrackedCell struct MarkdownListToStyledNode
    marker_style::StyleText = get_markdown_style(nothing, :rendered_marker_text)
end

_md_list_marker(ordered::Bool, i::Int) = ordered ? "$(i). " : "• "

function print_document(p::MarkdownListToStyledNode, recursion, lst::MarkdownList, ctx)
    child_iomaps = Cell(@computation([print_child(recursion, item,
                                  make_child_context(ctx, FieldReferenceStep("items"), ElementReferenceStep(i)))
                               for (i, item) in enumerate(lst.items)]))
    items = CellVector(@computation begin
        ord = lst.ordered
        SyntaxDocument[
            SyntaxDelimitation(im.output;
                               opening_delimiter=TextString(_md_list_marker(ord, i), p.marker_style))
            for (i, im) in enumerate(child_iomaps[]) ]
    end)
    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(lst, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)
    node = SyntaxNode(items; sep=TextString("\n", p.marker_style), indentation=0, paths...)
    iomap = ChildrenIoMap(p, lst, node, child_iomaps)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::MarkdownListToStyledNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
        ::MarkdownList.items{s:e}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[child_i]::SyntaxDelimitation.content.^(inner)
        end
    end
end

function map_reference_backward(p::MarkdownListToStyledNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::MarkdownList
        ::SyntaxNode.children{s:e}.content.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps
            1 <= child_i <= length(iomaps) || return make_introduced_reference(p, iomap, reference)
            child = iomaps[child_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::MarkdownList.items::CellVector[child_i].^(inner)
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::MarkdownListToStyledNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    r = map_reference_backward(p, iomap, op.path)
    r === nothing ? nothing : make_path_operation(op, r)
end
function read_intent(p::MarkdownListToStyledNode, iomap::ChildrenIoMap, op::ReplaceStringRangeOperation)
    r = map_reference_backward(p, iomap, op.reference)
    (r === nothing || has_introduced_step(r)) ? nothing : ReplaceStringRangeOperation(r, op.replacement)
end

# ══════════════════════════════════════════════════════════════════════════════
# Dispatcher
# ══════════════════════════════════════════════════════════════════════════════

"""
    MarkdownToSyntax(; style::Symbol = :source, theme = nothing)

Build the Markdown → Syntax projection. `style` is `:source` (colourised raw
markdown, fully editable including markers) or `:rendered` (formatted, marker-free
— see the module docstring). The projections take the style of each role with
`get_markdown_style`, from `theme`, a `MarkdownTheme` scaled or not, or the
default styles for `nothing`.
"""
function MarkdownToSyntax(; style::Symbol = :source, theme = nothing)
    style in (:source, :rendered) || error("MarkdownToSyntax: style must be :source or :rendered, got :$style")
    get_style(name) = get_markdown_style(theme, name)
    style_marker = (style = get_style(:marker_text),)
    style_source = (style = get_style(:source_text),)
    marker_style_group = (marker_style = get_style(:marker_text),)
    pipe_style_group = (pipe_style = get_style(:marker_text),)
    if style === :rendered
        marker = get_style(:rendered_marker_text)
        return TypeDispatchingProjection(
            MarkdownInsertion     => MarkdownInsertionToSyntaxLeaf(; style_marker...),
            MarkdownText          => MarkdownStyledTextToSyntaxLeaf(; style = get_style(:body_text)),
            MarkdownCode          => MarkdownCodeToSyntaxLeaf(; tick="",
                                        value_style = get_style(:language_text),
                                        tick_style = get_style(:marker_text)),
            MarkdownThematicBreak => MarkdownThematicBreakToSyntaxLeaf(; text="────────────", style=marker),
            MarkdownEmphasis      => MarkdownEmphasisToStyledNode(; theme),
            MarkdownStrong        => MarkdownStrongToStyledNode(; theme),
            MarkdownParagraph     => MarkdownParagraphToSyntaxNode(),
            MarkdownHeading       => MarkdownHeadingToStyledNode(; theme),
            MarkdownCodeBlock     => MarkdownCodeBlockToSyntaxNode(; open_fence="", close_fence="",
                                        fence_style = get_style(:marker_text), lang_style=marker,
                                        code_style = get_style(:code_text)),
            MarkdownQuote         => MarkdownQuoteToSyntaxNode(; open_marker="▏ ", sep_marker="\n▏ ",
                                        marker_style=marker),
            MarkdownList          => MarkdownListToStyledNode(; marker_style = marker),
            MarkdownListItem      => MarkdownListItemToSyntaxNode(; bullet="", bullet_style = get_style(:marker_text)),
            MarkdownTable         => MarkdownTableToSyntaxNode(; pipe_style_group...),
            MarkdownTableRow      => MarkdownTableRowToSyntaxNode(; pipe_style_group...),
            MarkdownLink          => MarkdownLinkToStyledNode(; theme),
            MarkdownImage         => MarkdownImageToStyledNode(; caption_style = get_style(:caption_text),
                                        placeholder = get_style(:marker_text)),
            MarkdownRoot          => MarkdownRootToSyntaxNode(; style_source...),
            Vector{Cell}          => CopyingProjection(),
        )
    end
    TypeDispatchingProjection(
        MarkdownInsertion     => MarkdownInsertionToSyntaxLeaf(; style_marker...),
        MarkdownText          => MarkdownTextToSyntaxLeaf(; style_source...),
        MarkdownCode          => MarkdownCodeToSyntaxLeaf(; value_style = get_style(:code_text),
                                    tick_style = get_style(:marker_text)),
        MarkdownThematicBreak => MarkdownThematicBreakToSyntaxLeaf(; style_marker...),
        MarkdownEmphasis      => MarkdownEmphasisToSyntaxNode(; marker_style_group...),
        MarkdownStrong        => MarkdownStrongToSyntaxNode(; marker_style_group...),
        MarkdownParagraph     => MarkdownParagraphToSyntaxNode(),
        MarkdownHeading       => MarkdownHeadingToSyntaxNode(; hash_style = get_style(:heading_marker_text)),
        MarkdownCodeBlock     => MarkdownCodeBlockToSyntaxNode(; fence_style = get_style(:marker_text),
                                    lang_style = get_style(:language_text), code_style = get_style(:code_text)),
        MarkdownQuote         => MarkdownQuoteToSyntaxNode(; marker_style_group...),
        MarkdownList          => MarkdownListToSyntaxNode(),
        MarkdownListItem      => MarkdownListItemToSyntaxNode(; bullet_style = get_style(:marker_text)),
        MarkdownTable         => MarkdownTableToSyntaxNode(; pipe_style_group...),
        MarkdownTableRow      => MarkdownTableRowToSyntaxNode(; pipe_style_group...),
        MarkdownLink          => MarkdownLinkToSyntaxNode(; bracket_style = get_style(:marker_text),
                                    url_style = get_style(:url_text)),
        MarkdownImage         => MarkdownImageToSyntaxNode(; bracket_style = get_style(:marker_text),
                                    alt_style = get_style(:alt_text), url_style = get_style(:url_text)),
        MarkdownRoot          => MarkdownRootToSyntaxNode(; style_source...),
        Vector{Cell}          => CopyingProjection(),
    )
end

# ── Natural-projection registration ─────────────────────────────────────────
# The row that teaches the render-anything projection what this domain is. The
# factory form, so every renderer builds its own projection instance.
