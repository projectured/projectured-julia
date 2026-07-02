"""
    XmlToSyntaxModule

XML → SyntaxDocument projection. Maps XML text and element nodes to syntax
tree leaves and nodes, reflecting tag/attribute/child structure as delimiters
and indented children.
"""
module XmlToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read, map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..XmlModule: XmlDocument, XmlInsertion, XmlText, XmlAttribute, XmlElement
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20
import ..ColorModule: StyleColor, color_black, color_default, color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_cyan, color_solarized_yellow, color_solarized_gray
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, ProjectionReference, ReferencePath, append_reference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..PrinterContextModule: child_context
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: StringReplaceRangeOperation
import ..SyntaxToTextModule: SyntaxNodeToText, _syntax_to_flat
export XmlInsertionToSyntaxLeaf, XmlTextToSyntaxLeaf, XmlElementToSyntaxNode, XmlToSyntax

# ── Individual projection structs ─────────────────────────────────────────
#
# XmlTextToSyntaxLeaf    — maps XmlText    → SyntaxLeaf
# XmlElementToSyntaxNode — maps XmlElement → structured SyntaxNode:
#
#   SyntaxNode(open="", close="", sep="", [
#     SyntaxLeaf(open="<",  close=" "|"", value=tag),   ← tag-name leaf
#     SyntaxNode(open="", close=">", sep=" ", [          ← attributes node
#       SyntaxNode(open="", close="", sep="=", [         ← each attribute
#         SyntaxLeaf(name),
#         SyntaxLeaf(open='"', close='"', value),
#       ]), ...
#     ]),
#     ... recursive XML children ...,
#     SyntaxLeaf(open="</", close=">", value=tag),       ← closing-tag leaf
#   ])
#
# All internal nodes have open="" so SyntaxToText renders them
# inline (no indentation).  The space between the tag name and the first
# attribute is provided by a reactive close field on the tag-name leaf:
# it evaluates to " " when attributes are present and "" otherwise.

@projection struct XmlTextToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_black)
end

function map_reference_forward(::XmlTextToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        ::XmlText.content.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
    end
end

function map_reference_backward(::XmlTextToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        ::SyntaxLeaf.value.rest... => @reference ::XmlText.content::String.^(rest)
    end
end

function projection_read(p::XmlTextToSyntaxLeaf, iomap, op::ReplaceSelectionOperation)
    path = op.path
    path isa ConcreteReferencePath || return nothing
    h = path.head
    if h isa FieldReference && h.name == "value"
        return ReplaceSelectionOperation(@reference content.^(path.tail))
    else
        return ReplaceSelectionOperation(@reference proj(p, ^(path)))
    end
end

# Type-in: a syntax-domain `.value[s:e]` edit translates to the text node's
# `.content[s:e]` via the same map_reference_backward used for selection reads.
function projection_read(p::XmlTextToSyntaxLeaf, iomap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function _xml_text_sel(t::XmlText)
    Cell(() -> begin
        sel = t.selection
        sel isa ConcreteReferencePath && sel.head isa ProjectionReference && return sel
        @reference_case t.selection begin
            content.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
        end
    end)
end

function projection_print(p::XmlTextToSyntaxLeaf, recursion, t::XmlText, ctx)
    output_selection = _xml_text_sel(t)
    SimpleIoMap(p, t, SyntaxLeaf(TextString(() -> t.content, p.style); selection=output_selection))
end

# ── XmlInsertionToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct XmlInsertionToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

function projection_print(p::XmlInsertionToSyntaxLeaf, recursion, x::XmlInsertion, ctx)
    output_selection = Cell(() -> map_reference_forward(p, nothing, x.selection))
    SimpleIoMap(p, x, SyntaxLeaf(TextString("insert XML here", p.style); selection=output_selection))
end

@projection struct XmlElementToSyntaxNode
    tag::StyleText        = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    delim::StyleText      = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    attr_name::StyleText  = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    quote_style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    attr_value::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

# Selection mapping (School A). The output node's children are
# [tag leaf (1), attrs node (2), body node (3), close leaf (4)]. The recursively
# projected XML children live inside the body node, so .children[i] maps to
# .children[3].children[i] and the tail is delegated through the stored child IO
# map — independent of what projection rendered each child. The tag and the
# attributes are projection-introduced structure, so they map directly to their
# fixed output positions:
#   .tag[k]            → .children[1].value[k]
#   .attrs[i].name[k]  → .children[2].children[i].children[1].value[k]
#   .attrs[i].value[k] → .children[2].children[i].children[2].value[k]
# The closing tag (child 4) renders the same .tag field but carries no cursor.
function map_reference_forward(p::XmlElementToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ::XmlElement.tag.rest...        => @reference ::SyntaxNode.children[1].value::TextString.^(rest)
        ::XmlElement.attrs{s:_}.name.rest... => begin
            attr_i = s + 1
            (1 <= attr_i <= length(iomap.input.attrs)) || return nothing
            @reference ::SyntaxNode.children[2].children[attr_i].children[1].value::TextString.^(rest)
        end
        ::XmlElement.attrs{s:_}.value.rest... => begin
            attr_i = s + 1
            (1 <= attr_i <= length(iomap.input.attrs)) || return nothing
            @reference ::SyntaxNode.children[2].children[attr_i].children[2].value::TextString.^(rest)
        end
        ::XmlElement.children{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children[3].children[child_i].^(inner)
        end
    end
end

function map_reference_backward(p::XmlElementToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ::SyntaxNode.children{s:_}.rest... => begin
            child_i = s + 1
            if child_i == 1
                # tag leaf: .value[k] → .tag[k]
                @reference_case rest begin
                    value.vtail... => @reference ::XmlElement.tag::String.^(vtail)
                end
            elseif child_i == 2
                # attrs node: .children[i].children[j].value[k] →
                #   .attrs[i].name[k]  (j == 1)  /  .attrs[i].value[k]  (j == 2)
                @reference_case rest begin
                    children{ai:_}.children{lj:_}.ltail... => begin
                        attr_i = ai + 1
                        leaf_j = lj + 1
                        (1 <= attr_i <= length(iomap.input.attrs)) || return nothing
                        @reference_case ltail begin
                            value.vtail... => begin
                                if leaf_j == 1
                                    @reference ::XmlElement.attrs[attr_i].name::String.^(vtail)
                                elseif leaf_j == 2
                                    @reference ::XmlElement.attrs[attr_i].value::String.^(vtail)
                                else
                                    nothing
                                end
                            end
                        end
                    end
                end
            elseif child_i == 3
                # body node: delegate each XML child through its stored IO map.
                @reference_case rest begin
                    children{s2:_}.tail... => begin
                        child_j = s2 + 1
                        iomaps = iomap.child_iomaps[]
                        1 <= child_j <= length(iomaps) || return nothing
                        child = iomaps[child_j]
                        translated = map_reference_backward(child.projection, child, tail)
                        translated === nothing && return nothing
                        @reference ::XmlElement.children[child_j].^(translated)
                    end
                end
            else
                # child 4 is the closing tag. It renders the same `.tag` field
                # as the start tag (child 1), which already updates both tags
                # reactively (a text edit threads back to `.tag[s:e]` and
                # `splice_value!` rewrites the shared field), so the end tag is
                # intentionally display-only: it carries no
                # cursor forward and no edit maps back through it. Edit the tag
                # via the start tag instead (plan §5.2, "display-only" option).
                nothing
            end
        end
    end
end

function projection_read(p::XmlElementToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

# Type-in: route a child's `.value[s:e]` edit back to `.children[i].…` through the
# stored child IO map (School A delegation), the same path map_reference_backward
# uses for selection reads. Edits targeting projection-introduced spans (tag,
# attributes, closing tag) fall through to nothing.
function projection_read(p::XmlElementToSyntaxNode, iomap::ChildrenIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function projection_print(p::XmlElementToSyntaxNode, recursion, e::XmlElement, ctx)
    reference = ctx.reference
    child_iomaps = Cell(() -> [projection_printer_recurse(recursion, child,
                                   child_context(ctx, @reference ^(reference).children[i]))
                               for (i, child) in enumerate(e.children)])

    sel = Cell(() -> begin
        path = e.selection
        path isa ConcreteReferencePath && path.head isa ProjectionReference && return path
        @reference_case e.selection begin
            children{s:_}.rest... => begin
                child_i = s + 1
                iomaps = child_iomaps[]
                child_i > length(iomaps) && return nothing
                child_sel = iomaps[child_i].output.selection
                child_sel === nothing && return nothing
                @reference ::SyntaxNode.children[3].children[child_i].^(child_sel)
            end
        end
    end)

    # The opening tag carries the cursor for `.tag[k]` edits, mapped onto its
    # own value span (`.tag[k]` → `.value[k]`). The closing tag renders the same
    # field but never holds a cursor.
    tag_sel = Cell(() -> begin
        @reference_case e.selection begin
            tag.rest... => @reference ::SyntaxLeaf.value::TextString.^(rest)
        end
    end)
    tag_leaf = SyntaxLeaf(
        TextString(() -> e.tag, p.tag);
        open=TextString("<", p.delim),
        close=TextString(() -> isempty(e.attrs) ? "" : " ", p.delim),
        selection=tag_sel)

    attrs_node = SyntaxNode(
        () -> SyntaxDocument[_attr_node(a, p) for a in e.attrs];
        close=TextString(">", p.delim),
        sep=TextString(" ", p.delim.font, color_default))

    body_node = SyntaxNode(
        CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]]);
        indentation=1)

    close_leaf = SyntaxLeaf(
        TextString(() -> e.tag, p.tag);
        open=TextString("</", p.delim),
        close=TextString(">",  p.delim))

    ChildrenIoMap(p, e, SyntaxNode(
        CellVector(Cell[Cell(tag_leaf), Cell(attrs_node), Cell(body_node), Cell(close_leaf)]);
        selection=sel), child_iomaps)
end

# ── Utility functions ──────────────────────────────────────────────────────

function xml_escape_text(s::AbstractString)
    buf = IOBuffer()
    for ch in s
        if ch == '&'      write(buf, "&amp;")
        elseif ch == '<'  write(buf, "&lt;")
        elseif ch == '>'  write(buf, "&gt;")
        else              write(buf, ch)
        end
    end
    String(take!(buf))
end

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

# Each attribute renders as a two-leaf node `name = "value"`. The name leaf
# carries the cursor for `.name[k]` edits and the value leaf for `.value[k]`
# edits, each mapped onto its own value span.
function _attr_node(a::XmlAttribute, p::XmlElementToSyntaxNode)
    name_sel = Cell(() -> begin
        @reference_case a.selection begin
            name.rest... => @reference value.^(rest)
        end
    end)
    value_sel = Cell(() -> begin
        @reference_case a.selection begin
            value.rest... => @reference value.^(rest)
        end
    end)
    SyntaxNode(
        SyntaxDocument[
            SyntaxLeaf(
                TextString(() -> a.name, p.attr_name);
                selection=name_sel),
            SyntaxLeaf(
                TextString(() -> xml_escape_attr(a.value), p.attr_value);
                open=TextString("\"", p.quote_style),
                close=TextString("\"", p.quote_style),
                selection=value_sel),
        ];
        sep=TextString("=", p.delim))
end

# The XML authoring command set lives with the domain as `@gestures` (document/Xml.jl);
# raw keys reach it through the generic `projection_read → document_read` delegation.

function XmlToSyntax()
    TypeDispatchingProjection(
        XmlText      => XmlTextToSyntaxLeaf(),
        XmlElement    => XmlElementToSyntaxNode(),
        XmlInsertion  => XmlInsertionToSyntaxLeaf(),
    )
end

end # module
