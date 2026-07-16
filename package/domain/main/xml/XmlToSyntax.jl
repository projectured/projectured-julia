"""
    XmlToSyntaxModule

XML → SyntaxDocument projection, written with `@projection_template` (like
`JsonToSyntax` / `JuliaToSyntax`). Each XML type is a builder that constructs the
real Syntax output with `bound(…)` / `collection(…)` markers at the positions that
need special wiring; the template engine (`ProjectionTemplate.jl`) records the
wiring, strips the markers, and supplies reference mapping and the recursive reader
generically. The authoring command set lives on the XML document types as
`@gestures` (see `document/Xml.jl`); the template's reader delegates a raw gesture
to `read_gesture`.

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

Internal nodes have no open delimiter, so SyntaxToText renders them inline. The space
between the tag name and the first attribute is a reactive `close` on the tag leaf:
`" "` when attributes are present, `""` otherwise. The closing tag renders the same
`.tag` field (updated reactively) but is projection-introduced structure (no
`bound`), so it carries no cursor and maps nothing back.
"""
module XmlToSyntaxModule

import ..CellModule: Cell
import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..ReferenceModule: ConcreteReferencePath, PositionReference
import ..ProjectionReferenceModule: ProjectionReference, is_introduced_reference
import ..OperationModule: ReplaceSelectionOperation
import ..SyntaxToTextModule: SyntaxCompoundToText, _syntax_to_flat
import ..XmlModule: XmlDocument, XmlNothing, XmlInsertion, XmlText, XmlAttribute, XmlElement
import ..DocumentInsertionToSyntaxModule: DomainInsertionToSyntaxLeaf, InsertionNothingToSyntaxLeaf
import ..TextModule: TextString
import ..FontModule: font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20
import ..ColorModule: color_black, color_default, color_solarized_blue, color_solarized_green,
                      color_solarized_cyan, color_solarized_yellow, color_solarized_gray
import ..StyleTextModule: StyleText, DStyleText
import ..SyntaxModule: SyntaxLeaf, SyntaxNode, SyntaxConcatenation
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..ProjectionTemplateModule: var"@projection_template", bound, collection, RuleIoMap
export XmlInsertionToSyntaxLeaf, XmlTextToSyntaxLeaf, XmlAttributeToSyntaxNode,
       XmlElementToSyntaxNode, XmlToSyntax

# ── XmlTextToSyntaxLeaf ─────────────────────────────────────────────────────
#
# A bound leaf: `.content{k}` edits map to the leaf's own `.value{k}` span.

@projection struct XmlTextToSyntaxLeaf
    style::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_black)
end

@projection_template XmlTextToSyntaxLeaf XmlText (p, t) ->
    SyntaxLeaf(bound(:content, String, TextString(() -> t.content, p.style)))

# ── XmlInsertionToSyntaxLeaf ────────────────────────────────────────────────
#
# The shared typed-name insertion buffer, constrained to the XML candidates
# (prefix-free: `element` → `XmlElement`, `text` → `XmlText`). The `<`/`"`
# type-to-replace gestures on a whole-selected insertion keep working: the
# leaf's char editing declines without a value cursor, so those keys fall
# through to `@gestures XmlDocument` (declared in `document/Xml.jl`).

XmlInsertionToSyntaxLeaf() = DomainInsertionToSyntaxLeaf(XmlDocument)

# ── XmlAttributeToSyntaxNode ────────────────────────────────────────────────
#
# A fixed 2-leaf `name="value"` node, both leaves bound. An attribute is a
# document in its own right, so it projects on its own rather than being built
# inline by the element that happens to hold it.

@projection struct XmlAttributeToSyntaxNode
    delim::ImmutableCell{DStyleText}       = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    attr_name::ImmutableCell{DStyleText}   = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    quote_style::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    attr_value::ImmutableCell{DStyleText}  = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

@projection_template XmlAttributeToSyntaxNode XmlAttribute (p, a) ->
    SyntaxNode(TextString("", p.delim), TextString("", p.delim), TextString("=", p.delim),
        [ SyntaxLeaf(bound(:name, String, TextString(() -> a.name, p.attr_name))),
          SyntaxLeaf(bound(:value, String, TextString(() -> xml_escape_attr(a.value), p.attr_value));
                     open=TextString("\"", p.quote_style),
                     close=TextString("\"", p.quote_style)) ],
        0, false, nothing)

# ── XmlElementToSyntaxNode ──────────────────────────────────────────────────

@projection struct XmlElementToSyntaxNode
    tag::ImmutableCell{DStyleText}   = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    delim::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
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
                            sep=TextString(" ", p.delim.font, color_default))

    body_node = SyntaxNode(collection(:children); indentation=1)

    close_leaf = SyntaxLeaf(TextString(() -> e.tag, p.tag);
                            open=TextString("</", p.delim),
                            close=TextString(">", p.delim))

    SyntaxConcatenation([ tag_leaf, attrs_node, body_node, close_leaf ])
end

# ── Structural-caret navigation (the one bit the template engine can't supply) ─
#
# The element node carries projection-introduced text that has no input pre-image:
# the delimiters (`<`, `>`, `</`, `"`, `=`) and the closing tag (which re-renders
# `.tag` as a display-only child). A text caret there maps back to *nothing* through
# the wiring. The template's domain-neutral fallback wraps the whole (output-domain)
# path in a `ProjectionReference`; but `strip_reference_types` (which the navigation
# BFS dedups on) does not collapse that, so each round-trip through such a caret grows
# the path without bound and the caret walk never terminates.
#
# XML instead collapses an unmapped caret to a single canonical **flat offset** into
# the rendered node (`_syntax_to_flat`, the same machinery SyntaxToText round-trips
# through) — a bounded set, so navigation terminates. This is the SyntaxToText-specific
# piece the engine deliberately leaves to the domain; the printer, reference mapping,
# and every other reader still come from `@projection_template`.
function read_intent(p::XmlElementToSyntaxNode, iomap::RuleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxConcatenation, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

# Render that flat structural caret back out: a `proj(p, …)` selection is this
# projection's own introduced position, so pass it through unchanged (the fixed-node
# forward mapper handles field references but not our own projection wrap). Everything
# else defers to the generic template mapper.
function map_reference_forward(p::XmlElementToSyntaxNode, iomap::RuleIoMap, reference)
    is_introduced_reference(reference) && return reference
    invoke(map_reference_forward, Tuple{Projection, RuleIoMap, Any}, p, iomap, reference)
end

# ── XmlToSyntax (composite) ─────────────────────────────────────────────────

function XmlToSyntax()
    TypeDispatchingProjection(
        XmlText      => XmlTextToSyntaxLeaf(),
        XmlAttribute => XmlAttributeToSyntaxNode(),
        XmlElement   => XmlElementToSyntaxNode(),
        XmlInsertion => XmlInsertionToSyntaxLeaf(),
        XmlNothing   => InsertionNothingToSyntaxLeaf(),
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
