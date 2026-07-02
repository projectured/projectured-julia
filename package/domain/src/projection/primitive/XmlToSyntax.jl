"""
    XmlToSyntaxModule

XML → SyntaxDocument projection, written with `@projection_template` (like
`JsonToSyntax` / `JuliaToSyntax`). Each XML type is a builder that constructs the
real Syntax output with `bound(…)` / `collection(…)` markers at the positions that
need special wiring; the template engine (`ProjectionTemplate.jl`) records the
wiring, strips the markers, and supplies reference mapping and the recursive reader
generically. The authoring command set lives on the XML document types as
`@gestures` (see `document/Xml.jl`); the template's reader delegates a raw gesture
to `document_read`.

The output node shape is unchanged:

    SyntaxNode("", "", "", [                             ← element node
      SyntaxLeaf(open="<", close=" "|"", bound(:tag)),   ← tag-name leaf
      SyntaxNode(close=">", sep=" ", collection(:attrs) do a  ← attributes node
        SyntaxNode(sep="=", [                            ← each attribute
          SyntaxLeaf(bound(:name)),
          SyntaxLeaf(open='"', close='"', bound(:value)),
        ]) end),
      SyntaxNode(collection(:children); indentation=1),  ← recursive child body
      SyntaxLeaf(open="</", close=">", value=tag),        ← closing-tag leaf (display-only)
    ])

All internal nodes have open="" so SyntaxToText renders them inline. The space
between the tag name and the first attribute is a reactive `close` on the tag leaf:
`" "` when attributes are present, `""` otherwise. The closing tag renders the same
`.tag` field (updated reactively) but is projection-introduced structure (no
`bound`), so it carries no cursor and maps nothing back.
"""
module XmlToSyntaxModule

import ..ReactiveModule: Cell
import ..ProjectionApiModule: projection_print, Projection
import ..ProjectionModule: var"@projection"
import ..XmlModule: XmlInsertion, XmlText, XmlAttribute, XmlElement
import ..TextModule: TextString
import ..FontModule: font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20
import ..ColorModule: color_black, color_default, color_solarized_blue, color_solarized_green,
                      color_solarized_cyan, color_solarized_yellow, color_solarized_gray
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..ProjectionTemplateModule: var"@projection_template", bound, collection
export XmlInsertionToSyntaxLeaf, XmlTextToSyntaxLeaf, XmlElementToSyntaxNode, XmlToSyntax

# ── XmlTextToSyntaxLeaf ─────────────────────────────────────────────────────
#
# A bound leaf: `.content{k}` edits map to the leaf's own `.value{k}` span.

@projection struct XmlTextToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_black)
end

@projection_template XmlTextToSyntaxLeaf XmlText (p, t) ->
    SyntaxLeaf(bound(:content, String, TextString(() -> t.content, p.style)))

# ── XmlInsertionToSyntaxLeaf ────────────────────────────────────────────────
#
# An opaque placeholder leaf (no `bound`): maps `∅↔∅` only. Its `<`/`"` replace
# gestures are declared on `XmlInsertion` in `document/Xml.jl`.

@projection struct XmlInsertionToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template XmlInsertionToSyntaxLeaf XmlInsertion (p, x) ->
    SyntaxLeaf(TextString("insert XML here", p.style))

# ── XmlElementToSyntaxNode ──────────────────────────────────────────────────

@projection struct XmlElementToSyntaxNode
    tag::StyleText         = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    delim::StyleText       = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    attr_name::StyleText   = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    quote_style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    attr_value::StyleText  = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

# Fixed-children node `[tag, attrs, body, close]`. The tag leaf is `bound(:tag)`;
# the attrs and body nodes are nested sub-nodes (F1) each keying off one element
# field (`:attrs` / `:children`); the close leaf is projection-introduced (renders
# the shared `.tag`, no cursor). Each attribute builds a fixed 2-leaf `name="value"`
# node with both leaves bound.
@projection_template XmlElementToSyntaxNode XmlElement (p, e) -> begin
    tag_leaf = SyntaxLeaf(bound(:tag, String, TextString(() -> e.tag, p.tag));
                          open=TextString("<", p.delim),
                          close=TextString(() -> isempty(e.attrs) ? "" : " ", p.delim))

    attrs_node = SyntaxNode(collection(:attrs) do a
                                SyntaxNode(TextString("", p.delim), TextString("", p.delim), TextString("=", p.delim),
                                    [ SyntaxLeaf(bound(:name, String, TextString(() -> a.name, p.attr_name))),
                                      SyntaxLeaf(bound(:value, String, TextString(() -> xml_escape_attr(a.value), p.attr_value));
                                                 open=TextString("\"", p.quote_style),
                                                 close=TextString("\"", p.quote_style)) ],
                                    0, false, nothing)
                            end;
                            close=TextString(">", p.delim),
                            sep=TextString(" ", p.delim.font, color_default))

    body_node = SyntaxNode(collection(:children); indentation=1)

    close_leaf = SyntaxLeaf(TextString(() -> e.tag, p.tag);
                            open=TextString("</", p.delim),
                            close=TextString(">", p.delim))

    SyntaxNode(TextString(""), TextString(""), TextString(""),
               [ tag_leaf, attrs_node, body_node, close_leaf ],
               0, false, nothing)
end

# ── XmlToSyntax (composite) ─────────────────────────────────────────────────

function XmlToSyntax()
    TypeDispatchingProjection(
        XmlText      => XmlTextToSyntaxLeaf(),
        XmlElement   => XmlElementToSyntaxNode(),
        XmlInsertion => XmlInsertionToSyntaxLeaf(),
    )
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

end # module
