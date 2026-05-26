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
import ..OperationModule: ReplaceSelectionOperation
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
    reference isa ConcreteReferencePath || return nothing
    h = reference.head
    h isa FieldReference && h.name == "cell" || return nothing
    return ConcreteReferencePath(FieldReference("value"), reference.tail)
end

function map_reference_backward(::XmlTextToSyntaxLeaf, iomap, reference)
    reference isa ConcreteReferencePath || return nothing
    h = reference.head
    h isa FieldReference && h.name == "value" || return nothing
    return ConcreteReferencePath(FieldReference("cell"), reference.tail)
end

function projection_read(p::XmlTextToSyntaxLeaf, iomap, op::ReplaceSelectionOperation)
    path = op.path
    path isa ConcreteReferencePath || return nothing
    h = path.head
    if h isa FieldReference && h.name == "value"
        return ReplaceSelectionOperation(ConcreteReferencePath(FieldReference("cell"), path.tail))
    else
        return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, path)))
    end
end

function _xml_text_sel(t::XmlText)
    Cell(() -> begin
        sel = t.selection
        sel isa ConcreteReferencePath || return nothing
        h = sel.head
        if h isa FieldReference && h.name == "cell"
            ConcreteReferencePath(FieldReference("value"), sel.tail)
        elseif h isa ProjectionReference
            sel
        else
            nothing
        end
    end)
end

function projection_print(p::XmlTextToSyntaxLeaf, t::XmlText, recursion, reference)
    output_selection = _xml_text_sel(t)
    SimpleIoMap(p, t, SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default), TextString(() -> t.cell, p.font, p.color), output_selection))
end

# ── XmlInsertionToSyntaxLeaf ───────────────────────────────────────────────────

struct XmlInsertionToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
XmlInsertionToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_gray) = XmlInsertionToSyntaxLeaf(font, color)

function projection_print(p::XmlInsertionToSyntaxLeaf, x::XmlInsertion, recursion, reference)
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

function map_reference_forward(::XmlElementToSyntaxNode, iomap::ChildrenIoMap, reference)
    return _forward_xml_path(iomap.input::XmlElement, reference)
end

function map_reference_backward(::XmlElementToSyntaxNode, iomap::ChildrenIoMap, reference)
    return _translate_xml_path(iomap.input::XmlElement, reference)
end

function projection_read(p::XmlElementToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = _translate_xml_path(iomap.input::XmlElement, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

function projection_print(p::XmlElementToSyntaxNode, e::XmlElement, recursion, reference)
    child_iomaps = Cell(() -> [projection_print(recursion, child, recursion,
                                   append_reference(reference, FieldReference("cell"), ElementReference(i)))
                               for (i, child) in enumerate(e)])

    sel = Cell(() -> begin
        path = e.selection
        path isa ConcreteReferencePath || return nothing
        h = path.head
        if h isa FieldReference && h.name == "cell"
            rest = path.tail
            rest isa ConcreteReferencePath || return nothing
            h2 = rest.head
            h2 isa RangeReference || return nothing
            child_i = h2.start + 1
            iomaps = child_iomaps[]
            child_i > length(iomaps) && return nothing
            child_sel = iomaps[child_i].output.selection
            child_sel === nothing && return nothing
            return ConcreteReferencePath(FieldReference("children"),
                       ConcreteReferencePath(ElementReference(2),
                           ConcreteReferencePath(FieldReference("children"),
                               ConcreteReferencePath(ElementReference(child_i), child_sel))))
        elseif h isa ProjectionReference
            return path
        end
        return nothing
    end)

    tag_leaf = SyntaxLeaf(
        TextString("<", p.delim_font, p.delim_color),
        TextString(() -> isempty(e.attrs) ? "" : " ", p.delim_font, p.delim_color),
        TextString(e.tag, p.tag_font, p.tag_color),
        getfield(e, :selection))

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
        TextString(e.tag, p.tag_font, p.tag_color))

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

function _attr_node(a::XmlAttribute, p::XmlElementToSyntaxNode)
    SyntaxNode(
        TextString("", p.delim_font, color_default),
        TextString("", p.delim_font, color_default),
        TextString("=", p.delim_font, p.delim_color),
        SyntaxDocument[
            SyntaxLeaf(TextString(a.name, p.attr_name_font, p.attr_name_color)),
            SyntaxLeaf(
                TextString("\"", p.quote_font, p.quote_color),
                TextString("\"", p.quote_font, p.quote_color),
                TextString(() -> xml_escape_attr(a.cell), p.attr_value_font, p.attr_value_color),
                getfield(a, :selection)),
        ])
end

function _translate_xml_path(t::XmlText, path::ReferencePath)
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "value" || return nothing
    return ConcreteReferencePath(FieldReference("cell"), path.tail)
end

function _translate_xml_path(e::XmlElement, path::ReferencePath)
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "children" || return nothing
    rest2 = path.tail
    rest2 isa ConcreteReferencePath || return nothing
    h2 = rest2.head
    h2 isa RangeReference || return nothing
    outer_child = h2.start + 1
    outer_child == 2 || return nothing  # must be body_node (index 2)
    rest3 = rest2.tail
    rest3 isa ConcreteReferencePath || return nothing
    h3 = rest3.head
    h3 isa FieldReference || return nothing
    rest4 = rest3.tail
    rest4 isa ConcreteReferencePath || return nothing
    h4 = rest4.head
    h4 isa RangeReference || return nothing
    child_i = h4.start + 1
    1 <= child_i <= length(e) || return nothing
    child = e[child_i]
    translated = _translate_xml_path(child, rest4.tail)
    translated === nothing && return nothing
    return ConcreteReferencePath(FieldReference("cell"),
               ConcreteReferencePath(ElementReference(child_i), translated))
end

function _forward_xml_path(t::XmlText, path::ReferencePath)
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "cell" || return nothing
    return ConcreteReferencePath(FieldReference("value"), path.tail)
end

function _forward_xml_path(e::XmlElement, path::ReferencePath)
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "cell" || return nothing
    rest = path.tail
    rest isa ConcreteReferencePath || return nothing
    h2 = rest.head
    h2 isa RangeReference || return nothing
    child_i = h2.start + 1
    1 <= child_i <= length(e) || return nothing
    child = e[child_i]
    inner = _forward_xml_path(child, rest.tail)
    inner === nothing && return nothing
    return ConcreteReferencePath(FieldReference("children"),
               ConcreteReferencePath(ElementReference(2),
                   ConcreteReferencePath(FieldReference("children"),
                       ConcreteReferencePath(ElementReference(child_i), inner))))
end

function XmlToSyntax()
    TypeDispatchingProjection(
        XmlText      => XmlTextToSyntaxLeaf(),
        XmlElement    => XmlElementToSyntaxNode(),
        XmlInsertion  => XmlInsertionToSyntaxLeaf(),
    )
end

end # module
