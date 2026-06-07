"""
    XmlToSyntaxModule

XML → SyntaxDocument projection. Maps XML text and element nodes to syntax
tree leaves and nodes, reflecting tag/attribute/child structure as delimiters
and indented children.
"""
module XmlToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..XmlModule: XmlDocument, XmlInsertion, XmlText, XmlAttribute, XmlElement
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_black, color_default, color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_cyan, color_solarized_yellow, color_solarized_gray
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, ProjectionReference, ReferencePath, EmptyReferencePath, append_reference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..ProjectionContextModule: child_context
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

struct XmlTextToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
XmlTextToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_black) = XmlTextToSyntaxLeaf(font, color)

function map_reference_forward(::XmlTextToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        cell.rest... => @reference value.^(rest)
    end
end

function map_reference_backward(::XmlTextToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        value.rest... => @reference cell.^(rest)
    end
end

function projection_read(p::XmlTextToSyntaxLeaf, iomap, op::ReplaceSelectionOperation)
    path = op.path
    path isa ConcreteReferencePath || return nothing
    h = path.head
    if h isa FieldReference && h.name == "value"
        return ReplaceSelectionOperation(@reference cell.^(path.tail))
    else
        return ReplaceSelectionOperation(@reference proj(p, ^(path)))
    end
end

# Type-in: a syntax-domain `.value[s:e]` edit translates to the text node's
# `.cell[s:e]` via the same map_reference_backward used for selection reads.
function projection_read(p::XmlTextToSyntaxLeaf, iomap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function _xml_text_sel(t::XmlText)
    Cell(() -> begin
        sel = t.selection
        sel isa ConcreteReferencePath && sel.head isa ProjectionReference && return sel
        @reference_case sel begin
            cell.rest... => @reference value.^(rest)
        end
    end)
end

function projection_print(p::XmlTextToSyntaxLeaf, t::XmlText, recursion, ctx)
    output_selection = _xml_text_sel(t)
    SimpleIoMap(p, t, SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default), TextString(() -> t.cell, p.font, p.color), output_selection))
end

# ── XmlInsertionToSyntaxLeaf ───────────────────────────────────────────────────

struct XmlInsertionToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
XmlInsertionToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_gray) = XmlInsertionToSyntaxLeaf(font, color)

function projection_print(p::XmlInsertionToSyntaxLeaf, x::XmlInsertion, recursion, ctx)
    output_selection = Cell(() -> map_reference_forward(p, nothing, x.selection))
    SimpleIoMap(p, x, SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default), TextString("insert XML here", p.font, p.color), output_selection))
end

struct XmlElementToSyntaxNode <: Projection
    tag_font::StyleFont
    tag_color::StyleColor
    delim_font::StyleFont
    delim_color::StyleColor
    attr_name_font::StyleFont
    attr_name_color::StyleColor
    quote_font::StyleFont
    quote_color::StyleColor
    attr_value_font::StyleFont
    attr_value_color::StyleColor
end
XmlElementToSyntaxNode(;
        tag_font=font_ubuntu_monospace_bold_24,       tag_color=color_solarized_blue,
        delim_font=font_ubuntu_monospace_regular_24,         delim_color=color_solarized_gray,
        attr_name_font=font_ubuntu_monospace_regular_24,     attr_name_color=color_solarized_green,
        quote_font=font_ubuntu_monospace_regular_24,         quote_color=color_solarized_yellow,
        attr_value_font=font_ubuntu_monospace_regular_24,    attr_value_color=color_solarized_cyan) =
    XmlElementToSyntaxNode(tag_font, tag_color, delim_font, delim_color,
                           attr_name_font, attr_name_color,
                           quote_font, quote_color,
                           attr_value_font, attr_value_color)

# Selection mapping (School A). The output node's children are
# [tag leaf (1), attrs node (2), body node (3), close leaf (4)]. The recursively
# projected XML children live inside the body node, so .cell[i] maps to
# .children[3].children[i] and the tail is delegated through the stored child IO
# map — independent of what projection rendered each child. The tag and the
# attributes are projection-introduced structure, so they map directly to their
# fixed output positions:
#   .tag[k]          → .children[1].value[k]
#   .attrs[i].name[k] → .children[2].children[i].children[1].value[k]
#   .attrs[i].cell[k] → .children[2].children[i].children[2].value[k]
# The closing tag (child 4) renders the same .tag field but carries no cursor.
function map_reference_forward(p::XmlElementToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        tag.rest...        => @reference children[1].value.^(rest)
        attrs{s:_}.name.rest... => begin
            attr_i = s + 1
            (1 <= attr_i <= length(iomap.input.attrs)) || return nothing
            @reference children[2].children[attr_i].children[1].value.^(rest)
        end
        attrs{s:_}.cell.rest... => begin
            attr_i = s + 1
            (1 <= attr_i <= length(iomap.input.attrs)) || return nothing
            @reference children[2].children[attr_i].children[2].value.^(rest)
        end
        cell{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[3].children[child_i].^(inner)
        end
    end
end

function map_reference_backward(p::XmlElementToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        children{s:_}.rest... => begin
            child_i = s + 1
            if child_i == 1
                # tag leaf: .value[k] → .tag[k]
                @reference_case rest begin
                    value.vtail... => @reference tag.^(vtail)
                end
            elseif child_i == 2
                # attrs node: .children[i].children[j].value[k] →
                #   .attrs[i].name[k]  (j == 1)  /  .attrs[i].cell[k]  (j == 2)
                @reference_case rest begin
                    children{ai:_}.children{lj:_}.ltail... => begin
                        attr_i = ai + 1
                        leaf_j = lj + 1
                        (1 <= attr_i <= length(iomap.input.attrs)) || return nothing
                        @reference_case ltail begin
                            value.vtail... => begin
                                if leaf_j == 1
                                    @reference attrs[attr_i].name.^(vtail)
                                elseif leaf_j == 2
                                    @reference attrs[attr_i].cell.^(vtail)
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
                        @reference cell[child_j].^(translated)
                    end
                end
            else
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

# Type-in: route a child's `.value[s:e]` edit back to `.cell[i].…` through the
# stored child IO map (School A delegation), the same path map_reference_backward
# uses for selection reads. Edits targeting projection-introduced spans (tag,
# attributes, closing tag) fall through to nothing.
function projection_read(p::XmlElementToSyntaxNode, iomap::ChildrenIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function projection_print(p::XmlElementToSyntaxNode, e::XmlElement, recursion, ctx)
    reference = ctx.reference
    child_iomaps = Cell(() -> [projection_print(recursion, child, recursion,
                                   child_context(ctx, @reference ^(reference).cell[i]))
                               for (i, child) in enumerate(e)])

    sel = Cell(() -> begin
        path = e.selection
        path isa ConcreteReferencePath && path.head isa ProjectionReference && return path
        @reference_case path begin
            cell{s:_}.rest... => begin
                child_i = s + 1
                iomaps = child_iomaps[]
                child_i > length(iomaps) && return nothing
                child_sel = iomaps[child_i].output.selection
                child_sel === nothing && return nothing
                @reference children[3].children[child_i].^(child_sel)
            end
        end
    end)

    # The opening tag carries the cursor for `.tag[k]` edits, mapped onto its
    # own value span (`.tag[k]` → `.value[k]`). The closing tag renders the same
    # field but never holds a cursor.
    tag_sel = Cell(() -> begin
        @reference_case e.selection begin
            tag.rest... => @reference value.^(rest)
        end
    end)
    tag_leaf = SyntaxLeaf(
        TextString("<", p.delim_font, p.delim_color),
        TextString(() -> isempty(e.attrs) ? "" : " ", p.delim_font, p.delim_color),
        TextString(() -> e.tag, p.tag_font, p.tag_color),
        tag_sel)

    attrs_node = SyntaxNode(
        TextString("", p.delim_font, color_default),
        TextString(">", p.delim_font, p.delim_color),
        TextString(" ", p.delim_font, color_default),
        () -> SyntaxDocument[_attr_node(a, p) for a in e.attrs])

    body_node = SyntaxNode(
        TextString("", p.delim_font, color_default),
        TextString("", p.delim_font, color_default),
        TextString("", p.delim_font, color_default),
        CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]]),
        1,
        Cell(false),
        Cell(nothing))

    close_leaf = SyntaxLeaf(
        TextString("</", p.delim_font, p.delim_color),
        TextString(">",  p.delim_font, p.delim_color),
        TextString(() -> e.tag, p.tag_font, p.tag_color))

    ChildrenIoMap(p, e, SyntaxNode(
        TextString("", p.delim_font, color_default),
        TextString("", p.delim_font, color_default),
        TextString("", p.delim_font, color_default),
        CellVector(Cell[Cell(tag_leaf), Cell(attrs_node), Cell(body_node), Cell(close_leaf)]),
        0,
        Cell(false),
        sel), child_iomaps)
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
# carries the cursor for `.name[k]` edits and the value leaf for `.cell[k]`
# edits, each mapped onto its own value span.
function _attr_node(a::XmlAttribute, p::XmlElementToSyntaxNode)
    name_sel = Cell(() -> begin
        @reference_case a.selection begin
            name.rest... => @reference value.^(rest)
        end
    end)
    value_sel = Cell(() -> begin
        @reference_case a.selection begin
            cell.rest... => @reference value.^(rest)
        end
    end)
    SyntaxNode(
        TextString("", p.delim_font, color_default),
        TextString("", p.delim_font, color_default),
        TextString("=", p.delim_font, p.delim_color),
        SyntaxDocument[
            SyntaxLeaf(
                TextString("", p.attr_name_font, color_default),
                TextString("", p.attr_name_font, color_default),
                TextString(() -> a.name, p.attr_name_font, p.attr_name_color),
                name_sel),
            SyntaxLeaf(
                TextString("\"", p.quote_font, p.quote_color),
                TextString("\"", p.quote_font, p.quote_color),
                TextString(() -> xml_escape_attr(a.cell), p.attr_value_font, p.attr_value_color),
                value_sel),
        ])
end

function XmlToSyntax()
    TypeDispatchingProjection(
        XmlText      => XmlTextToSyntaxLeaf(),
        XmlElement    => XmlElementToSyntaxNode(),
        XmlInsertion  => XmlInsertionToSyntaxLeaf(),
    )
end

end # module
