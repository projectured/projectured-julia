"""
    RstToSyntaxModule

RST → SyntaxDocument projection with two presentations, selected by
`RstToSyntax(; style)`:

- `:source` (default) — colourised **raw reStructuredText**: underlined
  section titles, `` ``literals`` ``, `` :ned:`roles` ``, `**bold**`,
  `- ` bullets, `.. directive::` lines with their option lines. Every marker
  is a text span, and every one-line field is editable. Written with
  `@projection_template`, so the reader is derived from the wiring.
- `:rendered` — **natural notation**, marker-free: large bold titles, real
  bold and italic, a role as a coloured chip, a figure as the picture itself,
  an admonition as a labelled box. Inline weight and colour cascade from a
  container to its descendant text through an ambient `:rst_style` in the
  printer context, the School A pattern `MarkdownToSyntax` uses.

**Indentation is written, not computed.** Every compound here carries
`indentation=0` and puts the indent into its own `open` and `sep` text. The
alternative — the compound's `indentation` field — indents in units of the
pipeline's `indent_size`, which `document_to_text` fixes at two, and RST needs
the indent of a directive body to be a width this slice chooses. Writing the
spaces keeps emit under this file's control, and it works because a paragraph
is one line: the parser joins a paragraph's source lines with a space.

**Verbatim bodies emit through a closure, not through `bound`.** The body of a
code block, a literal include, a literal block, a math block, a raw block and
a comment is opaque multi-line text that must be indented under its marker.
A `bound` leaf maps a text splice back by offset, and pre-indenting the render
would shift every offset past the first line. So these six render through a
plain computed `TextString`: correct on the page and correct on save, but not
splice-editable in the source view. Every other field stays `bound`.
"""
module RstToSyntaxModule

import ..CellModule: Cell, ComputedCell, set_cell_function!
import ..CollectionModule: CellVector, ComputedCellVector
import ..ProjectionApiModule: Projection, print_document, print_child, read_intent,
                              map_reference_forward, map_reference_backward
# The module binding itself, not only its names: the two macros below expand to
# `ProjectionApiModule.print_document(...)` definitions, and the unescaped name
# resolves in this module.
import ..ProjectionApiModule
import ..ProjectionModule: var"@projection"
import ..RstModule: RstDocument, RstInsertion, RstText, RstLiteral, RstEmphasis, RstStrong,
                    RstRole, RstReference, RstSubstitutionReference, RstFootnoteReference,
                    RstParagraph, RstLiteralBlock, RstLineBlock, RstListItem, RstBulletList,
                    RstEnumeratedList, RstDefinitionItem, RstDefinitionList, RstField,
                    RstFieldList, RstBlockQuote, RstTransition, RstComment, RstTarget,
                    RstSubstitutionDefinition, RstFootnote, RstTableCell, RstTableRow,
                    RstGridTable, RstDirectiveOption, RstLiteralInclude, RstFigure,
                    RstCodeBlock, RstImage, RstVideo, RstAudio, RstAdmonition, RstToctree,
                    RstMathBlock, RstRawBlock, RstRoleDefinition, RstDirective, RstSection,
                    RstRoot
import ..TextModule: TextString, hinted_text
import ..FontModule: font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20,
                     font_dejavu_monospace_regular_20
import ..ColorModule: color_black, color_solarized_blue, color_solarized_green,
                      color_solarized_magenta, color_solarized_cyan,
                      color_solarized_gray, color_solarized_violet,
                      color_solarized_yellow, color_solarized_orange
import ..StyleTextModule: StyleText, DStyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode, SyntaxConcatenation
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..CopyingProjectionModule: CopyingProjection
import ..ProjectionTemplateModule: var"@projection_template", bound, collection, project
import ..ProjectionTemplateModule: rule_print, template_read_intent
import ..PrinterContextModule: with_property, get_property
import ..IntentModule: Intent

export RstInsertionToSyntaxLeaf, RstTextToSyntaxLeaf, RstLiteralToSyntaxLeaf,
       RstEmphasisToSyntaxNode, RstStrongToSyntaxNode, RstRoleToSyntaxNode,
       RstReferenceToSyntaxNode, RstSubstitutionReferenceToSyntaxLeaf,
       RstFootnoteReferenceToSyntaxLeaf, RstParagraphToSyntaxNode,
       RstLiteralBlockToSyntaxLeaf, RstLineBlockToSyntaxNode, RstListItemToSyntaxNode,
       RstBulletListToSyntaxNode, RstEnumeratedListToSyntaxNode,
       RstDefinitionItemToSyntaxNode, RstDefinitionListToSyntaxNode,
       RstFieldToSyntaxNode, RstFieldListToSyntaxNode, RstBlockQuoteToSyntaxNode,
       RstTransitionToSyntaxLeaf, RstCommentToSyntaxLeaf, RstTargetToSyntaxLeaf,
       RstSubstitutionDefinitionToSyntaxNode, RstFootnoteToSyntaxNode,
       RstTableCellToSyntaxNode, RstTableRowToSyntaxNode, RstGridTableToSyntaxNode,
       RstDirectiveOptionToSyntaxNode, RstLiteralIncludeToSyntaxNode,
       RstFigureToSyntaxNode, RstCodeBlockToSyntaxNode, RstImageToSyntaxNode,
       RstVideoToSyntaxNode, RstAudioToSyntaxNode, RstAdmonitionToSyntaxNode,
       RstToctreeToSyntaxNode, RstMathBlockToSyntaxLeaf, RstRawBlockToSyntaxLeaf,
       RstRoleDefinitionToSyntaxNode, RstDirectiveToSyntaxNode, RstSectionToSyntaxNode,
       RstRootToSyntaxNode, RstToSyntax

const _MONO      = font_ubuntu_monospace_regular_20
const _MONO_BOLD = font_ubuntu_monospace_bold_20

# The body indent of a directive, a definition and a quote. Three spaces is what
# the corpus writes and what `.. ` is wide, so an emitted file reads like a
# hand-written one.
const _IND = "   "

# ── Emitted width of an inline run ────────────────────────────────────────────
# A section underline must be at least as long as its title, and the title is a
# run of inline nodes whose markers count. This measures the run the way the
# rules below print it. It is the one place where an emitted width is computed
# rather than laid out, because the underline is a single span.

_inline_source(::Any)                      = ""
_inline_source(x::RstText)                 = x.content
_inline_source(x::RstLiteral)              = "``" * x.content * "``"
_inline_source(x::RstRole)                 = ":" * x.name * ":`" * x.content * "`"
_inline_source(x::RstStrong)               = "**" * _run_source(x.content) * "**"
_inline_source(x::RstEmphasis)             = "*" * _run_source(x.content) * "*"
_inline_source(x::RstSubstitutionReference) = "|" * x.name * "|"
_inline_source(x::RstFootnoteReference)    = "[" * x.label * "]_"
_inline_source(x::RstReference) = "`" * x.text *
    (isempty(x.target) ? "" : " <" * x.target * ">") * "`" * (x.anonymous ? "__" : "_")

_run_source(nodes) = join((_inline_source(n) for n in nodes), "")

_title_width(title) = max(1, length(_run_source(title)))

# The underline (or overline) a section prints under its title.
_adornment_line(doc) = (isempty(doc.adornment) ? "=" : doc.adornment)^_title_width(doc.title)

# Indent every line of an opaque body, so it sits under the marker that owns it.
_indent_body(text::AbstractString, prefix::AbstractString = _IND) =
    isempty(text) ? "" : join((isempty(l) ? "" : prefix * l for l in split(text, '\n')), "\n")

# ── The ambient indent ────────────────────────────────────────────────────────
# A block that spans more than one line has to start each of its lines at the
# column its container put it in. The compound's own `indentation` field cannot
# express that: it writes a newline before the *first* child too, and it always
# costs one indent level, so a list's items would leave their marker column.
#
# So the indent travels as an ambient `:rst_indent` in the printer context, the
# way `MarkdownToSyntax` passes an ambient font down its rendered view. A
# container that owns an indented body pushes a deeper indent; every rule that
# writes a newline of its own reads the ambient and puts it after the newline.
# Because `make_child_context` derives from the context the rule was given, the
# ambient reaches every descendant without being threaded by hand.
#
# `@projection_template` builds the printer from `(prj, doc)` alone, so the two
# macros below wrap `rule_print` — the same entry point the template macro uses
# — and hand the builder the ambient as well. A rule keeps its template body;
# only its signature grows.

# The column the block this rule prints starts at.
_ambient(ctx) = something(get_property(ctx, :rst_indent, ""), "")

"""
    @rst_flat Projection DocumentType (prj, doc, indent) -> node

A rule whose children sit at its own column: a list and its items, a root and
its blocks. `indent` is that column, and the children inherit it.
"""
macro rst_flat(projname, intype, builder)
    quote
        function ProjectionApiModule.print_document(p::$(esc(projname)), recursion, doc::$(esc(intype)), ctx)
            indent = $(_ambient)(ctx)
            $(rule_print)(p, recursion, doc, ctx, (prj, d) -> $(esc(builder))(prj, d, indent))
        end
        function ProjectionApiModule.read_intent(p::$(esc(projname)), recursion, change::Intent, iomap)
            $(template_read_intent)(p, recursion, change, iomap)
        end
    end
end

"""
    @rst_indented Projection DocumentType (prj, doc, outer, inner) -> node

A rule that owns an indented body: a list item, a directive, an admonition, a
block quote. `outer` is the column the rule itself starts at, `inner` the
column of its body — and `inner` is what the children inherit.
"""
macro rst_indented(projname, intype, builder)
    quote
        function ProjectionApiModule.print_document(p::$(esc(projname)), recursion, doc::$(esc(intype)), ctx)
            outer = $(_ambient)(ctx)
            inner = outer * $(_IND)
            $(rule_print)(p, recursion, doc, $(with_property)(ctx, :rst_indent, inner),
                          (prj, d) -> $(esc(builder))(prj, d, outer, inner))
        end
        function ProjectionApiModule.read_intent(p::$(esc(projname)), recursion, change::Intent, iomap)
            $(template_read_intent)(p, recursion, change, iomap)
        end
    end
end

# ══════════════════════════════════════════════════════════════════════════════
# Source view (style = :source) — colourised raw RST
# ══════════════════════════════════════════════════════════════════════════════

# ── Inline leaves ─────────────────────────────────────────────────────────────

@projection struct RstInsertionToSyntaxLeaf
    style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
end

@projection_template RstInsertionToSyntaxLeaf RstInsertion (prj, doc) ->
    SyntaxLeaf(TextString("insert rst here", prj.style))

@projection struct RstTextToSyntaxLeaf
    style::ImmutableCell{DStyleText} = StyleText(_MONO, color_black)
end

@projection_template RstTextToSyntaxLeaf RstText (prj, doc) ->
    SyntaxLeaf(bound(:content, String,
                     hinted_text(() -> doc.content, () -> isempty(doc.content), "text", prj.style)))

@projection struct RstLiteralToSyntaxLeaf
    value_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_green)
    tick_style::ImmutableCell{DStyleText}  = StyleText(_MONO, color_solarized_gray)
    tick::String = "``"
end

@projection_template RstLiteralToSyntaxLeaf RstLiteral (prj, doc) ->
    SyntaxLeaf(bound(:content, String,
                     hinted_text(() -> doc.content, () -> isempty(doc.content), "literal", prj.value_style));
               open=TextString(prj.tick, prj.tick_style),
               close=TextString(prj.tick, prj.tick_style))

@projection struct RstEmphasisToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    marker::String = "*"
end

@projection_template RstEmphasisToSyntaxNode RstEmphasis (prj, doc) ->
    SyntaxNode(collection(:content);
               open=TextString(prj.marker, prj.marker_style),
               close=TextString(prj.marker, prj.marker_style))

@projection struct RstStrongToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    marker::String = "**"
end

@projection_template RstStrongToSyntaxNode RstStrong (prj, doc) ->
    SyntaxNode(collection(:content);
               open=TextString(prj.marker, prj.marker_style),
               close=TextString(prj.marker, prj.marker_style))

# `:name:`content`` — the name and the content are separate editable spans, and
# the colons and backquotes are the chrome between them.
@projection struct RstRoleToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    name_style::ImmutableCell{DStyleText}   = StyleText(_MONO, color_solarized_violet)
    value_style::ImmutableCell{DStyleText}  = StyleText(_MONO, color_solarized_cyan)
    open_marker::String  = ":"
    mid_marker::String   = ":`"
    close_marker::String = "`"
end

@projection_template RstRoleToSyntaxNode RstRole (prj, doc) ->
    SyntaxConcatenation([ SyntaxLeaf(bound(:name, String,
                                           hinted_text(() -> doc.name, () -> isempty(doc.name), "role", prj.name_style));
                                     open=TextString(prj.open_marker, prj.marker_style),
                                     close=TextString(prj.mid_marker, prj.marker_style)),
                          SyntaxLeaf(bound(:content, String,
                                           hinted_text(() -> doc.content, () -> isempty(doc.content), "value", prj.value_style));
                                     close=TextString(prj.close_marker, prj.marker_style)) ])

# `` `text <target>`_ `` — the angled part disappears when the target is empty,
# which is the named-reference form `` `name`_ ``.
@projection struct RstReferenceToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    text_style::ImmutableCell{DStyleText}   = StyleText(_MONO, color_solarized_blue)
    target_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_violet)
    show_markers::Bool = true
end

@projection_template RstReferenceToSyntaxNode RstReference (prj, doc) ->
    SyntaxConcatenation([ SyntaxLeaf(bound(:text, String,
                                           hinted_text(() -> doc.text, () -> isempty(doc.text), "link", prj.text_style));
                                     open=TextString(prj.show_markers ? "`" : "", prj.marker_style)),
                          SyntaxLeaf(bound(:target, String, TextString(() -> doc.target, prj.target_style));
                                     open=TextString(() -> !prj.show_markers || isempty(doc.target) ? "" : " <", prj.marker_style),
                                     close=TextString(() -> !prj.show_markers ? "" :
                                                            (isempty(doc.target) ? "" : ">") * "`" * (doc.anonymous ? "__" : "_"),
                                                     prj.marker_style)) ])

@projection struct RstSubstitutionReferenceToSyntaxLeaf
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    style::ImmutableCell{DStyleText}        = StyleText(_MONO, color_solarized_orange)
    marker::String = "|"
end

@projection_template RstSubstitutionReferenceToSyntaxLeaf RstSubstitutionReference (prj, doc) ->
    SyntaxLeaf(bound(:name, String,
                     hinted_text(() -> doc.name, () -> isempty(doc.name), "name", prj.style));
               open=TextString(prj.marker, prj.marker_style),
               close=TextString(prj.marker, prj.marker_style))

@projection struct RstFootnoteReferenceToSyntaxLeaf
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    style::ImmutableCell{DStyleText}        = StyleText(_MONO, color_solarized_blue)
    open_marker::String  = "["
    close_marker::String = "]_"
end

@projection_template RstFootnoteReferenceToSyntaxLeaf RstFootnoteReference (prj, doc) ->
    SyntaxLeaf(bound(:label, String,
                     hinted_text(() -> doc.label, () -> isempty(doc.label), "n", prj.style));
               open=TextString(prj.open_marker, prj.marker_style),
               close=TextString(prj.close_marker, prj.marker_style))

# ── Blocks ────────────────────────────────────────────────────────────────────

@projection struct RstParagraphToSyntaxNode end

@projection_template RstParagraphToSyntaxNode RstParagraph (prj, doc) ->
    SyntaxNode(collection(:content); indentation=0)

@projection struct RstLiteralBlockToSyntaxLeaf
    style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_green)
end

# The block writes its own `::` marker on a line of its own. The parser takes
# the marker off the paragraph that introduced it — `text::` is stored as the
# paragraph `text:` plus this block — so emitting the body alone would leave an
# indented run with nothing to introduce it, and that re-reads as a block quote.
# A standalone `::` is the expanded form RST allows for exactly this.
@rst_indented RstLiteralBlockToSyntaxLeaf RstLiteralBlock (prj, doc, outer, inner) ->
    SyntaxLeaf(TextString(() -> "::\n\n" * _indent_body(doc.content, inner), prj.style);
               open=TextString("", prj.style))

@projection struct RstLineBlockToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    open_marker::String = "| "
    sep_marker::String  = "\n| "
end

@rst_flat RstLineBlockToSyntaxNode RstLineBlock (prj, doc, indent) ->
    SyntaxNode(collection(:lines);
               open=TextString(prj.open_marker, prj.marker_style),
               sep=TextString("\n" * indent * prj.open_marker, prj.marker_style),
               indentation=0)

# An item carries no marker of its own: the **list** writes it, because the
# marker belongs to the list (`-`, `*` or `+` for a bullet list, the running
# number for an enumerated one) and one item rule then serves both. The item
# only stacks its own blocks under the marker's content column.
@projection struct RstListItemToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    sep::String = "\n\n   "
end

@rst_indented RstListItemToSyntaxNode RstListItem (prj, doc, outer, inner) ->
    SyntaxNode(collection(:elements);
               sep=TextString("\n\n" * inner, prj.marker_style),
               indentation=0)

# `-  item` — the marker plus two spaces, so a continuation line indents by the
# three spaces the item rule writes.
_bullet_marker(doc) = (isempty(doc.marker) ? "-" : doc.marker) * "  "

# `1. item`. Every item prints the list's own start number rather than a
# running one, because an item does not know its index. RST accepts that and
# renumbers on render, and a re-parse recovers the same list.
_enum_marker(doc) = (startswith(doc.style, "#") ? "#" : string(doc.start)) *
                    (isempty(doc.style) ? "." : doc.style[end:end]) * " "

@projection struct RstBulletListToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
end

@rst_flat RstBulletListToSyntaxNode RstBulletList (prj, doc, indent) ->
    SyntaxNode(collection(:items);
               open=TextString(() -> _bullet_marker(doc), prj.marker_style),
               sep=TextString(() -> "\n" * indent * _bullet_marker(doc), prj.marker_style),
               indentation=0)

@projection struct RstEnumeratedListToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
end

@rst_flat RstEnumeratedListToSyntaxNode RstEnumeratedList (prj, doc, indent) ->
    SyntaxNode(collection(:items);
               open=TextString(() -> _enum_marker(doc), prj.marker_style),
               sep=TextString(() -> "\n" * indent * _enum_marker(doc), prj.marker_style),
               indentation=0)

@projection struct RstDefinitionItemToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
end

@rst_indented RstDefinitionItemToSyntaxNode RstDefinitionItem (prj, doc, outer, inner) ->
    SyntaxConcatenation([ SyntaxNode(collection(:term); indentation=0),
                          SyntaxNode(collection(:elements);
                                     open=TextString(() -> isempty(doc.elements) ? "" : "\n" * inner, prj.marker_style),
                                     sep=TextString("\n\n" * inner, prj.marker_style),
                                     indentation=0) ])

@projection struct RstDefinitionListToSyntaxNode end

@rst_flat RstDefinitionListToSyntaxNode RstDefinitionList (prj, doc, indent) ->
    SyntaxNode(collection(:items); sep=TextString("\n\n" * indent), indentation=0)

@projection struct RstFieldToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    name_style::ImmutableCell{DStyleText}   = StyleText(_MONO, color_solarized_blue)
end

@rst_indented RstFieldToSyntaxNode RstField (prj, doc, outer, inner) ->
    SyntaxConcatenation([ SyntaxLeaf(bound(:name, String,
                                           hinted_text(() -> doc.name, () -> isempty(doc.name), "field", prj.name_style));
                                     open=TextString(":", prj.marker_style),
                                     close=TextString(": ", prj.marker_style)),
                          SyntaxNode(collection(:elements); sep=TextString("\n" * inner, prj.marker_style), indentation=0) ])

@projection struct RstFieldListToSyntaxNode end

@rst_flat RstFieldListToSyntaxNode RstFieldList (prj, doc, indent) ->
    SyntaxNode(collection(:fields); sep=TextString("\n" * indent), indentation=0)

@projection struct RstBlockQuoteToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
end

@rst_indented RstBlockQuoteToSyntaxNode RstBlockQuote (prj, doc, outer, inner) ->
    SyntaxNode(collection(:elements);
               open=TextString(_IND, prj.marker_style),
               sep=TextString("\n\n" * inner, prj.marker_style),
               close=TextString(() -> isempty(doc.attribution) ? "" :
                                      "\n\n" * inner * "-- " * doc.attribution,
                                prj.marker_style),
               indentation=0)

@projection struct RstTransitionToSyntaxLeaf
    style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    text::String = "----"
end

@projection_template RstTransitionToSyntaxLeaf RstTransition (prj, doc) ->
    SyntaxLeaf(TextString(prj.text, prj.style))

@projection struct RstCommentToSyntaxLeaf
    style::ImmutableCell{DStyleText}  = StyleText(_MONO, color_solarized_gray)
    marker::String = ".. "
    show_marker::Bool = true
end

# The body is opaque multi-line text: the first line rides the `.. ` marker and
# every later line is indented under it.
@rst_indented RstCommentToSyntaxLeaf RstComment (prj, doc, outer, inner) ->
    SyntaxLeaf(TextString(() -> begin
                              lines = split(doc.content, '\n')
                              head = isempty(lines) ? "" : String(lines[1])
                              rest = length(lines) <= 1 ? "" :
                                     "\n" * _indent_body(join(lines[2:end], "\n"), inner)
                              (prj.show_marker ? prj.marker : "") * head * rest
                          end, prj.style))

@projection struct RstTargetToSyntaxLeaf
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    style::ImmutableCell{DStyleText}        = StyleText(_MONO, color_solarized_violet)
    open_marker::String  = ".. _"
    close_marker::String = ":"
end

@projection_template RstTargetToSyntaxLeaf RstTarget (prj, doc) ->
    SyntaxLeaf(bound(:name, String,
                     hinted_text(() -> doc.name, () -> isempty(doc.name), "name", prj.style));
               open=TextString(prj.open_marker, prj.marker_style),
               close=TextString(prj.close_marker, prj.marker_style))

@projection struct RstSubstitutionDefinitionToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    name_style::ImmutableCell{DStyleText}   = StyleText(_MONO, color_solarized_orange)
end

@rst_indented RstSubstitutionDefinitionToSyntaxNode RstSubstitutionDefinition (prj, doc, outer, inner) ->
    SyntaxConcatenation([ SyntaxLeaf(bound(:name, String,
                                           hinted_text(() -> doc.name, () -> isempty(doc.name), "name", prj.name_style));
                                     open=TextString(".. |", prj.marker_style),
                                     close=TextString("| ", prj.marker_style)),
                          project(:body) ])

@projection struct RstFootnoteToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    label_style::ImmutableCell{DStyleText}  = StyleText(_MONO, color_solarized_blue)
end

@rst_indented RstFootnoteToSyntaxNode RstFootnote (prj, doc, outer, inner) ->
    SyntaxConcatenation([ SyntaxLeaf(bound(:label, String,
                                           hinted_text(() -> doc.label, () -> isempty(doc.label), "n", prj.label_style));
                                     open=TextString(".. [", prj.marker_style),
                                     close=TextString("] ", prj.marker_style)),
                          SyntaxNode(collection(:elements); sep=TextString("\n\n" * inner, prj.marker_style), indentation=0) ])

# ── Tables ────────────────────────────────────────────────────────────────────
# A grid table redraws its whole `+--+--+` ruling from one closure. Laying the
# grid out span by span would need each cell's emitted width *before* the row
# prints, and a printer never has a sibling's width. So the table is the
# seventh opaque body: correct on the page and correct on save, but a cell is
# navigated through the document, not through the source text. The rendered
# view lays the cells out as a real table instead, cell by cell.
#
# A cell keeps its own rule so the rendered view has one to replace.

_block_source(::Any)            = ""
_block_source(x::RstParagraph)  = _run_source(x.content)
_block_source(x::RstLiteral)    = _inline_source(x)

_cell_source(cell) = String(strip(join((_block_source(b) for b in cell.elements), " ")))

function _grid_table_text(doc)
    rows = collect(doc.rows)
    isempty(rows) && return ""
    columns = maximum(length(r.cells) for r in rows)
    texts = [[k <= length(r.cells) ? _cell_source(r.cells[k]) : "" for k in 1:columns] for r in rows]
    stored = collect(doc.widths)
    # A column is wide enough for its widest cell plus the one leading space,
    # and never narrower than the source drew it. Asking for a trailing space as
    # well would widen a column whose cell the source wrapped over two lines,
    # because a cell rejoins as one line here.
    widths = [max(k <= length(stored) ? Int(stored[k]) : 0,
                  maximum(length(t[k]) for t in texts) + 1) for k in 1:columns]
    ruling(fill) = "+" * join((fill^w for w in widths), "+") * "+"
    lines = String[ruling("-")]
    for (i, row) in enumerate(texts)
        push!(lines, "|" * join((" " * rpad(row[k], widths[k] - 1) for k in 1:columns), "|") * "|")
        push!(lines, ruling(i == doc.header_rows ? "=" : "-"))
    end
    join(lines, "\n")
end

@projection struct RstTableCellToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
end

@projection_template RstTableCellToSyntaxNode RstTableCell (prj, doc) ->
    SyntaxNode(collection(:elements); sep=TextString(" ", prj.marker_style), indentation=0)

@projection struct RstTableRowToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
end

@projection_template RstTableRowToSyntaxNode RstTableRow (prj, doc) ->
    SyntaxNode(collection(:cells); sep=TextString(" | ", prj.marker_style), indentation=0)

@projection struct RstGridTableToSyntaxNode
    style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
end

@rst_flat RstGridTableToSyntaxNode RstGridTable (prj, doc, indent) ->
    SyntaxLeaf(TextString(() -> _indent_body(_grid_table_text(doc), indent)[length(indent) + 1:end],
                          prj.style))

# ── Directives ────────────────────────────────────────────────────────────────

@projection struct RstDirectiveOptionToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    name_style::ImmutableCell{DStyleText}   = StyleText(_MONO, color_solarized_blue)
    value_style::ImmutableCell{DStyleText}  = StyleText(_MONO, color_black)
end

@projection_template RstDirectiveOptionToSyntaxNode RstDirectiveOption (prj, doc) ->
    SyntaxConcatenation([ SyntaxLeaf(bound(:name, String,
                                           hinted_text(() -> doc.name, () -> isempty(doc.name), "option", prj.name_style));
                                     open=TextString(":", prj.marker_style),
                                     close=TextString(":", prj.marker_style)),
                          SyntaxLeaf(bound(:value, String, TextString(() -> doc.value, prj.value_style));
                                     open=TextString(() -> isempty(doc.value) ? "" : " ", prj.marker_style)) ])

# One helper shape for every typed directive: a `.. name:: argument` header, a
# run of named option lines, the extra options the parser did not name, and the
# body. A named option prints nothing at all when its field is empty, so the
# emitted file carries only the options the source had.
_option_open(prj, value_getter, name, indent) =
    TextString(() -> isempty(value_getter()) ? "" : "\n" * indent * ":" * name * ": ", prj.marker_style)

@projection struct RstLiteralIncludeToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    path_style::ImmutableCell{DStyleText}   = StyleText(_MONO, color_solarized_violet)
    value_style::ImmutableCell{DStyleText}  = StyleText(_MONO, color_black)
    header::String = ".. literalinclude:: "
end

@rst_indented RstLiteralIncludeToSyntaxNode RstLiteralInclude (prj, doc, outer, inner) ->
    SyntaxConcatenation([
        SyntaxLeaf(bound(:path, String,
                         hinted_text(() -> doc.path, () -> isempty(doc.path), "path", prj.path_style));
                   open=TextString(prj.header, prj.marker_style)),
        SyntaxLeaf(bound(:language, String, TextString(() -> doc.language, prj.value_style));
                   open=_option_open(prj, () -> doc.language, "language", inner)),
        SyntaxLeaf(bound(:start_at, String, TextString(() -> doc.start_at, prj.value_style));
                   open=_option_open(prj, () -> doc.start_at, "start-at", inner)),
        SyntaxLeaf(bound(:end_at, String, TextString(() -> doc.end_at, prj.value_style));
                   open=_option_open(prj, () -> doc.end_at, "end-at", inner)),
        SyntaxLeaf(bound(:start_after, String, TextString(() -> doc.start_after, prj.value_style));
                   open=_option_open(prj, () -> doc.start_after, "start-after", inner)),
        SyntaxLeaf(bound(:end_before, String, TextString(() -> doc.end_before, prj.value_style));
                   open=_option_open(prj, () -> doc.end_before, "end-before", inner)),
        SyntaxNode(collection(:extra);
                   open=TextString(() -> isempty(doc.extra) ? "" : "\n" * inner, prj.marker_style),
                   sep=TextString("\n" * inner, prj.marker_style), indentation=0) ])

@projection struct RstFigureToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    path_style::ImmutableCell{DStyleText}   = StyleText(_MONO, color_solarized_violet)
    value_style::ImmutableCell{DStyleText}  = StyleText(_MONO, color_black)
    header::String = ".. figure:: "
end

@rst_indented RstFigureToSyntaxNode RstFigure (prj, doc, outer, inner) ->
    SyntaxConcatenation([
        SyntaxLeaf(bound(:path, String,
                         hinted_text(() -> doc.path, () -> isempty(doc.path), "path", prj.path_style));
                   open=TextString(prj.header, prj.marker_style)),
        SyntaxLeaf(bound(:align, String, TextString(() -> doc.align, prj.value_style));
                   open=_option_open(prj, () -> doc.align, "align", inner)),
        SyntaxLeaf(bound(:width, String, TextString(() -> doc.width, prj.value_style));
                   open=_option_open(prj, () -> doc.width, "width", inner)),
        SyntaxNode(collection(:extra);
                   open=TextString(() -> isempty(doc.extra) ? "" : "\n" * inner, prj.marker_style),
                   sep=TextString("\n" * inner, prj.marker_style), indentation=0),
        SyntaxNode(collection(:caption);
                   open=TextString(() -> isempty(doc.caption) ? "" : "\n\n" * inner, prj.marker_style),
                   sep=TextString("\n\n" * inner, prj.marker_style), indentation=0) ])

@projection struct RstCodeBlockToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    lang_style::ImmutableCell{DStyleText}   = StyleText(_MONO, color_solarized_magenta)
    code_style::ImmutableCell{DStyleText}   = StyleText(_MONO, color_solarized_green)
    header::String = ".. code-block:: "
end

@rst_indented RstCodeBlockToSyntaxNode RstCodeBlock (prj, doc, outer, inner) ->
    SyntaxConcatenation([
        SyntaxLeaf(bound(:language, String, TextString(() -> doc.language, prj.lang_style));
                   open=TextString(prj.header, prj.marker_style)),
        SyntaxNode(collection(:extra);
                   open=TextString(() -> isempty(doc.extra) ? "" : "\n" * inner, prj.marker_style),
                   sep=TextString("\n" * inner, prj.marker_style), indentation=0),
        SyntaxLeaf(TextString(() -> isempty(doc.code) ? "" :
                                    "\n\n" * _indent_body(doc.code, inner), prj.code_style)) ])

@projection struct RstImageToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    path_style::ImmutableCell{DStyleText}   = StyleText(_MONO, color_solarized_violet)
    value_style::ImmutableCell{DStyleText}  = StyleText(_MONO, color_black)
    header::String = ".. image:: "
end

@rst_indented RstImageToSyntaxNode RstImage (prj, doc, outer, inner) ->
    SyntaxConcatenation([
        SyntaxLeaf(bound(:path, String,
                         hinted_text(() -> doc.path, () -> isempty(doc.path), "path", prj.path_style));
                   open=TextString(prj.header, prj.marker_style)),
        SyntaxLeaf(bound(:width, String, TextString(() -> doc.width, prj.value_style));
                   open=_option_open(prj, () -> doc.width, "width", inner)),
        SyntaxLeaf(bound(:height, String, TextString(() -> doc.height, prj.value_style));
                   open=_option_open(prj, () -> doc.height, "height", inner)),
        SyntaxLeaf(bound(:alt, String, TextString(() -> doc.alt, prj.value_style));
                   open=_option_open(prj, () -> doc.alt, "alt", inner)),
        SyntaxNode(collection(:extra);
                   open=TextString(() -> isempty(doc.extra) ? "" : "\n" * inner, prj.marker_style),
                   sep=TextString("\n" * inner, prj.marker_style), indentation=0) ])

@projection struct RstVideoToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    path_style::ImmutableCell{DStyleText}   = StyleText(_MONO, color_solarized_violet)
    value_style::ImmutableCell{DStyleText}  = StyleText(_MONO, color_black)
end

@rst_indented RstVideoToSyntaxNode RstVideo (prj, doc, outer, inner) ->
    SyntaxConcatenation([
        SyntaxLeaf(bound(:path, String,
                         hinted_text(() -> doc.path, () -> isempty(doc.path), "path", prj.path_style));
                   open=TextString(() -> ".. " * (doc.loop ? "video" : "video_noloop") * ":: ",
                                   prj.marker_style)),
        SyntaxLeaf(bound(:width, String, TextString(() -> doc.width, prj.value_style));
                   open=_option_open(prj, () -> doc.width, "width", inner)),
        SyntaxLeaf(bound(:height, String, TextString(() -> doc.height, prj.value_style));
                   open=_option_open(prj, () -> doc.height, "height", inner)),
        SyntaxNode(collection(:extra);
                   open=TextString(() -> isempty(doc.extra) ? "" : "\n" * inner, prj.marker_style),
                   sep=TextString("\n" * inner, prj.marker_style), indentation=0) ])

@projection struct RstAudioToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    path_style::ImmutableCell{DStyleText}   = StyleText(_MONO, color_solarized_violet)
    header::String = ".. audio:: "
end

@rst_indented RstAudioToSyntaxNode RstAudio (prj, doc, outer, inner) ->
    SyntaxConcatenation([
        SyntaxLeaf(bound(:path, String,
                         hinted_text(() -> doc.path, () -> isempty(doc.path), "path", prj.path_style));
                   open=TextString(prj.header, prj.marker_style)),
        SyntaxNode(collection(:extra);
                   open=TextString(() -> isempty(doc.extra) ? "" : "\n" * inner, prj.marker_style),
                   sep=TextString("\n" * inner, prj.marker_style), indentation=0) ])

@projection struct RstAdmonitionToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO_BOLD, color_solarized_yellow)
end

@rst_indented RstAdmonitionToSyntaxNode RstAdmonition (prj, doc, outer, inner) ->
    SyntaxNode(collection(:elements);
               open=TextString(() -> ".. " * doc.kind * "::\n\n" * inner, prj.marker_style),
               sep=TextString("\n\n" * inner, prj.marker_style),
               indentation=0)

@projection struct RstToctreeToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    entry_style::ImmutableCell{DStyleText}  = StyleText(_MONO, color_solarized_blue)
end

@rst_indented RstToctreeToSyntaxNode RstToctree (prj, doc, outer, inner) ->
    SyntaxConcatenation([
        SyntaxLeaf(TextString(() -> ".. toctree::" *
                                    (doc.maxdepth == 0 ? "" : "\n" * inner * ":maxdepth: " * string(doc.maxdepth)) *
                                    (doc.titlesonly ? "\n" * inner * ":titlesonly:" : "") *
                                    (doc.glob ? "\n" * inner * ":glob:" : ""),
                              prj.marker_style)),
        SyntaxNode(collection(:extra);
                   open=TextString(() -> isempty(doc.extra) ? "" : "\n" * inner, prj.marker_style),
                   sep=TextString("\n" * inner, prj.marker_style), indentation=0),
        SyntaxNode(collection(:entries);
                   open=TextString(() -> isempty(doc.entries) ? "" : "\n\n" * inner, prj.entry_style),
                   sep=TextString("\n" * inner, prj.entry_style), indentation=0) ])

@projection struct RstMathBlockToSyntaxLeaf
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    style::ImmutableCell{DStyleText}        = StyleText(_MONO, color_solarized_cyan)
    show_marker::Bool = true
end

@rst_indented RstMathBlockToSyntaxLeaf RstMathBlock (prj, doc, outer, inner) ->
    SyntaxLeaf(TextString(() -> (prj.show_marker ? ".. math::\n\n" : "") * _indent_body(doc.content, inner),
                          prj.style))

@projection struct RstRawBlockToSyntaxLeaf
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    style::ImmutableCell{DStyleText}        = StyleText(_MONO, color_solarized_gray)
end

@rst_indented RstRawBlockToSyntaxLeaf RstRawBlock (prj, doc, outer, inner) ->
    SyntaxLeaf(TextString(() -> ".. raw:: " * doc.format * "\n\n" * _indent_body(doc.content, inner),
                          prj.style))

@projection struct RstRoleDefinitionToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    name_style::ImmutableCell{DStyleText}   = StyleText(_MONO, color_solarized_violet)
end

@rst_indented RstRoleDefinitionToSyntaxNode RstRoleDefinition (prj, doc, outer, inner) ->
    SyntaxConcatenation([
        SyntaxLeaf(bound(:name, String,
                         hinted_text(() -> doc.name, () -> isempty(doc.name), "role", prj.name_style));
                   open=TextString(".. role:: ", prj.marker_style),
                   close=TextString(() -> isempty(doc.base) ? "" : "(" * doc.base * ")", prj.marker_style)),
        SyntaxNode(collection(:extra);
                   open=TextString(() -> isempty(doc.extra) ? "" : "\n" * inner, prj.marker_style),
                   sep=TextString("\n" * inner, prj.marker_style), indentation=0) ])

@projection struct RstDirectiveToSyntaxNode
    marker_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_gray)
    name_style::ImmutableCell{DStyleText}   = StyleText(_MONO, color_solarized_magenta)
    arg_style::ImmutableCell{DStyleText}    = StyleText(_MONO, color_black)
end

@rst_indented RstDirectiveToSyntaxNode RstDirective (prj, doc, outer, inner) ->
    SyntaxConcatenation([
        SyntaxLeaf(bound(:name, String,
                         hinted_text(() -> doc.name, () -> isempty(doc.name), "directive", prj.name_style));
                   open=TextString(".. ", prj.marker_style),
                   close=TextString(":: ", prj.marker_style)),
        SyntaxLeaf(bound(:argument, String, TextString(() -> doc.argument, prj.arg_style))),
        SyntaxNode(collection(:options);
                   open=TextString(() -> isempty(doc.options) ? "" : "\n" * inner, prj.marker_style),
                   sep=TextString("\n" * inner, prj.marker_style), indentation=0),
        SyntaxNode(collection(:elements);
                   open=TextString(() -> isempty(doc.elements) ? "" : "\n\n" * inner, prj.marker_style),
                   sep=TextString("\n\n" * inner, prj.marker_style), indentation=0) ])

# ── Section and root ──────────────────────────────────────────────────────────

@projection struct RstSectionToSyntaxNode
    adornment_style::ImmutableCell{DStyleText} = StyleText(_MONO, color_solarized_blue)
    title_style::ImmutableCell{DStyleText}     = StyleText(_MONO_BOLD, color_solarized_blue)
end

@rst_flat RstSectionToSyntaxNode RstSection (prj, doc, indent) ->
    SyntaxConcatenation([
        SyntaxNode(collection(:title);
                   open=TextString(() -> doc.overline ? _adornment_line(doc) * "\n" : "",
                                   prj.adornment_style),
                   close=TextString(() -> "\n" * _adornment_line(doc), prj.adornment_style),
                   indentation=0),
        SyntaxNode(collection(:elements);
                   open=TextString(() -> isempty(doc.elements) ? "" : "\n\n" * indent, prj.adornment_style),
                   sep=TextString("\n\n" * indent, prj.adornment_style), indentation=0) ])

@projection struct RstRootToSyntaxNode
    style::ImmutableCell{DStyleText} = StyleText(_MONO, color_black)
end

@rst_flat RstRootToSyntaxNode RstRoot (prj, doc, indent) ->
    SyntaxNode(collection(:elements); sep=TextString("\n\n" * indent, prj.style), indentation=0)

# ══════════════════════════════════════════════════════════════════════════════
# Dispatcher
# ══════════════════════════════════════════════════════════════════════════════

# The source dispatch table. The rendered style is built from it by replacing
# the rules whose presentation differs, so a rule that reads the same either way
# is written once.
_source_rules() = Pair{Any,Any}[
    RstInsertion               => RstInsertionToSyntaxLeaf(),
    RstText                    => RstTextToSyntaxLeaf(),
    RstLiteral                 => RstLiteralToSyntaxLeaf(),
    RstEmphasis                => RstEmphasisToSyntaxNode(),
    RstStrong                  => RstStrongToSyntaxNode(),
    RstRole                    => RstRoleToSyntaxNode(),
    RstReference               => RstReferenceToSyntaxNode(),
    RstSubstitutionReference   => RstSubstitutionReferenceToSyntaxLeaf(),
    RstFootnoteReference       => RstFootnoteReferenceToSyntaxLeaf(),
    RstParagraph               => RstParagraphToSyntaxNode(),
    RstLiteralBlock            => RstLiteralBlockToSyntaxLeaf(),
    RstLineBlock               => RstLineBlockToSyntaxNode(),
    RstListItem                => RstListItemToSyntaxNode(),
    RstBulletList              => RstBulletListToSyntaxNode(),
    RstEnumeratedList          => RstEnumeratedListToSyntaxNode(),
    RstDefinitionItem          => RstDefinitionItemToSyntaxNode(),
    RstDefinitionList          => RstDefinitionListToSyntaxNode(),
    RstField                   => RstFieldToSyntaxNode(),
    RstFieldList               => RstFieldListToSyntaxNode(),
    RstBlockQuote              => RstBlockQuoteToSyntaxNode(),
    RstTransition              => RstTransitionToSyntaxLeaf(),
    RstComment                 => RstCommentToSyntaxLeaf(),
    RstTarget                  => RstTargetToSyntaxLeaf(),
    RstSubstitutionDefinition  => RstSubstitutionDefinitionToSyntaxNode(),
    RstFootnote                => RstFootnoteToSyntaxNode(),
    RstTableCell               => RstTableCellToSyntaxNode(),
    RstTableRow                => RstTableRowToSyntaxNode(),
    RstGridTable               => RstGridTableToSyntaxNode(),
    RstDirectiveOption         => RstDirectiveOptionToSyntaxNode(),
    RstLiteralInclude          => RstLiteralIncludeToSyntaxNode(),
    RstFigure                  => RstFigureToSyntaxNode(),
    RstCodeBlock               => RstCodeBlockToSyntaxNode(),
    RstImage                   => RstImageToSyntaxNode(),
    RstVideo                   => RstVideoToSyntaxNode(),
    RstAudio                   => RstAudioToSyntaxNode(),
    RstAdmonition              => RstAdmonitionToSyntaxNode(),
    RstToctree                 => RstToctreeToSyntaxNode(),
    RstMathBlock               => RstMathBlockToSyntaxLeaf(),
    RstRawBlock                => RstRawBlockToSyntaxLeaf(),
    RstRoleDefinition          => RstRoleDefinitionToSyntaxNode(),
    RstDirective               => RstDirectiveToSyntaxNode(),
    RstSection                 => RstSectionToSyntaxNode(),
    RstRoot                    => RstRootToSyntaxNode(),
    Vector{Cell}               => CopyingProjection(),
]

"""
    RstToSyntax(; style::Symbol = :source)

Build the RST → Syntax projection. `style` is `:source` (colourised raw RST,
fully editable including the markers) or `:rendered` (the natural notation,
marker-free — see the module docstring).
"""
function RstToSyntax(; style::Symbol = :source)
    style in (:source, :rendered) || error("RstToSyntax: style must be :source or :rendered, got :$style")
    TypeDispatchingProjection(_source_rules()...)
end

end # module
