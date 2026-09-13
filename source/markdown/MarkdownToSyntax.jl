"""
    MarkdownToSyntaxModule

Markdown → SyntaxDocument projection with two presentations, selected by
`MarkdownToSyntax(; style)`:

- `:source` (default) — colourised **raw markdown**: `#` headings, `**bold**`,
  `` `code` ``, `[text](url)`, `- ` bullets, ` ``` ` fences, `>` quotes, `---`.
  Every marker is an editable text span. Written entirely with
  `@projection_template`, so the reader is derived from the wiring.
- `:rendered` — **formatted markdown**, marker-free: big bold headings, real
  bold/italic, plain inline code, `•` bullets, `▏` quote bars, `───` rules, blue
  links. Inline font weight/size cascades from a container to its descendant text
  via an ambient `:md_style` carried in the printer context (School A: containers
  delegate to their children and only *augment* the ambient style; the leaf reads
  it). This mirrors YAML's `YamlToSyntax(; style)`: most rules stay on
  `@projection_template` (rendered field values), only the cascading nodes
  (Text/Strong/Emphasis/Heading/Link) are hand-written.

Blocks stack flush-left (`indentation=0` + a newline `sep`, the BookToSyntax
idiom); inline runs concatenate (a `SyntaxConcatenation`).
"""
module MarkdownToSyntaxModule

import ..CellModule: Cell, ComputedCell, set_cell_function!
import ..CollectionModule: CellVector, ComputedCellVector
import ..ProjectionApiModule: Projection, print_document, print_child, read_intent,
                              map_reference_forward, map_reference_backward
import ..ProjectionModule: var"@projection"
import ..MarkdownModule: MarkdownInsertion, MarkdownText, MarkdownCode, MarkdownEmphasis,
                         MarkdownStrong, MarkdownLink, MarkdownImage, MarkdownHeading,
                         MarkdownParagraph, MarkdownCodeBlock, MarkdownThematicBreak,
                         MarkdownQuote, MarkdownList, MarkdownListItem, MarkdownRoot
import ..TextModule: TextString, make_hinted_text, TextGraphics
import ..ImageModule: ImageFile
import ..BackendModule: decode_image
import ..GraphicsModule: GraphicsDocument
import ..FontModule: font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20,
                     font_ubuntu_regular_20, font_ubuntu_bold_20, font_ubuntu_italic_20,
                     font_ubuntu_bold_36, font_ubuntu_bold_24, font_ubuntu_bold_22, font_ubuntu_bold_18,
                     font_dejavu_monospace_regular_20
import ..ColorModule: color_black, color_solarized_blue, color_solarized_green,
                      color_solarized_magenta, color_solarized_cyan,
                      color_solarized_gray, color_solarized_violet
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode, SyntaxConcatenation, SyntaxDelimitation
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..CopyingProjectionModule: CopyingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..PrinterContextModule: make_child_context, with_property, get_property
import ..ReferenceModule: ConcreteReference, FieldReferenceStep, RangeReferenceStep, ElementReferenceStep,
                          EmptyReference
import ..ProjectionReferenceStepModule: ProjectionReferenceStep, is_introduced_reference
import ..ReferenceModule: var"@reference_case"
import ..ReferenceModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
import ..ProjectionTemplateModule: var"@projection_template", bound, collection
import ..SerializationModule: FileDocument, ReferenceStub, format_marker_text, format_file_marker_text, get_filename
export MarkdownInsertionToSyntaxLeaf, MarkdownTextToSyntaxLeaf, MarkdownCodeToSyntaxLeaf,
       MarkdownThematicBreakToSyntaxLeaf, MarkdownEmphasisToSyntaxNode, MarkdownStrongToSyntaxNode,
       MarkdownParagraphToSyntaxNode, MarkdownHeadingToSyntaxNode, MarkdownQuoteToSyntaxNode,
       MarkdownListToSyntaxNode, MarkdownListItemToSyntaxNode, MarkdownRootToSyntaxNode,
       MarkdownLinkToSyntaxNode, MarkdownImageToSyntaxNode, MarkdownCodeBlockToSyntaxNode,
       MarkdownStyledTextToSyntaxLeaf, MarkdownStyledInline, MarkdownStrongToStyledNode,
       MarkdownEmphasisToStyledNode, MarkdownHeadingToStyledNode, MarkdownLinkToStyledNode,
       MarkdownImageToStyledNode, MarkdownListToStyledNode,
       ReferenceStubToMarkdownSyntaxLeaf, EmbeddedFileDocumentToMarkdownSyntaxLeaf,
       MarkdownToSyntax

const _MONO      = font_ubuntu_monospace_regular_20
const _MONO_BOLD = font_ubuntu_monospace_bold_20

# ══════════════════════════════════════════════════════════════════════════════
# Source view (style = :source) — colourised raw markdown, all @projection_template
# ══════════════════════════════════════════════════════════════════════════════

# ── MarkdownInsertionToSyntaxLeaf ─────────────────────────────────────────────

@projection struct MarkdownInsertionToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(_MONO, color_solarized_gray)
end

@projection_template MarkdownInsertionToSyntaxLeaf MarkdownInsertion (prj, doc) ->
    SyntaxLeaf(TextString("insert markdown here", prj.style))

# ── MarkdownTextToSyntaxLeaf ──────────────────────────────────────────────────

@projection struct MarkdownTextToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(_MONO, color_black)
end

@projection_template MarkdownTextToSyntaxLeaf MarkdownText (prj, doc) ->
    SyntaxLeaf(bound(:content, String,
                     make_hinted_text(() -> doc.content, () -> isempty(doc.content), "text", prj.style)))

# ── MarkdownCodeToSyntaxLeaf ──────────────────────────────────────────────────
# `tick` is the delimiter shown around the code (`` ` `` in source, "" rendered).

@projection struct MarkdownCodeToSyntaxLeaf
    value_style::ImmutableCell{StyleText} = StyleText(_MONO, color_solarized_green)
    tick_style::ImmutableCell{StyleText}  = StyleText(_MONO, color_solarized_gray)
    tick::String           = "`"
end

@projection_template MarkdownCodeToSyntaxLeaf MarkdownCode (prj, doc) ->
    SyntaxLeaf(bound(:content, String,
                     make_hinted_text(() -> doc.content, () -> isempty(doc.content), "code", prj.value_style));
               open=TextString(prj.tick, prj.tick_style),
               close=TextString(prj.tick, prj.tick_style))

# ── MarkdownThematicBreakToSyntaxLeaf ─────────────────────────────────────────
# `text` is "---" in source, a `───` rule (DejaVu box-drawing) when rendered.

@projection struct MarkdownThematicBreakToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(_MONO, color_solarized_gray)
    text::String     = "---"
end

@projection_template MarkdownThematicBreakToSyntaxLeaf MarkdownThematicBreak (prj, doc) ->
    SyntaxLeaf(TextString(prj.text, prj.style))

# ── MarkdownEmphasisToSyntaxNode / MarkdownStrongToSyntaxNode (source) ─────────

@projection struct MarkdownEmphasisToSyntaxNode
    marker_style::ImmutableCell{StyleText} = StyleText(_MONO, color_solarized_gray)
end

@projection_template MarkdownEmphasisToSyntaxNode MarkdownEmphasis (prj, doc) ->
    SyntaxNode(collection(:content);
               open=TextString("*", prj.marker_style),
               close=TextString("*", prj.marker_style))

@projection struct MarkdownStrongToSyntaxNode
    marker_style::ImmutableCell{StyleText} = StyleText(_MONO, color_solarized_gray)
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

@projection struct MarkdownHeadingToSyntaxNode
    hash_style::ImmutableCell{StyleText} = StyleText(_MONO_BOLD, color_solarized_blue)
end

@projection_template MarkdownHeadingToSyntaxNode MarkdownHeading (prj, doc) ->
    SyntaxNode(collection(:content);
               open=TextString(() -> "#"^clamp(doc.level, 1, 6) * " ", prj.hash_style),
               indentation=0)

# ── MarkdownQuoteToSyntaxNode ─────────────────────────────────────────────────
# `open_marker`/`sep_marker` prefix each quoted line (`> ` source, `▏ ` rendered).

@projection struct MarkdownQuoteToSyntaxNode
    marker_style::ImmutableCell{StyleText} = StyleText(_MONO, color_solarized_gray)
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

@projection struct MarkdownListItemToSyntaxNode
    bullet_style::ImmutableCell{StyleText} = StyleText(_MONO, color_solarized_gray)
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

@projection struct MarkdownRootToSyntaxNode
    style::ImmutableCell{StyleText} = StyleText(_MONO, color_black)
end

@projection_template MarkdownRootToSyntaxNode MarkdownRoot (prj, doc) ->
    SyntaxNode(collection(:elements);
               sep=TextString("\n\n", prj.style),
               indentation=0)

# ── MarkdownLinkToSyntaxNode (source `[content](url)`) ────────────────────────

@projection struct MarkdownLinkToSyntaxNode
    bracket_style::ImmutableCell{StyleText} = StyleText(_MONO, color_solarized_gray)
    url_style::ImmutableCell{StyleText}     = StyleText(_MONO, color_solarized_violet)
end

@projection_template MarkdownLinkToSyntaxNode MarkdownLink (prj, doc) ->
    SyntaxConcatenation([ SyntaxNode(collection(:content);
                                     open=TextString("[", prj.bracket_style),
                                     close=TextString("]", prj.bracket_style)),
                          SyntaxLeaf(bound(:url, String,
                                           make_hinted_text(() -> doc.url, () -> isempty(doc.url), "url", prj.url_style));
                                     open=TextString("(", prj.bracket_style),
                                     close=TextString(")", prj.bracket_style)) ])

# ── MarkdownImageToSyntaxNode (source `![alt](url)`) ──────────────────────────

@projection struct MarkdownImageToSyntaxNode
    bracket_style::ImmutableCell{StyleText} = StyleText(_MONO, color_solarized_gray)
    alt_style::ImmutableCell{StyleText}     = StyleText(_MONO, color_solarized_cyan)
    url_style::ImmutableCell{StyleText}     = StyleText(_MONO, color_solarized_violet)
end

@projection_template MarkdownImageToSyntaxNode MarkdownImage (prj, doc) ->
    SyntaxConcatenation([ SyntaxLeaf(bound(:alt, String,
                                           make_hinted_text(() -> doc.alt, () -> isempty(doc.alt), "alt", prj.alt_style));
                                     open=TextString("![", prj.bracket_style),
                                     close=TextString("]", prj.bracket_style)),
                          SyntaxLeaf(bound(:url, String,
                                           make_hinted_text(() -> doc.url, () -> isempty(doc.url), "url", prj.url_style));
                                     open=TextString("(", prj.bracket_style),
                                     close=TextString(")", prj.bracket_style)) ])

# ── MarkdownCodeBlockToSyntaxNode (fenced; shared) ────────────────────────────

@projection struct MarkdownCodeBlockToSyntaxNode
    fence_style::ImmutableCell{StyleText} = StyleText(_MONO, color_solarized_gray)
    lang_style::ImmutableCell{StyleText}  = StyleText(_MONO, color_solarized_magenta)
    code_style::ImmutableCell{StyleText}  = StyleText(_MONO, color_solarized_green)
    open_fence::String     = "```"     # "" rendered
    close_fence::String    = "\n```"   # "" rendered
end

@projection_template MarkdownCodeBlockToSyntaxNode MarkdownCodeBlock (prj, doc) ->
    SyntaxNode(TextString(prj.open_fence, prj.fence_style), TextString(prj.close_fence, prj.fence_style), nothing,
        [ SyntaxLeaf(bound(:language, String,
                           make_hinted_text(() -> doc.language, () -> isempty(doc.language), "lang", prj.lang_style))),
          SyntaxLeaf(bound(:code, String,
                           make_hinted_text(() -> doc.code, () -> isempty(doc.code), "code", prj.code_style));
                     open=TextString("\n", prj.fence_style)) ],
        0, false, nothing)

# ══════════════════════════════════════════════════════════════════════════════
# Rendered view (style = :rendered) — cascading inline styles via ambient context
# ══════════════════════════════════════════════════════════════════════════════

const _BODY = StyleText(font_ubuntu_regular_20, color_black)
const _HEADING_COLOR = color_solarized_blue

_heading_font(level) = level <= 1 ? font_ubuntu_bold_36 :
                       level == 2 ? font_ubuntu_bold_24 :
                       level == 3 ? font_ubuntu_bold_22 :
                                    font_ubuntu_bold_18

# Augment the ambient style with a container's mode. There is no bold-italic face,
# so nesting keeps the innermost weight (a documented v1 limitation).
function _mode_style(mode::Symbol, ambient::StyleText, doc)
    mode === :bold    && return StyleText(font_ubuntu_bold_20, ambient.color)
    mode === :italic  && return StyleText(font_ubuntu_italic_20, ambient.color)
    mode === :link    && return StyleText(ambient.font, color_solarized_blue)
    mode === :heading && return StyleText(_heading_font(clamp(doc.level, 1, 6)), _HEADING_COLOR)
    ambient
end

# ── MarkdownStyledTextToSyntaxLeaf (rendered MarkdownText; reads ambient) ──────
# Same output shape and reference mapping as the source text leaf; the only
# difference is the font, taken from the ambient `:md_style` (or the body default).

@projection struct MarkdownStyledTextToSyntaxLeaf
    style::ImmutableCell{StyleText} = _BODY
end

function map_reference_forward(::MarkdownStyledTextToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        ::MarkdownText.content.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
    end
end

function map_reference_backward(::MarkdownStyledTextToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        ::SyntaxLeaf.value.rest... => @reference ::MarkdownText.content::String.^(rest)
    end
end

function print_document(p::MarkdownStyledTextToSyntaxLeaf, recursion, t::MarkdownText, ctx)
    style = get_property(ctx, :md_style, p.style)
    sel = ComputedCell(() -> begin
        s = t.selection
        is_introduced_reference(s) && return s
        map_reference_forward(p, nothing, s)
    end)
    SimpleIoMap(p, t, SyntaxLeaf(TextString(() -> t.content, style); selection=sel))
end

function read_intent(p::MarkdownStyledTextToSyntaxLeaf, iomap, op::ReplaceStringRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    ReplaceStringRangeOperation(new_ref, op.replacement)
end

function read_intent(p::MarkdownStyledTextToSyntaxLeaf, iomap, op::ReplaceSelectionOperation)
    path = op.path
    path isa ConcreteReference || return nothing
    h = path.head
    if h isa FieldReferenceStep && h.name == "value"
        return ReplaceSelectionOperation(@reference ::MarkdownText.content::String.^(path.tail))
    else
        return ReplaceSelectionOperation(@reference(iomap.input, proj(p, ^(path))))
    end
end

# ── MarkdownStyledInline (rendered Strong/Emphasis/Heading/Link) ───────────────
# A marker-free inline container that sets an ambient `:md_style` (its `mode`) and
# projects its `content` children through it (School A delegation). Output shape:
# a `SyntaxNode` whose children are the recursively projected content, so the
# reference mapping is the standard "delegate to child i" (modeled on
# YamlSequenceToBlockSyntaxNode, minus the per-item wrapper).

abstract type MarkdownStyledInline <: Projection end

struct MarkdownStrongToStyledNode   <: MarkdownStyledInline end
struct MarkdownEmphasisToStyledNode <: MarkdownStyledInline end
struct MarkdownHeadingToStyledNode  <: MarkdownStyledInline end
struct MarkdownLinkToStyledNode     <: MarkdownStyledInline end

_mode(::MarkdownStrongToStyledNode)   = :bold
_mode(::MarkdownEmphasisToStyledNode) = :italic
_mode(::MarkdownHeadingToStyledNode)  = :heading
_mode(::MarkdownLinkToStyledNode)     = :link

function print_document(p::MarkdownStyledInline, recursion, doc, ctx)
    ambient = get_property(ctx, :md_style, _BODY)
    style = _mode_style(_mode(p), ambient, doc)
    child_iomaps = ComputedCell(() -> [
        print_child(recursion, child,
            with_property(make_child_context(ctx, FieldReferenceStep("content"), ElementReferenceStep(i)), :md_style, style))
        for (i, child) in enumerate(doc.content)])
    items = ComputedCellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]])
    iomap_cell = Cell(nothing)
    sel = ComputedCell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)
    node = SyntaxNode(items; indentation=0, selection=sel)
    iomap = ChildrenIoMap(p, doc, node, child_iomaps)
    iomap_cell[] = iomap
    return iomap
end

# Forward is shared (input matched by the `content` field name, output is
# `::SyntaxNode`): no input-type literal is needed.
function map_reference_forward(p::MarkdownStyledInline, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
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
                1 <= child_i <= length(iomaps) || return nothing
                child = iomaps[child_i]
                inner = map_reference_backward(child.projection, child, rest)
                inner === nothing && return nothing
                @reference ::$D.content::CellVector[child_i].^(inner)
            end
        end
    end
end

function read_intent(p::MarkdownStyledInline, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    r = map_reference_backward(p, iomap, op.path)
    r === nothing ? nothing : ReplaceSelectionOperation(r)
end

function read_intent(p::MarkdownStyledInline, iomap::ChildrenIoMap, op::ReplaceStringRangeOperation)
    r = map_reference_backward(p, iomap, op.reference)
    r === nothing ? nothing : ReplaceStringRangeOperation(r, op.replacement)
end

# ── MarkdownImageToStyledNode (rendered; real image via TextGraphics) ─────────
# An `alt` caption above the decoded image (from `url`), falling back to the url
# text when the file is not on disk. Modelled on BookPictureToSyntaxLeaf.
#   .alt[k] → .children[1].value[k]   .url[k] → .children[2].value[k]

@projection struct MarkdownImageToStyledNode
    caption_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_italic_20, color_solarized_gray)
    placeholder::ImmutableCell{StyleText}   = StyleText(_MONO, color_solarized_gray)
end

# The image span: an inline `TextGraphics` with a lazily-decoded `ImageFile` when
# `url` names a file on disk (sized to its natural extent, capped at `max_w`);
# otherwise the url / a placeholder as text.
function _md_image_value(url, style::StyleText, placeholder::StyleText; max_w::Int = 640)
    if url isa AbstractString && !isempty(url) && isfile(String(url))
        path = String(url)
        img  = ImageFile(path)
        raw  = getfield(img, :raw)
        set_cell_function!(raw, () -> (try decode_image(path) catch; nothing end))
        _nat(i, fb) = (r = raw[]; (r isa Tuple && length(r) == 3) ? Int(r[i]) : fb)
        dw = ComputedCell(() -> Int32(min(_nat(2, 720), max_w)))
        dh = ComputedCell(() -> begin w = min(_nat(2, 720), max_w); Int32(round(Int, _nat(3, 460) * w / _nat(2, 720))) end)
        return TextGraphics(Cell(img), dw, dh, Cell(style.font), Cell(""),
                            Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    end
    TextString(isempty(String(url)) ? "image" : String(url), placeholder)
end

function print_document(p::MarkdownImageToStyledNode, recursion, doc::MarkdownImage, ctx)
    alt_sel = ComputedCell(() -> begin
        @reference_case doc.selection begin
            ::MarkdownImage.alt.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
        end
    end)
    url_sel = ComputedCell(() -> begin
        @reference_case doc.selection begin
            ::MarkdownImage.url.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
        end
    end)
    alt_leaf = SyntaxLeaf(
        make_hinted_text(() -> doc.alt, () -> isempty(doc.alt), "image", p.caption_style);
        selection=alt_sel)
    img_leaf = SyntaxLeaf(_md_image_value(doc.url, p.caption_style, p.placeholder); selection=url_sel)
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

function read_intent(p::MarkdownImageToStyledNode, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    r = map_reference_backward(p, iomap, op.path)
    r === nothing ? nothing : ReplaceSelectionOperation(r)
end
function read_intent(p::MarkdownImageToStyledNode, iomap::SimpleIoMap, op::ReplaceStringRangeOperation)
    r = map_reference_backward(p, iomap, op.reference)
    r === nothing ? nothing : ReplaceStringRangeOperation(r, op.replacement)
end

# ── MarkdownListToStyledNode (rendered; `1.` ordered / `•` unordered) ──────────
# The marker depends on the item index + `ordered`, which the template's
# homogeneous collection cannot inject, so this is hand-written like
# YamlSequenceToBlockSyntaxNode: each item is wrapped in a node whose `open` is the
# marker. Rendered `MarkdownListItem` carries no bullet (the List supplies it).
#   .items[i].rest ↔ .children[i].content.<item-mapped rest>

@projection struct MarkdownListToStyledNode
    marker_style::ImmutableCell{StyleText} = StyleText(font_dejavu_monospace_regular_20, color_solarized_gray)
end

_md_list_marker(ordered::Bool, i::Int) = ordered ? "$(i). " : "• "

function print_document(p::MarkdownListToStyledNode, recursion, lst::MarkdownList, ctx)
    child_iomaps = ComputedCell(() -> [print_child(recursion, item,
                                   make_child_context(ctx, FieldReferenceStep("items"), ElementReferenceStep(i)))
                               for (i, item) in enumerate(lst.items)])
    items = ComputedCellVector(() -> begin
        ord = lst.ordered
        SyntaxDocument[
            SyntaxDelimitation(im.output;
                               opening_delimiter=TextString(_md_list_marker(ord, i), p.marker_style))
            for (i, im) in enumerate(child_iomaps[]) ]
    end)
    iomap_cell = Cell(nothing)
    sel = ComputedCell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = lst.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)
    node = SyntaxNode(items; sep=TextString("\n", p.marker_style), indentation=0, selection=sel)
    iomap = ChildrenIoMap(p, lst, node, child_iomaps)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::MarkdownListToStyledNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
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
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::MarkdownList.items::CellVector[child_i].^(inner)
        end
    end
end

function read_intent(p::MarkdownListToStyledNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    r = map_reference_backward(p, iomap, op.path)
    r === nothing ? nothing : ReplaceSelectionOperation(r)
end
function read_intent(p::MarkdownListToStyledNode, iomap::ChildrenIoMap, op::ReplaceStringRangeOperation)
    r = map_reference_backward(p, iomap, op.reference)
    r === nothing ? nothing : ReplaceStringRangeOperation(r, op.replacement)
end

# ══════════════════════════════════════════════════════════════════════════════
# Dispatcher
# ══════════════════════════════════════════════════════════════════════════════

"""
    MarkdownToSyntax(; style::Symbol = :source)

Build the Markdown → Syntax projection. `style` is `:source` (colourised raw
markdown, fully editable including markers) or `:rendered` (formatted, marker-free
— see the module docstring).
"""
function MarkdownToSyntax(; style::Symbol = :source)
    style in (:source, :rendered) || error("MarkdownToSyntax: style must be :source or :rendered, got :$style")
    if style === :rendered
        gray_dejavu = StyleText(font_dejavu_monospace_regular_20, color_solarized_gray)
        return TypeDispatchingProjection(
            MarkdownInsertion     => MarkdownInsertionToSyntaxLeaf(),
            MarkdownText          => MarkdownStyledTextToSyntaxLeaf(),
            MarkdownCode          => MarkdownCodeToSyntaxLeaf(tick="",
                                        value_style=StyleText(_MONO, color_solarized_magenta)),
            MarkdownThematicBreak => MarkdownThematicBreakToSyntaxLeaf(text="────────────",
                                        style=gray_dejavu),
            MarkdownEmphasis      => MarkdownEmphasisToStyledNode(),
            MarkdownStrong        => MarkdownStrongToStyledNode(),
            MarkdownParagraph     => MarkdownParagraphToSyntaxNode(),
            MarkdownHeading       => MarkdownHeadingToStyledNode(),
            MarkdownCodeBlock     => MarkdownCodeBlockToSyntaxNode(open_fence="", close_fence="",
                                        lang_style=gray_dejavu),
            MarkdownQuote         => MarkdownQuoteToSyntaxNode(open_marker="▏ ", sep_marker="\n▏ ",
                                        marker_style=gray_dejavu),
            MarkdownList          => MarkdownListToStyledNode(),
            MarkdownListItem      => MarkdownListItemToSyntaxNode(bullet=""),
            MarkdownLink          => MarkdownLinkToStyledNode(),
            MarkdownImage         => MarkdownImageToStyledNode(),
            MarkdownRoot          => MarkdownRootToSyntaxNode(),
            # An embed keeps its marker in *both* styles when this projection
            # runs alone: a domain projection is the save path, and the save
            # path is by-marker. Rendering an embed inline is the shared
            # to-syntax fabric's job (`EmbedToSyntax`), which is what a page
            # goes through when it is read rather than written.
            ReferenceStub         => ReferenceStubToMarkdownSyntaxLeaf(),
            FileDocument          => EmbeddedFileDocumentToMarkdownSyntaxLeaf(),
            Vector{Cell}          => CopyingProjection(),
        )
    end
    TypeDispatchingProjection(
        MarkdownInsertion     => MarkdownInsertionToSyntaxLeaf(),
        MarkdownText          => MarkdownTextToSyntaxLeaf(),
        MarkdownCode          => MarkdownCodeToSyntaxLeaf(),
        MarkdownThematicBreak => MarkdownThematicBreakToSyntaxLeaf(),
        MarkdownEmphasis      => MarkdownEmphasisToSyntaxNode(),
        MarkdownStrong        => MarkdownStrongToSyntaxNode(),
        MarkdownParagraph     => MarkdownParagraphToSyntaxNode(),
        MarkdownHeading       => MarkdownHeadingToSyntaxNode(),
        MarkdownCodeBlock     => MarkdownCodeBlockToSyntaxNode(),
        MarkdownQuote         => MarkdownQuoteToSyntaxNode(),
        MarkdownList          => MarkdownListToSyntaxNode(),
        MarkdownListItem      => MarkdownListItemToSyntaxNode(),
        MarkdownLink          => MarkdownLinkToSyntaxNode(),
        MarkdownImage         => MarkdownImageToSyntaxNode(),
        MarkdownRoot          => MarkdownRootToSyntaxNode(),
        # A cross-file reference — either as a load-produced stub or
        # as an embedded FileDocument child — renders as a fenced
        # `pred-ref` code block so print_natural_text emits the right
        # thing without a pre-save AST mutation.
        ReferenceStub         => ReferenceStubToMarkdownSyntaxLeaf(),
        FileDocument          => EmbeddedFileDocumentToMarkdownSyntaxLeaf(),
        Vector{Cell}          => CopyingProjection(),
    )
end

# ── ReferenceStubToMarkdownSyntaxLeaf ───────────────────────────────────────
# ReferenceStub → a fenced `pred-ref` code block whose body is the
# marker text (`<<file(\"path\")>>`). Emitted as a single SyntaxLeaf
# holding the whole block text so print_natural_text writes it
# verbatim.

@projection struct ReferenceStubToMarkdownSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(_MONO, color_solarized_gray)
end

@projection_template ReferenceStubToMarkdownSyntaxLeaf ReferenceStub (p, s) ->
    SyntaxLeaf(TextString(_stub_marker_fence(s), p.style))

# A marker written in a line of prose goes back as it was found; one written as
# a block of its own goes back in its fence.
_stub_marker_fence(stub::ReferenceStub) =
    stub.inline ? format_marker_text(stub) : "```pred-ref\n" * format_marker_text(stub) * "\n```"

# ── EmbeddedFileDocumentToMarkdownSyntaxLeaf ────────────────────────────────

@projection struct EmbeddedFileDocumentToMarkdownSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(_MONO, color_solarized_gray)
end

@projection_template EmbeddedFileDocumentToMarkdownSyntaxLeaf FileDocument (p, f) ->
    SyntaxLeaf(TextString(_embedded_marker_fence(f), p.style))

_embedded_marker_fence(f::FileDocument) =
    "```pred-ref\n" * format_file_marker_text(get_filename(f)) * "\n```"

# ── Natural-projection registration ─────────────────────────────────────────
# The row that teaches the render-anything projection what this domain is. The
# factory form, so every renderer builds its own projection instance.
import ..NaturalRegistryModule: register_natural_syntax!
import ..MarkdownModule: MarkdownDocument

function __init__()
    register_natural_syntax!(:markdown, () -> Pair{Type,Any}[MarkdownDocument => MarkdownToSyntax(style = :rendered)])
end

end # module
