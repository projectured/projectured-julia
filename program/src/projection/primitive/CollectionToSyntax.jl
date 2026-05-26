"""
    CollectionToSyntaxModule

Collection → Syntax projection. Handles `CellVector` and `ListNode`
as top-level collection documents, mapping each element through recursion.

- `CellVector` → `SyntaxNode` with `[`, `]` delimiters and eager children.
- `ListNode`   → `ListNode(projected)` preserving lazy structure (no wrapping
   delimiters for infinite lists).
"""
module CollectionToSyntaxModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..CollectionModule: CellVector, ListNode
import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..SyntaxModule: SyntaxDocument, SyntaxNode
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_solarized_gray
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..IoMapApiModule: IoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, FieldReference, RangeReference,
                          EmptyReferencePath, append_reference
export CollectionCellVectorToSyntax, CollectionListNodeToSyntax, CollectionToSyntax

# ── CollectionCellVectorToSyntax ─────────────────────────────────────────────

struct CollectionCellVectorToSyntax <: Projection
    delim_font::StyleFont
    delim_color::StyleColor
    sep_font::StyleFont
    sep_color::StyleColor
end
CollectionCellVectorToSyntax(; delim_font=font_ubuntu_monospace_bold_24, delim_color=color_solarized_gray,
                                sep_font=font_ubuntu_monospace_regular_24, sep_color=color_solarized_gray) =
    CollectionCellVectorToSyntax(delim_font, delim_color, sep_font, sep_color)

function map_reference_forward(::CollectionCellVectorToSyntax, iomap, reference)
    return nothing
end

function map_reference_backward(::CollectionCellVectorToSyntax, iomap, reference)
    return nothing
end

function projection_print(p::CollectionCellVectorToSyntax, cv::CellVector, recursion, reference)
    child_iomaps = Cell(() -> [projection_print(recursion, x, recursion,
                                   append_reference(reference, ElementReference(i)))
                               for (i, x) in enumerate(cv)])
    node = SyntaxNode(
        TextString("[", p.delim_font, p.delim_color),
        TextString("]", p.delim_font, p.delim_color),
        TextString(", ", p.sep_font, p.sep_color),
        CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]]),
        1,
        Cell(false),
        Cell(nothing))
    ChildrenIoMap(p, cv, node, child_iomaps)
end

# ── CollectionListNodeToSyntax ───────────────────────────────────────────────

struct CollectionListNodeToSyntax <: Projection end

function map_reference_forward(::CollectionListNodeToSyntax, iomap, reference)
    return nothing
end

function map_reference_backward(::CollectionListNodeToSyntax, iomap, reference)
    return nothing
end

"""
    projection_print(::CollectionListNodeToSyntax, ln::ListNode, recursion, reference)

Maps each element in the `ListNode` through `recursion` lazily.
The output is a `ListNode(projected)` preserving the lazy structure.
"""
function projection_print(p::CollectionListNodeToSyntax, ln::ListNode, recursion, reference)
    out_head = _map_listnode(recursion, ln, reference, 1)
    SimpleIoMap(p, ln, out_head)
end

function _map_listnode(recursion, input_node::ListNode, reference, index::Int)
    child_ref = append_reference(reference, ElementReference(index))
    child_iomap = projection_print(recursion, input_node.value, recursion, child_ref)
    out_node = ListNode(child_iomap.output)

    # Lazy next
    setfn!(getfield(out_node, :next), () -> begin
        input_next = input_node.next
        input_next === nothing && return nothing
        next_out = _map_listnode(recursion, input_next, reference, index + 1)
        setval!(getfield(next_out, :prev), out_node)
        next_out
    end)

    # Lazy prev
    setfn!(getfield(out_node, :prev), () -> begin
        input_prev = input_node.prev
        input_prev === nothing && return nothing
        prev_out = _map_listnode(recursion, input_prev, reference, index - 1)
        setval!(getfield(prev_out, :next), out_node)
        prev_out
    end)

    out_node
end

# ── CollectionToSyntax (composite) ───────────────────────────────────────────

import ..TypeDispatchingModule: TypeDispatchingProjection

"""
    CollectionToSyntax()

Composite projection that dispatches `CellVector` to
`CollectionCellVectorToSyntax` and `ListNode` to `CollectionListNodeToSyntax`.
Element projection is supplied by the surrounding `recursion`; compose with
`NestingProjection` to provide the element-level conversion.

Usage:
    NestingProjection(CollectionToSyntax(), PrimitiveStringToSyntaxLeaf())
"""
function CollectionToSyntax()
    TypeDispatchingProjection(
        CellVector => CollectionCellVectorToSyntax(),
        ListNode   => CollectionListNodeToSyntax(),
    )
end

end # module
