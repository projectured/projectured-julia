# Fragment of `RstModule`.
#
# RST → SyntaxDocument projection with two presentations, selected by
# `RstToSyntax(; style)`:
#
# - `:source` (default) — colourised **raw reStructuredText**: underlined
#   section titles, `` ``literals`` ``, `` :ned:`roles` ``, `**bold**`,
#   `- ` bullets, `.. directive::` lines with their option lines. Every marker
#   is a text span, and every one-line field is editable. Written with
#   `@projection_template`, so the reader is derived from the wiring.
# - `:rendered` — **natural notation**, marker-free: large bold titles, real
#   bold and italic, a role as a coloured chip, a figure as the picture itself,
#   an admonition as a labelled box. Inline weight and colour cascade from a
#   container to its descendant text through an ambient `:rst_style` in the
#   printer context, the School A pattern `MarkdownToSyntax` uses.
#
# **Indentation is written, not computed.** Every compound here carries
# `indentation=0` and puts the indent into its own `open` and `sep` text. The
# alternative — the compound's `indentation` field — indents in units of the
# pipeline's `indent_size`, which `print_natural_text` fixes at two, and RST needs
# the indent of a directive body to be a width this slice chooses. Writing the
# spaces keeps emit under this file's control, and it works because a paragraph
# is one line: the parser joins a paragraph's source lines with a space.
#
# **Verbatim bodies emit through a closure, not through `bound`.** The body of a
# code block, a literal include, a literal block, a math block, a raw block, a
# comment and a grid table is opaque multi-line text that must be indented
# under its marker (or, for the table, ruled). A `bound` leaf maps a text
# splice back by offset, and pre-indenting the render would shift every offset
# past the first line. So these seven render through a plain computed
# `TextString`: correct on the page and correct on save, but not
# splice-editable in the source view. Every other field stays `bound`.
#
# Every rule holds its styles as fields, and no theme: `RstToSyntax` fills them
# with `get_rst_style`, from a theme scaled or not, so with no theme a rule
# holds the plain values of the default theme and with a scaled theme it
# follows the appearance's scales (`RstTheme.jl`).
# The module binding itself, not only its names: the two macros below expand to
# `ProjectionModule.print_document(...)` definitions, and the unescaped name
# resolves in this module.


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
# `@projection_template` builds the printer from `(prj, doc)` alone, so the two macros
# below wrap `print_template_document` — the same entry point the template macro uses —
# and hand the builder the ambient as well. A rule keeps its template body; only its
# signature grows.

# The column the block this rule prints starts at.
_ambient(ctx) = something(get_property(ctx, :rst_indent, ""), "")

"""
    @rst_flat Projection DocumentType (prj, doc, indent) -> node

A rule whose children sit at its own column: a list and its items, a root and
its blocks. `indent` is that column, and the children inherit it.
"""
macro rst_flat(projname, intype, builder)
    builder = make_template_builder(builder)
    quote
        function ProjectionModule.print_document(p::$(esc(projname)), recursion, doc::$(esc(intype)), ctx)
            indent = $(_ambient)(ctx)
            $(print_template_document)(p, recursion, doc, ctx,
                                       (prj, d) -> $(esc(builder))(prj, d, indent))
        end
        function ProjectionModule.read_intent(p::$(esc(projname)), recursion, change::Intent, iomap)
            $(read_template_intent)(p, recursion, change, iomap)
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
    builder = make_template_builder(builder)
    quote
        function ProjectionModule.print_document(p::$(esc(projname)), recursion, doc::$(esc(intype)), ctx)
            outer = $(_ambient)(ctx)
            inner = outer * $(_IND)
            $(print_template_document)(p, recursion, doc,
                                       $(with_property)(ctx, :rst_indent, inner),
                                       (prj, d) -> $(esc(builder))(prj, d, outer, inner))
        end
        function ProjectionModule.read_intent(p::$(esc(projname)), recursion, change::Intent, iomap)
            $(read_template_intent)(p, recursion, change, iomap)
        end
    end
end

# ══════════════════════════════════════════════════════════════════════════════
# Source view (style = :source) — colourised raw RST
# ══════════════════════════════════════════════════════════════════════════════

# ── Inline leaves ─────────────────────────────────────────────────────────────

@projection UntrackedCell struct RstInsertionToSyntaxLeaf
    style::StyleText = get_rst_style(nothing, :marker_text)
end

@projection_template RstInsertionToSyntaxLeaf RstInsertion (prj, doc) ->
    SyntaxLeaf(TextString("insert rst here", prj.style))

@projection UntrackedCell struct RstTextToSyntaxLeaf
    style::StyleText = get_rst_style(nothing, :source_text)
end

@projection_template RstTextToSyntaxLeaf RstText (prj, doc) ->
    SyntaxLeaf(bound(:content, String,
                     make_hinted_text(() -> doc.content;
                                      empty_thunk = () -> isempty(doc.content),
                                      placeholder = "text",
                                      style = prj.style)))

@projection UntrackedCell struct RstLiteralToSyntaxLeaf
    value_style::StyleText = get_rst_style(nothing, :literal_text)
    tick_style::StyleText  = get_rst_style(nothing, :marker_text)
    tick::String = "``"
end

@projection_template RstLiteralToSyntaxLeaf RstLiteral (prj, doc) ->
    SyntaxLeaf(bound(:content, String,
                     make_hinted_text(() -> doc.content;
                                      empty_thunk = () -> isempty(doc.content),
                                      placeholder = "literal",
                                      style = prj.value_style));
               open=TextString(prj.tick, prj.tick_style),
               close=TextString(prj.tick, prj.tick_style))

@projection UntrackedCell struct RstEmphasisToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    marker::String = "*"
end

@projection_template RstEmphasisToSyntaxNode RstEmphasis (prj, doc) ->
    SyntaxNode(collection(:content);
               open=TextString(prj.marker, prj.marker_style),
               close=TextString(prj.marker, prj.marker_style))

@projection UntrackedCell struct RstStrongToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    marker::String = "**"
end

@projection_template RstStrongToSyntaxNode RstStrong (prj, doc) ->
    SyntaxNode(collection(:content);
               open=TextString(prj.marker, prj.marker_style),
               close=TextString(prj.marker, prj.marker_style))

# `:name:`content`` — the name and the content are separate editable spans, and
# the colons and backquotes are the chrome between them.
@projection UntrackedCell struct RstRoleToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    name_style::StyleText   = get_rst_style(nothing, :target_text)
    value_style::StyleText  = get_rst_style(nothing, :value_text)
    open_marker::String  = ":"
    mid_marker::String   = ":`"
    close_marker::String = "`"
end

@projection_template RstRoleToSyntaxNode RstRole (prj, doc) ->
    SyntaxConcatenation([ SyntaxLeaf(bound(:name, String,
                                           make_hinted_text(() -> doc.name;
                                                            empty_thunk = () -> isempty(doc.name),
                                                            placeholder = "role",
                                                            style = prj.name_style));
                                     open=TextString(prj.open_marker, prj.marker_style),
                                     close=TextString(prj.mid_marker, prj.marker_style)),
                          SyntaxLeaf(bound(:content, String,
                                           make_hinted_text(() -> doc.content;
                                                            empty_thunk = () -> isempty(doc.content),
                                                            placeholder = "value",
                                                            style = prj.value_style));
                                     close=TextString(prj.close_marker, prj.marker_style)) ])

# `` `text <target>`_ `` — the angled part disappears when the target is empty,
# which is the named-reference form `` `name`_ ``.
@projection UntrackedCell struct RstReferenceToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    text_style::StyleText   = get_rst_style(nothing, :reference_text)
    target_style::StyleText = get_rst_style(nothing, :target_text)
    show_markers::Bool = true
end

@projection_template RstReferenceToSyntaxNode RstReference (prj, doc) ->
    SyntaxConcatenation([ SyntaxLeaf(bound(:text, String,
                                           make_hinted_text(() -> doc.text;
                                                            empty_thunk = () -> isempty(doc.text),
                                                            placeholder = "link",
                                                            style = prj.text_style));
                                     open=TextString(prj.show_markers ? "`" : "", prj.marker_style)),
                          # With the markers off the target is not shown at all:
                          # the natural notation says where a link points by
                          # colouring its text, not by printing the URL beside it.
                          SyntaxLeaf(bound(:target, String,
                                           TextString(() -> prj.show_markers ? doc.target : "", prj.target_style));
                                     open=TextString(() -> !prj.show_markers || isempty(doc.target) ? "" : " <", prj.marker_style),
                                     close=TextString(() -> !prj.show_markers ? "" :
                                                            (isempty(doc.target) ? "" : ">") * "`" * (doc.anonymous ? "__" : "_"),
                                                     prj.marker_style)) ])

@projection UntrackedCell struct RstSubstitutionReferenceToSyntaxLeaf
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    style::StyleText        = get_rst_style(nothing, :substitution_text)
    marker::String = "|"
end

@projection_template RstSubstitutionReferenceToSyntaxLeaf RstSubstitutionReference (prj, doc) ->
    SyntaxLeaf(bound(:name, String,
                     make_hinted_text(() -> doc.name; empty_thunk = () -> isempty(doc.name),
                                      placeholder = "name",
                                      style = prj.style));
               open=TextString(prj.marker, prj.marker_style),
               close=TextString(prj.marker, prj.marker_style))

@projection UntrackedCell struct RstFootnoteReferenceToSyntaxLeaf
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    style::StyleText        = get_rst_style(nothing, :reference_text)
    open_marker::String  = "["
    close_marker::String = "]_"
end

@projection_template RstFootnoteReferenceToSyntaxLeaf RstFootnoteReference (prj, doc) ->
    SyntaxLeaf(bound(:label, String,
                     make_hinted_text(() -> doc.label; empty_thunk = () -> isempty(doc.label),
                                      placeholder = "n",
                                      style = prj.style));
               open=TextString(prj.open_marker, prj.marker_style),
               close=TextString(prj.close_marker, prj.marker_style))

# ── Blocks ────────────────────────────────────────────────────────────────────

@projection struct RstParagraphToSyntaxNode end

@projection_template RstParagraphToSyntaxNode RstParagraph (prj, doc) ->
    SyntaxNode(collection(:content); indentation=0)

@projection UntrackedCell struct RstLiteralBlockToSyntaxLeaf
    style::StyleText = get_rst_style(nothing, :literal_text)
end

# The block writes its own `::` marker on a line of its own. The parser takes
# the marker off the paragraph that introduced it — `text::` is stored as the
# paragraph `text:` plus this block — so emitting the body alone would leave an
# indented run with nothing to introduce it, and that re-reads as a block quote.
# A standalone `::` is the expanded form RST allows for exactly this.
@rst_indented RstLiteralBlockToSyntaxLeaf RstLiteralBlock (prj, doc, outer, inner) ->
    SyntaxLeaf(TextString(() -> "::\n\n" * _indent_body(doc.content, inner), prj.style);
               open=TextString("", prj.style))

@projection UntrackedCell struct RstLineBlockToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
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
@projection UntrackedCell struct RstListItemToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    sep::String = "\n\n   "
end

@rst_indented RstListItemToSyntaxNode RstListItem (prj, doc, outer, inner) ->
    SyntaxNode(collection(:elements);
               sep=TextString("\n\n" * inner, prj.marker_style),
               indentation=0)

# `-  item` — the marker plus two spaces, so a continuation line indents by the
# three spaces the item rule writes.
_bullet_marker(prj, doc) = (isempty(prj.marker) ? (isempty(doc.marker) ? "-" : doc.marker) *
                                                  "  " : prj.marker)

# `1. item`. Every item prints the list's own start number rather than a
# running one, because an item does not know its index. RST accepts that and
# renumbers on render, and a re-parse recovers the same list.
_enum_marker(doc) = (startswith(doc.style, "#") ? "#" : string(doc.start)) *
                    (isempty(doc.style) ? "." : doc.style[end:end]) * " "

@projection UntrackedCell struct RstBulletListToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    # Empty means "use the marker the source wrote". The rendered view sets a
    # bullet glyph instead, because the natural notation shows one bullet
    # whatever character the file happened to use.
    marker::String = ""
end

@rst_flat RstBulletListToSyntaxNode RstBulletList (prj, doc, indent) ->
    SyntaxNode(collection(:items);
               open=TextString(() -> _bullet_marker(prj, doc), prj.marker_style),
               sep=TextString(() -> "\n" * indent * _bullet_marker(prj, doc), prj.marker_style),
               indentation=0)

@projection UntrackedCell struct RstEnumeratedListToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
end

@rst_flat RstEnumeratedListToSyntaxNode RstEnumeratedList (prj, doc, indent) ->
    SyntaxNode(collection(:items);
               open=TextString(() -> _enum_marker(doc), prj.marker_style),
               sep=TextString(() -> "\n" * indent * _enum_marker(doc), prj.marker_style),
               indentation=0)

@projection UntrackedCell struct RstDefinitionItemToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
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

@projection UntrackedCell struct RstFieldToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    name_style::StyleText   = get_rst_style(nothing, :reference_text)
end

@rst_indented RstFieldToSyntaxNode RstField (prj, doc, outer, inner) ->
    SyntaxConcatenation([ SyntaxLeaf(bound(:name, String,
                                           make_hinted_text(() -> doc.name;
                                                            empty_thunk = () -> isempty(doc.name),
                                                            placeholder = "field",
                                                            style = prj.name_style));
                                     open=TextString(":", prj.marker_style),
                                     close=TextString(": ", prj.marker_style)),
                          SyntaxNode(collection(:elements); sep=TextString("\n" * inner, prj.marker_style), indentation=0) ])

@projection struct RstFieldListToSyntaxNode end

@rst_flat RstFieldListToSyntaxNode RstFieldList (prj, doc, indent) ->
    SyntaxNode(collection(:fields); sep=TextString("\n" * indent), indentation=0)

@projection UntrackedCell struct RstBlockQuoteToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
end

@rst_indented RstBlockQuoteToSyntaxNode RstBlockQuote (prj, doc, outer, inner) ->
    SyntaxNode(collection(:elements);
               open=TextString(_IND, prj.marker_style),
               sep=TextString("\n\n" * inner, prj.marker_style),
               close=TextString(() -> isempty(doc.attribution) ? "" :
                                      "\n\n" * inner * "-- " * doc.attribution,
                                prj.marker_style),
               indentation=0)

@projection UntrackedCell struct RstTransitionToSyntaxLeaf
    style::StyleText = get_rst_style(nothing, :marker_text)
    text::String = "----"
end

@projection_template RstTransitionToSyntaxLeaf RstTransition (prj, doc) ->
    SyntaxLeaf(TextString(prj.text, prj.style))

@projection UntrackedCell struct RstCommentToSyntaxLeaf
    style::StyleText  = get_rst_style(nothing, :marker_text)
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

@projection UntrackedCell struct RstTargetToSyntaxLeaf
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    style::StyleText        = get_rst_style(nothing, :target_text)
    open_marker::String  = ".. _"
    close_marker::String = ":"
end

@projection_template RstTargetToSyntaxLeaf RstTarget (prj, doc) ->
    SyntaxLeaf(bound(:name, String,
                     make_hinted_text(() -> doc.name; empty_thunk = () -> isempty(doc.name),
                                      placeholder = "name",
                                      style = prj.style));
               open=TextString(prj.open_marker, prj.marker_style),
               close=TextString(prj.close_marker, prj.marker_style))

@projection UntrackedCell struct RstSubstitutionDefinitionToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    name_style::StyleText   = get_rst_style(nothing, :substitution_text)
end

@rst_indented RstSubstitutionDefinitionToSyntaxNode RstSubstitutionDefinition (prj, doc, outer, inner) ->
    SyntaxConcatenation([ SyntaxLeaf(bound(:name, String,
                                           make_hinted_text(() -> doc.name;
                                                            empty_thunk = () -> isempty(doc.name),
                                                            placeholder = "name",
                                                            style = prj.name_style));
                                     open=TextString(".. |", prj.marker_style),
                                     close=TextString("| ", prj.marker_style)),
                          project(:body) ])

@projection UntrackedCell struct RstFootnoteToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    label_style::StyleText  = get_rst_style(nothing, :reference_text)
end

@rst_indented RstFootnoteToSyntaxNode RstFootnote (prj, doc, outer, inner) ->
    SyntaxConcatenation([ SyntaxLeaf(bound(:label, String,
                                           make_hinted_text(() -> doc.label;
                                                            empty_thunk = () -> isempty(doc.label),
                                                            placeholder = "n",
                                                            style = prj.label_style));
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

@projection UntrackedCell struct RstTableCellToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
end

@projection_template RstTableCellToSyntaxNode RstTableCell (prj, doc) ->
    SyntaxNode(collection(:elements); sep=TextString(" ", prj.marker_style), indentation=0)

@projection UntrackedCell struct RstTableRowToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
end

@projection_template RstTableRowToSyntaxNode RstTableRow (prj, doc) ->
    SyntaxNode(collection(:cells); sep=TextString(" | ", prj.marker_style), indentation=0)

@projection UntrackedCell struct RstGridTableToSyntaxNode
    style::StyleText = get_rst_style(nothing, :marker_text)
end

@rst_flat RstGridTableToSyntaxNode RstGridTable (prj, doc, indent) ->
    SyntaxLeaf(TextString(() -> _indent_body(_grid_table_text(doc), indent)[length(indent) + 1:end],
                          prj.style))

# ── Directives ────────────────────────────────────────────────────────────────

@projection UntrackedCell struct RstDirectiveOptionToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    name_style::StyleText   = get_rst_style(nothing, :reference_text)
    value_style::StyleText  = get_rst_style(nothing, :source_text)
end

@projection_template RstDirectiveOptionToSyntaxNode RstDirectiveOption (prj, doc) ->
    SyntaxConcatenation([ SyntaxLeaf(bound(:name, String,
                                           make_hinted_text(() -> doc.name;
                                                            empty_thunk = () -> isempty(doc.name),
                                                            placeholder = "option",
                                                            style = prj.name_style));
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

@projection UntrackedCell struct RstLiteralIncludeToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    path_style::StyleText   = get_rst_style(nothing, :target_text)
    value_style::StyleText  = get_rst_style(nothing, :source_text)
    header::String = ".. literalinclude:: "
end

@rst_indented RstLiteralIncludeToSyntaxNode RstLiteralInclude (prj, doc, outer, inner) ->
    SyntaxConcatenation([
        SyntaxLeaf(bound(:path, String,
                         make_hinted_text(() -> doc.path; empty_thunk = () -> isempty(doc.path),
                                          placeholder = "path",
                                          style = prj.path_style));
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

@projection UntrackedCell struct RstFigureToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    path_style::StyleText   = get_rst_style(nothing, :target_text)
    value_style::StyleText  = get_rst_style(nothing, :source_text)
    header::String = ".. figure:: "
end

@rst_indented RstFigureToSyntaxNode RstFigure (prj, doc, outer, inner) ->
    SyntaxConcatenation([
        SyntaxLeaf(bound(:path, String,
                         make_hinted_text(() -> doc.path; empty_thunk = () -> isempty(doc.path),
                                          placeholder = "path",
                                          style = prj.path_style));
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

@projection UntrackedCell struct RstCodeBlockToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    lang_style::StyleText   = get_rst_style(nothing, :directive_text)
    code_style::StyleText   = get_rst_style(nothing, :literal_text)
    header::String = ".. code-block:: "
    # The rendered view shows the code alone. The language names a colouring
    # rule, not something a reader of the page needs to see.
    show_language::Bool = true
end

@rst_indented RstCodeBlockToSyntaxNode RstCodeBlock (prj, doc, outer, inner) ->
    SyntaxConcatenation([
        SyntaxLeaf(bound(:language, String,
                         TextString(() -> prj.show_language ? doc.language : "", prj.lang_style));
                   open=TextString(prj.header, prj.marker_style)),
        SyntaxNode(collection(:extra);
                   open=TextString(() -> !prj.show_language || isempty(doc.extra) ? "" : "\n" * inner, prj.marker_style),
                   sep=TextString("\n" * inner, prj.marker_style), indentation=0),
        SyntaxLeaf(TextString(() -> isempty(doc.code) ? "" :
                                    (prj.show_language ? "\n\n" : "") * _indent_body(doc.code, inner),
                              prj.code_style)) ])

@projection UntrackedCell struct RstImageToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    path_style::StyleText   = get_rst_style(nothing, :target_text)
    value_style::StyleText  = get_rst_style(nothing, :source_text)
    header::String = ".. image:: "
end

@rst_indented RstImageToSyntaxNode RstImage (prj, doc, outer, inner) ->
    SyntaxConcatenation([
        SyntaxLeaf(bound(:path, String,
                         make_hinted_text(() -> doc.path; empty_thunk = () -> isempty(doc.path),
                                          placeholder = "path",
                                          style = prj.path_style));
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

@projection UntrackedCell struct RstVideoToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    path_style::StyleText   = get_rst_style(nothing, :target_text)
    value_style::StyleText  = get_rst_style(nothing, :source_text)
end

@rst_indented RstVideoToSyntaxNode RstVideo (prj, doc, outer, inner) ->
    SyntaxConcatenation([
        SyntaxLeaf(bound(:path, String,
                         make_hinted_text(() -> doc.path; empty_thunk = () -> isempty(doc.path),
                                          placeholder = "path",
                                          style = prj.path_style));
                   open=TextString(() -> ".. " * (doc.loop ? "video" : "video_noloop") * ":: ",
                                   prj.marker_style)),
        SyntaxLeaf(bound(:width, String, TextString(() -> doc.width, prj.value_style));
                   open=_option_open(prj, () -> doc.width, "width", inner)),
        SyntaxLeaf(bound(:height, String, TextString(() -> doc.height, prj.value_style));
                   open=_option_open(prj, () -> doc.height, "height", inner)),
        SyntaxNode(collection(:extra);
                   open=TextString(() -> isempty(doc.extra) ? "" : "\n" * inner, prj.marker_style),
                   sep=TextString("\n" * inner, prj.marker_style), indentation=0) ])

@projection UntrackedCell struct RstAudioToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    path_style::StyleText   = get_rst_style(nothing, :target_text)
    header::String = ".. audio:: "
end

@rst_indented RstAudioToSyntaxNode RstAudio (prj, doc, outer, inner) ->
    SyntaxConcatenation([
        SyntaxLeaf(bound(:path, String,
                         make_hinted_text(() -> doc.path; empty_thunk = () -> isempty(doc.path),
                                          placeholder = "path",
                                          style = prj.path_style));
                   open=TextString(prj.header, prj.marker_style)),
        SyntaxNode(collection(:extra);
                   open=TextString(() -> isempty(doc.extra) ? "" : "\n" * inner, prj.marker_style),
                   sep=TextString("\n" * inner, prj.marker_style), indentation=0) ])

@projection UntrackedCell struct RstAdmonitionToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :admonition_text)
    # With the marker off the kind is written as a word — `Note`, `Warning` —
    # which is what the box is labelled in the natural notation.
    show_marker::Bool = true
end

@rst_indented RstAdmonitionToSyntaxNode RstAdmonition (prj, doc, outer, inner) ->
    SyntaxNode(collection(:elements);
               open=TextString(() -> (prj.show_marker ? ".. " * doc.kind * "::" :
                                                        uppercasefirst(doc.kind)) * "\n\n" * inner,
                               prj.marker_style),
               sep=TextString("\n\n" * inner, prj.marker_style),
               indentation=0)

@projection UntrackedCell struct RstToctreeToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    entry_style::StyleText  = get_rst_style(nothing, :reference_text)
    # With the marker off the directive line and its options go, and a heading
    # word stands over the entries — a toctree *is* a table of contents, and
    # `:maxdepth:` is a build setting the reader has no use for.
    show_marker::Bool = true
    heading::String   = "Contents"
end

@rst_indented RstToctreeToSyntaxNode RstToctree (prj, doc, outer, inner) ->
    SyntaxConcatenation([
        SyntaxLeaf(TextString(() -> prj.show_marker ?
                                    ".. toctree::" *
                                    (doc.maxdepth == 0 ? "" : "\n" * inner * ":maxdepth: " * string(doc.maxdepth)) *
                                    (doc.titlesonly ? "\n" * inner * ":titlesonly:" : "") *
                                    (doc.glob ? "\n" * inner * ":glob:" : "") :
                                    prj.heading,
                              prj.marker_style)),
        SyntaxNode(collection(:extra);
                   open=TextString(() -> !prj.show_marker || isempty(doc.extra) ? "" : "\n" * inner, prj.marker_style),
                   sep=TextString("\n" * inner, prj.marker_style), indentation=0),
        SyntaxNode(collection(:entries);
                   open=TextString(() -> isempty(doc.entries) ? "" : "\n\n" * inner, prj.entry_style),
                   sep=TextString("\n" * inner, prj.entry_style), indentation=0) ])

@projection UntrackedCell struct RstMathBlockToSyntaxLeaf
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    style::StyleText        = get_rst_style(nothing, :value_text)
    show_marker::Bool = true
end

@rst_indented RstMathBlockToSyntaxLeaf RstMathBlock (prj, doc, outer, inner) ->
    SyntaxLeaf(TextString(() -> (prj.show_marker ? ".. math::\n\n" : "") * _indent_body(doc.content, inner),
                          prj.style))

@projection UntrackedCell struct RstRawBlockToSyntaxLeaf
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    style::StyleText        = get_rst_style(nothing, :marker_text)
end

@rst_indented RstRawBlockToSyntaxLeaf RstRawBlock (prj, doc, outer, inner) ->
    SyntaxLeaf(TextString(() -> ".. raw:: " * doc.format * "\n\n" * _indent_body(doc.content, inner),
                          prj.style))

@projection UntrackedCell struct RstRoleDefinitionToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    name_style::StyleText   = get_rst_style(nothing, :target_text)
end

@rst_indented RstRoleDefinitionToSyntaxNode RstRoleDefinition (prj, doc, outer, inner) ->
    SyntaxConcatenation([
        SyntaxLeaf(bound(:name, String,
                         make_hinted_text(() -> doc.name; empty_thunk = () -> isempty(doc.name),
                                          placeholder = "role",
                                          style = prj.name_style));
                   open=TextString(".. role:: ", prj.marker_style),
                   close=TextString(() -> isempty(doc.base) ? "" : "(" * doc.base * ")", prj.marker_style)),
        SyntaxNode(collection(:extra);
                   open=TextString(() -> isempty(doc.extra) ? "" : "\n" * inner, prj.marker_style),
                   sep=TextString("\n" * inner, prj.marker_style), indentation=0) ])

@projection UntrackedCell struct RstDirectiveToSyntaxNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
    name_style::StyleText   = get_rst_style(nothing, :directive_text)
    arg_style::StyleText    = get_rst_style(nothing, :source_text)
end

@rst_indented RstDirectiveToSyntaxNode RstDirective (prj, doc, outer, inner) ->
    SyntaxConcatenation([
        SyntaxLeaf(bound(:name, String,
                         make_hinted_text(() -> doc.name; empty_thunk = () -> isempty(doc.name),
                                          placeholder = "directive",
                                          style = prj.name_style));
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

@projection UntrackedCell struct RstSectionToSyntaxNode
    adornment_style::StyleText = get_rst_style(nothing, :reference_text)
    title_style::StyleText     = get_rst_style(nothing, :title_text)
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

@projection UntrackedCell struct RstRootToSyntaxNode
    style::StyleText = get_rst_style(nothing, :source_text)
end

@rst_flat RstRootToSyntaxNode RstRoot (prj, doc, indent) ->
    SyntaxNode(collection(:elements); sep=TextString("\n\n" * indent, prj.style), indentation=0)

# ══════════════════════════════════════════════════════════════════════════════
# Rendered view (style = :rendered) — the natural notation
# ══════════════════════════════════════════════════════════════════════════════
#
# Most of the natural notation is the source view with its markers turned off:
# a literal without its backquotes, a bullet as `•`, a code block without its
# `.. code-block::` line. Those are field values, so the rendered dispatch table
# below rebuilds the same rules with different fields and no rule is written
# twice.
#
# What needs its own rule is what *cascades*. Bold, italic and a section title
# change the font of every descendant text run, and a text leaf is what finally
# draws it. That travels as an ambient `:rst_style`, the way the indent travels
# as `:rst_indent` — a container augments it and delegates (School A), the leaf
# reads it.

# A role is drawn as a coloured chip with no `:name:` chrome. The colour groups
# the roles by what they name, so a reader tells a NED type from a C++ symbol
# from an ini parameter at a glance. An unknown role gets the neutral colour,
# because the role set is open. Each colour is the colour of the style field
# the projection holds for the theme role it names, so the chip follows the
# same theme as every other rule.
function _role_color(p, name::AbstractString)
    name in ("ned", "gate", "msg")  && return p.reference_style.color
    name in ("cpp", "var", "fun")   && return p.target_style.color
    name in ("par", "ini")          && return p.literal_style.color
    name in ("file", "download")    && return p.value_style.color
    name in ("doc", "ref")          && return p.directive_style.color
    name == "protocol"              && return p.substitution_style.color
    p.style.color
end

# ── RstStyledTextToSyntaxLeaf (rendered RstText; reads the ambient) ───────────
# Same output shape and reference mapping as the source text leaf; only the font
# differs, taken from the ambient `:rst_style` (or the theme's body default).

@projection UntrackedCell struct RstStyledTextToSyntaxLeaf
    style::StyleText = get_rst_style(nothing, :body_text)
end

function ProjectionModule.print_document(p::RstStyledTextToSyntaxLeaf, recursion, t::RstText, ctx)
    style = get_property(ctx, :rst_style, p.style)
    paths = make_output_path_cells(t, path -> map_reference_forward(p, nothing, path))
    SimpleIoMap(p, t, SyntaxLeaf(TextString(() -> t.content, style); paths...))
end

function map_reference_forward(p::RstStyledTextToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        proj(^(p), inner) => inner
        ::RstText.content.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
    end
end

function map_reference_backward(p::RstStyledTextToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        ∅ => EmptyReference(get_reference_node_type(iomap.input))
        ::SyntaxLeaf.value.rest... => @reference ::RstText.content::String.^(rest)
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::RstStyledTextToSyntaxLeaf, iomap, op::ReplaceStringRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    (new_ref === nothing || has_introduced_step(new_ref)) && return nothing
    ReplaceStringRangeOperation(new_ref, op.replacement)
end

function read_intent(p::RstStyledTextToSyntaxLeaf, iomap, op::ReplacePathOperation)
    path = map_reference_backward(p, iomap, op.path)
    path === nothing ? nothing : make_path_operation(op, path)
end

# ── RstStyledInline (rendered Strong / Emphasis) ──────────────────────────────
# A marker-free inline container that sets the ambient `:rst_style` and projects
# its `content` children through it. The output is a `SyntaxNode` of the
# projected children, so the reference mapping is the standard "delegate to
# child i".

# Neither is declared with `@projection`: each needs a different resolved theme
# value (a bold or an italic font), so each holds exactly the `Any` fields it
# needs — a value or a cell that `get_rst_style` returned — and reads it with
# `unwrap_cell`.
abstract type RstStyledInline <: Projection end

struct RstStrongToStyledNode <: RstStyledInline
    bold_font::Any
    body_text::Any
end
RstStrongToStyledNode(; theme = nothing) =
    RstStrongToStyledNode(get_rst_style(theme, :bold_font), get_rst_style(theme, :body_text))

struct RstEmphasisToStyledNode <: RstStyledInline
    italic_font::Any
    body_text::Any
end
RstEmphasisToStyledNode(; theme = nothing) =
    RstEmphasisToStyledNode(get_rst_style(theme, :italic_font), get_rst_style(theme, :body_text))

# Augment the ambient style with what this container's mode draws. There is no
# bold-italic face, so nesting keeps the innermost weight.
_mode_style(p::RstStrongToStyledNode, ambient::StyleText, doc) =
    StyleText(unwrap_cell(p.bold_font), ambient.color)
_mode_style(p::RstEmphasisToStyledNode, ambient::StyleText, doc) =
    StyleText(unwrap_cell(p.italic_font), ambient.color)

function ProjectionModule.print_document(p::RstStyledInline, recursion, doc, ctx)
    ambient = get_property(ctx, :rst_style, unwrap_cell(p.body_text))
    style = _mode_style(p, ambient, doc)
    child_iomaps = Cell(@computation([
        print_child(recursion, child,
            with_property(make_child_context(ctx, FieldReferenceStep("content"), ElementReferenceStep(i)),
                          :rst_style, style))
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

function map_reference_forward(p::RstStyledInline, iomap::ChildrenIoMap, reference)
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

for (T, D) in ((:RstStrongToStyledNode, :RstStrong), (:RstEmphasisToStyledNode, :RstEmphasis))
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

# ── RstRoleToStyledLeaf (rendered role; a coloured chip) ─────────────────────
# The `:name:` chrome disappears and the colour carries what the name said. The
# font and the colour are computed cells, so a role that is renamed recolours
# without a re-print.

@projection UntrackedCell struct RstRoleToStyledLeaf
    style::StyleText               = get_rst_style(nothing, :marker_text)
    reference_style::StyleText     = get_rst_style(nothing, :reference_text)
    target_style::StyleText        = get_rst_style(nothing, :target_text)
    literal_style::StyleText       = get_rst_style(nothing, :literal_text)
    value_style::StyleText         = get_rst_style(nothing, :value_text)
    directive_style::StyleText     = get_rst_style(nothing, :directive_text)
    substitution_style::StyleText  = get_rst_style(nothing, :substitution_text)
end

@rst_flat RstRoleToStyledLeaf RstRole (prj, doc, indent) ->
    SyntaxLeaf(bound(:content, String,
                     TextString(Cell(@computation doc.content),
                                Cell(@computation prj.style.font),
                                Cell(@computation _role_color(prj, doc.name)),
                                Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))))

# The font of a section title at `level` (1-based; every level past the third
# takes `title_font`), read from the projection's own field for that level.
_get_title_font(p, level::Int) =
    unwrap_cell(level <= 1 ? p.title_1_font :
                level == 2 ? p.title_2_font :
                level == 3 ? p.title_3_font : p.title_font)

# ── RstSectionToStyledNode (rendered section; a large title, no adornment) ────
# The title children are projected under a heading ambient and the body children
# under the body ambient, so one rule sets two different styles — which is why
# it is written out rather than templated.

@projection UntrackedCell struct RstSectionToStyledNode
    style::StyleText        = get_rst_style(nothing, :body_text)
    title_1_font::StyleFont = get_rst_style(nothing, :title_1_font)
    title_2_font::StyleFont = get_rst_style(nothing, :title_2_font)
    title_3_font::StyleFont = get_rst_style(nothing, :title_3_font)
    title_font::StyleFont   = get_rst_style(nothing, :title_font)
    title_color::StyleColor = get_rst_style(nothing, :title_color)
end

function ProjectionModule.print_document(p::RstSectionToStyledNode, recursion, doc::RstSection, ctx)
    indent = _ambient(ctx)
    title_style = StyleText(_get_title_font(p, doc.level), unwrap_cell(p.title_color))
    child_iomaps = Cell(@computation begin
        maps = Any[]
        for (i, child) in enumerate(doc.title)
            push!(maps, print_child(recursion, child,
                with_property(make_child_context(ctx, FieldReferenceStep("title"), ElementReferenceStep(i)),
                              :rst_style, title_style)))
        end
        for (i, child) in enumerate(doc.elements)
            push!(maps, print_child(recursion, child,
                make_child_context(ctx, FieldReferenceStep("elements"), ElementReferenceStep(i))))
        end
        maps
    end)
    title_count = Cell(@computation length(doc.title))
    items = CellVector(@computation begin
        maps = child_iomaps[]
        n = title_count[]
        # A title child concatenates into the title line; every body block
        # opens with the blank line that separates it from what came before.
        SyntaxDocument[
            k <= n ? maps[k].output :
                     SyntaxNode(SyntaxDocument[maps[k].output];
                                open=TextString("\n\n" * indent, p.style))
            for k in eachindex(maps)]
    end)
    node = SyntaxNode(items; sep=TextString(() -> "", p.style), indentation=0)
    ChildrenIoMap(p, doc, node, child_iomaps)
end

# ── RstEnumeratedListToStyledNode (rendered; the numbers actually count) ─────
# The source view prints the list's own start number on every item, because a
# templated item cannot know its index and RST renumbers on render anyway. The
# natural notation *is* the render, so the number has to be right — which means
# building the items here, where the index is in hand.

@projection UntrackedCell struct RstEnumeratedListToStyledNode
    marker_style::StyleText = get_rst_style(nothing, :marker_text)
end

function ProjectionModule.print_document(p::RstEnumeratedListToStyledNode, recursion, doc::RstEnumeratedList, ctx)
    indent = _ambient(ctx)
    child_iomaps = Cell(@computation([
        print_child(recursion, item,
                    make_child_context(ctx, FieldReferenceStep("items"), ElementReferenceStep(i)))
        for (i, item) in enumerate(doc.items)]))
    items = CellVector(@computation begin
        maps = child_iomaps[]
        first_number = doc.start
        SyntaxDocument[
            SyntaxDelimitation(maps[k].output;
                               opening_delimiter=TextString((k == 1 ? "" : "\n" * indent) *
                                                            string(first_number + k - 1) * ". ",
                                                            p.marker_style))
            for k in eachindex(maps)]
    end)
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

# Each item sits inside the `SyntaxDelimitation` that carries its number, so
# the tail hops through `.content` on the way in and out — the same hop
# `YamlSequenceToBlockSyntaxNode` makes for its `- ` marker.
function map_reference_forward(p::RstEnumeratedListToStyledNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
        items{s:e}.rest... => begin
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

function map_reference_backward(p::RstEnumeratedListToStyledNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::RstEnumeratedList
        ::SyntaxNode.children{s:e}.content.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps
            1 <= child_i <= length(iomaps) || return make_introduced_reference(p, iomap, reference)
            child = iomaps[child_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::RstEnumeratedList.items::CellVector[child_i].^(inner)
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::RstEnumeratedListToStyledNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing && return nothing
    make_path_operation(op, result)
end

function read_intent(p::RstEnumeratedListToStyledNode, iomap::ChildrenIoMap, op::ReplaceStringRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    (new_ref === nothing || has_introduced_step(new_ref)) && return nothing
    ReplaceStringRangeOperation(new_ref, op.replacement)
end

# ── The picture ───────────────────────────────────────────────────────────────
# A figure and an image draw the file `path` names, decoded lazily and capped in
# width; a path that is not on disk falls back to the path as text. Modelled on
# the markdown rendered image.

function _rst_picture(path, placeholder::StyleText; max_w::Int = 640)
    if path isa AbstractString && !isempty(path) && isfile(String(path))
        file = String(path)
        image = ImageFile(file)
        raw = getfield(image, :raw)
        set_cell_computation!(raw, () -> (try decode_image(file) catch; nothing end))
        natural(i, fallback) = (r = raw[]; (r isa Tuple && length(r) == 3) ? Int(r[i]) : fallback)
        width  = Cell(@computation Int32(min(natural(2, 720), max_w)))
        height = Cell(@computation begin
            w = min(natural(2, 720), max_w)
            Int32(round(Int, natural(3, 460) * w / natural(2, 720)))
        end)
        return TextGraphics(Cell(image), width, height, Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    end
    TextString(isempty(String(path)) ? "image" : String(path), placeholder)
end

@projection UntrackedCell struct RstFigureToStyledNode
    caption_style::StyleText = get_rst_style(nothing, :caption_text)
    placeholder::StyleText   = get_rst_style(nothing, :marker_text)
end

@rst_flat RstFigureToStyledNode RstFigure (prj, doc, indent) ->
    SyntaxConcatenation([
        SyntaxLeaf(_rst_picture(doc.path, prj.placeholder)),
        SyntaxNode(collection(:caption);
                   open=TextString(() -> isempty(doc.caption) ? "" : "\n" * indent, prj.caption_style),
                   sep=TextString("\n" * indent, prj.caption_style),
                   indentation=0) ])

# ── RstLiteralIncludeToStyledLeaf (rendered; one line, not option syntax) ────
# The source view lists the slice bounds as `:start-at:` / `:end-at:` lines,
# which is the file's own spelling. The natural notation says the same thing in
# one line: where the text comes from, in what language, between which marks.
#
# The arrow takes the theme's `rendered_marker_text`, which is DejaVu: Ubuntu
# Mono lacks this glyph, and a DejaVu marker stays legible without depending on
# the per-glyph fallback `source/backend/sdl/Sdl.jl` otherwise applies.

@projection UntrackedCell struct RstLiteralIncludeToStyledLeaf
    marker_style::StyleText = get_rst_style(nothing, :rendered_marker_text)
    path_style::StyleText   = get_rst_style(nothing, :target_text)
    detail_style::StyleText = get_rst_style(nothing, :marker_text)
    marker::String = "\u21b3 "
end

# The bounds, as the reader would say them: from what, to what.
function _include_detail(doc)
    parts = String[]
    isempty(doc.language) || push!(parts, doc.language)
    from = isempty(doc.start_at) ? doc.start_after : doc.start_at
    to   = isempty(doc.end_at) ? doc.end_before : doc.end_at
    isempty(from) && isempty(to) && return isempty(parts) ? "" : "  (" * join(parts, ", ") * ")"
    push!(parts, (isempty(from) ? "start" : from) * " \u2026 " * (isempty(to) ? "end" : to))
    "  (" * join(parts, ", ") * ")"
end

@rst_flat RstLiteralIncludeToStyledLeaf RstLiteralInclude (prj, doc, indent) ->
    SyntaxConcatenation([
        SyntaxLeaf(bound(:path, String,
                         make_hinted_text(() -> doc.path; empty_thunk = () -> isempty(doc.path),
                                          placeholder = "path",
                                          style = prj.path_style));
                   open=TextString(prj.marker, prj.marker_style)),
        SyntaxLeaf(TextString(() -> _include_detail(doc), prj.detail_style)) ])

@projection UntrackedCell struct RstImageToStyledNode
    placeholder::StyleText = get_rst_style(nothing, :marker_text)
end

@rst_flat RstImageToStyledNode RstImage (prj, doc, indent) ->
    SyntaxLeaf(_rst_picture(doc.path, prj.placeholder))

# ══════════════════════════════════════════════════════════════════════════════
# Dispatcher
# ══════════════════════════════════════════════════════════════════════════════

# The source dispatch table. The rendered style is built from it by replacing
# the rules whose presentation differs, so a rule that reads the same either way
# is written once.
"""
The directive name that tags a block as a cross-file marker:

    .. pred-ref:: <<file("path")>>

It lives here rather than next to the loader because both the reader of a
marker (the loader) and its writer (this projection) need the one name.
"""
const PRED_REF_DIRECTIVE = "pred-ref"

# The style of every role this dispatch table draws with, read once from
# `theme`; `media_styles` is the triplet a directive with a path and a value
# shares — a literal include, a figure, an image and a video.
function _source_rules(theme)
    get_style(name) = get_rst_style(theme, name)
    marker       = get_style(:marker_text)
    source       = get_style(:source_text)
    literal      = get_style(:literal_text)
    target       = get_style(:target_text)
    value        = get_style(:value_text)
    reference    = get_style(:reference_text)
    substitution = get_style(:substitution_text)
    directive    = get_style(:directive_text)
    media_styles = (marker_style = marker, path_style = target, value_style = source)
    Pair{Any,Any}[
        RstInsertion               => RstInsertionToSyntaxLeaf(; style = marker),
        RstText                    => RstTextToSyntaxLeaf(; style = source),
        RstLiteral                 => RstLiteralToSyntaxLeaf(; value_style = literal, tick_style = marker),
        RstEmphasis                => RstEmphasisToSyntaxNode(; marker_style = marker),
        RstStrong                  => RstStrongToSyntaxNode(; marker_style = marker),
        RstRole                    => RstRoleToSyntaxNode(; marker_style = marker, name_style = target, value_style = value),
        RstReference               => RstReferenceToSyntaxNode(; marker_style = marker, text_style = reference, target_style = target),
        RstSubstitutionReference   => RstSubstitutionReferenceToSyntaxLeaf(; marker_style = marker, style = substitution),
        RstFootnoteReference       => RstFootnoteReferenceToSyntaxLeaf(; marker_style = marker, style = reference),
        RstParagraph               => RstParagraphToSyntaxNode(),
        RstLiteralBlock            => RstLiteralBlockToSyntaxLeaf(; style = literal),
        RstLineBlock               => RstLineBlockToSyntaxNode(; marker_style = marker),
        RstListItem                => RstListItemToSyntaxNode(; marker_style = marker),
        RstBulletList              => RstBulletListToSyntaxNode(; marker_style = marker),
        RstEnumeratedList          => RstEnumeratedListToSyntaxNode(; marker_style = marker),
        RstDefinitionItem          => RstDefinitionItemToSyntaxNode(; marker_style = marker),
        RstDefinitionList          => RstDefinitionListToSyntaxNode(),
        RstField                   => RstFieldToSyntaxNode(; marker_style = marker, name_style = reference),
        RstFieldList               => RstFieldListToSyntaxNode(),
        RstBlockQuote              => RstBlockQuoteToSyntaxNode(; marker_style = marker),
        RstTransition              => RstTransitionToSyntaxLeaf(; style = marker),
        RstComment                 => RstCommentToSyntaxLeaf(; style = marker),
        RstTarget                  => RstTargetToSyntaxLeaf(; marker_style = marker, style = target),
        RstSubstitutionDefinition  => RstSubstitutionDefinitionToSyntaxNode(; marker_style = marker, name_style = substitution),
        RstFootnote                => RstFootnoteToSyntaxNode(; marker_style = marker, label_style = reference),
        RstTableCell               => RstTableCellToSyntaxNode(; marker_style = marker),
        RstTableRow                => RstTableRowToSyntaxNode(; marker_style = marker),
        RstGridTable               => RstGridTableToSyntaxNode(; style = marker),
        RstDirectiveOption         => RstDirectiveOptionToSyntaxNode(; marker_style = marker, name_style = reference, value_style = source),
        RstLiteralInclude          => RstLiteralIncludeToSyntaxNode(; media_styles...),
        RstFigure                  => RstFigureToSyntaxNode(; media_styles...),
        RstCodeBlock               => RstCodeBlockToSyntaxNode(; marker_style = marker, lang_style = directive, code_style = literal),
        RstImage                   => RstImageToSyntaxNode(; media_styles...),
        RstVideo                   => RstVideoToSyntaxNode(; media_styles...),
        RstAudio                   => RstAudioToSyntaxNode(; marker_style = marker, path_style = target),
        RstAdmonition              => RstAdmonitionToSyntaxNode(; marker_style = get_style(:admonition_text)),
        RstToctree                 => RstToctreeToSyntaxNode(; marker_style = marker, entry_style = reference),
        RstMathBlock               => RstMathBlockToSyntaxLeaf(; marker_style = marker, style = value),
        RstRawBlock                => RstRawBlockToSyntaxLeaf(; marker_style = marker, style = marker),
        RstRoleDefinition          => RstRoleDefinitionToSyntaxNode(; marker_style = marker, name_style = target),
        RstDirective               => RstDirectiveToSyntaxNode(; marker_style = marker, name_style = directive, arg_style = source),
        RstSection                 => RstSectionToSyntaxNode(; adornment_style = reference, title_style = get_style(:title_text)),
        RstRoot                    => RstRootToSyntaxNode(; style = source),
        Vector{Cell}               => CopyingProjection(),
    ]
end

"""
    RstToSyntax(; style::Symbol = :source, theme = nothing)

Build the RST → Syntax projection. `style` is `:source` (colourised raw RST,
fully editable including the markers) or `:rendered` (the natural notation,
marker-free — see the module docstring). `theme` is an `RstTheme`, a scaled
one, or `nothing` for the default styles; it gives each rule the style of its
role with `get_rst_style`, and no rule holds `theme` itself.
"""
function RstToSyntax(; style::Symbol = :source, theme = nothing)
    style in (:source, :rendered) || error("RstToSyntax: style must be :source or :rendered, got :$style")
    rules = _source_rules(theme)
    style === :source && return TypeDispatchingProjection(rules...)

    get_style(name) = get_rst_style(theme, name)
    marker          = get_style(:marker_text)
    rendered_marker = get_style(:rendered_marker_text)
    body            = get_style(:body_text)
    literal         = get_style(:literal_text)
    target          = get_style(:target_text)
    value           = get_style(:value_text)
    reference       = get_style(:reference_text)
    directive       = get_style(:directive_text)
    title_styles    = (title_1_font = get_style(:title_1_font), title_2_font = get_style(:title_2_font),
                       title_3_font = get_style(:title_3_font), title_font = get_style(:title_font),
                       title_color = get_style(:title_color))
    role_styles     = (reference_style = reference, target_style = target, literal_style = literal,
                       value_style = value, directive_style = directive,
                       substitution_style = get_style(:substitution_text))
    # Every override either swaps in a cascading rule or turns a marker off by
    # giving the same rule a different field value.
    overrides = Dict{Any,Any}(
        RstText        => RstStyledTextToSyntaxLeaf(; style = body),
        RstStrong      => RstStrongToStyledNode(; theme),
        RstEmphasis    => RstEmphasisToStyledNode(; theme),
        RstRole        => RstRoleToStyledLeaf(; style = marker, role_styles...),
        RstSection     => RstSectionToStyledNode(; style = body, title_styles...),
        RstFigure      => RstFigureToStyledNode(; caption_style = get_style(:caption_text), placeholder = marker),
        RstImage       => RstImageToStyledNode(; placeholder = marker),
        # The backquotes go, the monospace stays.
        RstLiteral     => RstLiteralToSyntaxLeaf(; value_style = literal, tick_style = marker, tick=""),
        # A rule with no markers left to draw.
        RstReference   => RstReferenceToSyntaxNode(; marker_style = marker, text_style = reference,
                                                     target_style = target, show_markers=false),
        RstTransition  => RstTransitionToSyntaxLeaf(; text="────────────", style=rendered_marker),
        RstBulletList  => RstBulletListToSyntaxNode(; marker_style = marker, marker="•  "),
        RstCodeBlock   => RstCodeBlockToSyntaxNode(; marker_style = marker, lang_style = directive,
                                                     code_style = literal, header="", show_language=false),
        RstEnumeratedList => RstEnumeratedListToStyledNode(; marker_style = marker),
        RstAdmonition  => RstAdmonitionToSyntaxNode(; marker_style = get_style(:admonition_text), show_marker=false),
        RstToctree     => RstToctreeToSyntaxNode(; marker_style = marker, entry_style = reference, show_marker=false),
        RstLineBlock   => RstLineBlockToSyntaxNode(; marker_style = marker, open_marker=""),
        RstLiteralInclude => RstLiteralIncludeToStyledLeaf(; marker_style = rendered_marker, path_style = target,
                                                             detail_style = marker),
        RstAudio       => RstAudioToSyntaxNode(; marker_style = marker, path_style = target, header=""),
        RstMathBlock   => RstMathBlockToSyntaxLeaf(; marker_style = marker, style = value, show_marker=false),
        # A comment and a target are build-time chrome: the natural notation
        # shows the comment dimmed without its marker, and nothing for a target.
        RstComment     => RstCommentToSyntaxLeaf(; style = marker, show_marker=false),
        RstTarget      => RstTargetToSyntaxLeaf(; marker_style = marker, style = target, open_marker="", close_marker=""),
    )
    TypeDispatchingProjection((k => get(overrides, k, v) for (k, v) in rules)...)
end

# ── Natural-projection registration ─────────────────────────────────────────
# The row that teaches the render-anything projection what this domain is. The
# factory form, so every renderer builds its own projection instance.
