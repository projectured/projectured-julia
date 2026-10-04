# Fragment of `XmlModule`.
#
# XML → SyntaxDocument projection, written with `@projection_template` (like
# `JsonToSyntax` / `JuliaToSyntax`). Each XML type is a builder that constructs the
# real Syntax output with `bound(…)` / `collection(…)` markers at the positions that
# need special wiring; the template engine (`ProjectionTemplate.jl`) records the
# wiring, strips the markers, and supplies reference mapping and the recursive reader
# generically. The authoring command set lives on the XML document types as
# `@gestures` (see `XmlDocument.jl`); the template's reader delegates a raw gesture
# to `read_gesture`.
#
# The output node shape is:
#
#     SyntaxConcatenation([                                ← element node
#       SyntaxLeaf(open="<", close=" "|"", bound(:tag)),   ← tag-name leaf
#       SyntaxNode(close=">", sep=" ", collection(:attrs) do a  ← attributes node
#         SyntaxNode(sep="=", [                            ← each attribute
#           SyntaxLeaf(bound(:name)),
#           SyntaxLeaf(open='"', close='"', bound(:value)),
#         ]) end),
#       SyntaxNode(collection(:children); indentation=1),  ← recursive child body
#       SyntaxLeaf(open="</", close=">", value=tag),        ← closing-tag leaf (display-only)
#     ])
#
# Internal nodes have no open delimiter, so SyntaxToText renders them inline. The space
# between the tag name and the first attribute is a reactive `close` on the tag leaf:
# `" "` when attributes are present, `""` otherwise. The closing tag renders the same
# `.tag` field (updated reactively) but is projection-introduced structure (no
# `bound`), so it carries no cursor and maps nothing back.
# ── XmlTextToSyntaxLeaf ─────────────────────────────────────────────────────
#
# A bound leaf: `.content{k}` edits map to the leaf's own `.value{k}` span.

@projection UntrackedCell struct XmlTextToSyntaxLeaf
    style::StyleText = get_xml_style(nothing, :content_text)
end

# The text is entity-escaped on the way out, as an attribute value already is,
# and the parser unescapes it on the way in: a `<` in a text node round-trips.
@projection_template XmlTextToSyntaxLeaf XmlText (p, t) ->
    SyntaxLeaf(bound(:content, String, TextString(() -> _xml_text_escape(t.content), p.style)))

# ── XmlInsertionToSyntaxLeaf ────────────────────────────────────────────────
#
# The shared typed-name insertion buffer, constrained to the XML candidates
# (prefix-free: `element` → `XmlElement`, `text` → `XmlText`). The `<`/`"`
# type-to-replace gestures on a whole-selected insertion keep working: the
# leaf's char editing declines without a value cursor, so those keys fall
# through to `@gestures XmlDocument` (declared in `XmlDocument.jl`).

XmlInsertionToSyntaxLeaf(; theme = nothing) = DomainInsertionToSyntaxLeaf(XmlDocument; theme)

# ── XmlAttributeToSyntaxNode ────────────────────────────────────────────────
#
# A fixed 2-leaf `name="value"` node, both leaves bound. An attribute is a
# document in its own right, so it projects on its own rather than being built
# inline by the element that happens to hold it.

@projection UntrackedCell struct XmlAttributeToSyntaxNode
    delim::StyleText       = get_xml_style(nothing, :delimiter_text)
    attr_name::StyleText   = get_xml_style(nothing, :attribute_name_text)
    quote_style::StyleText = get_xml_style(nothing, :quote_text)
    attr_value::StyleText  = get_xml_style(nothing, :attribute_value_text)
end

@projection_template XmlAttributeToSyntaxNode XmlAttribute (p, a) ->
    SyntaxNode(TextString("", p.delim), TextString("", p.delim), TextString("=", p.delim),
        [ SyntaxLeaf(bound(:name, String, TextString(() -> a.name, p.attr_name))),
          SyntaxLeaf(bound(:value, String, TextString(() -> xml_escape_attr(a.value), p.attr_value));
                     open=TextString("\"", p.quote_style),
                     close=TextString("\"", p.quote_style)) ],
        0, false, nothing)

# ── XmlElementToSyntaxNode ──────────────────────────────────────────────────

@projection UntrackedCell struct XmlElementToSyntaxNode
    tag::StyleText   = get_xml_style(nothing, :tag_text)
    delim::StyleText = get_xml_style(nothing, :delimiter_text)
end

# Fixed-children node `[tag, attrs, body, close]`. The tag leaf is `bound(:tag)`;
# the attrs and body nodes are nested sub-nodes (F1) each keying off one element
# field (`:attrs` / `:children`), whose elements project through the composite; the
# close leaf is projection-introduced (renders the shared `.tag`, no cursor).
@projection_template XmlElementToSyntaxNode XmlElement (p, e) -> begin
    tag_leaf = SyntaxLeaf(bound(:tag, String, TextString(() -> e.tag, p.tag));
                          open=TextString("<", p.delim),
                          close=TextString(() -> isempty(e.attrs) ? "" : " ", p.delim))

    attrs_node = SyntaxNode(collection(:attrs);
                            close=TextString(">", p.delim),
                            sep=TextString(" ", p.delim.font))

    body_node = SyntaxNode(collection(:children); indentation=1)

    close_leaf = SyntaxLeaf(TextString(() -> e.tag, p.tag);
                            open=TextString("</", p.delim),
                            close=TextString(">", p.delim))

    SyntaxConcatenation([ tag_leaf, attrs_node, body_node, close_leaf ])
end

# ── XmlToSyntax (composite) ─────────────────────────────────────────────────

# The projection of the whole domain: one rule per document type. The builder
# gives each projection its styles from `theme`, an `XmlTheme` scaled or not, or
# the default styles for `nothing`; `syntax_theme` styles the insertion and the
# empty placeholder, which are the syntax slice's.

function XmlToSyntax(; theme = nothing, syntax_theme = nothing)
    get_style(name) = get_xml_style(theme, name)
    TypeDispatchingProjection(
        XmlText      => XmlTextToSyntaxLeaf(; style = get_style(:content_text)),
        XmlAttribute => XmlAttributeToSyntaxNode(; delim = get_style(:delimiter_text),
                                                   attr_name = get_style(:attribute_name_text),
                                                   quote_style = get_style(:quote_text),
                                                   attr_value = get_style(:attribute_value_text)),
        XmlElement   => XmlElementToSyntaxNode(; tag = get_style(:tag_text),
                                                  delim = get_style(:delimiter_text)),
        XmlInsertion => XmlInsertionToSyntaxLeaf(; theme = syntax_theme),
        XmlNothing   => InsertionNothingToSyntaxLeaf(; theme = syntax_theme),
    )
end

function _xml_text_escape(s::AbstractString)
    buf = IOBuffer()
    for ch in s
        ch == '&' ? write(buf, "&amp;") :
        ch == '<' ? write(buf, "&lt;")  :
        ch == '>' ? write(buf, "&gt;")  :
                    write(buf, ch)
    end
    String(take!(buf))
end

# ── Utility ─────────────────────────────────────────────────────────────────

function xml_escape_attr(s::AbstractString)
    buf = IOBuffer()
    for ch in s
        if ch == '&'      write(buf, "&amp;")
        elseif ch == '<'  write(buf, "&lt;")
        elseif ch == '"'  write(buf, "&quot;")
        else              write(buf, ch)
        end
    end
    String(take!(buf))
end

# ── Natural-format registration ─────────────────────────────────────────────
# XML's seams for import_document / export_document / read+write_document_file.
make_document_seed(::Val{:xml}) = XmlInsertion()

# ── What this domain's natural notation is ──────────────────────────────────
# One statement: the rung it starts at and how to build it, the format it is
# written in, the extension that names the format back, and how to read that text
# in again. Runtime state, so `__init__` rather than a top-level call.
