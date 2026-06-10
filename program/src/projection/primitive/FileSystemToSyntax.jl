"""
    FileSystemToSyntaxModule

FileSystem → SyntaxDocument projection. Maps file-system nodes to syntax
tree shapes:

    FileSystemFile      → SyntaxLeaf  " <basename>"
    FileSystemDirectory → SyntaxNode  " <dirname>"  (children indented 2)

The directory printer places a name leaf as children[1] and wraps all
recursively-projected element outputs in a body SyntaxNode (indentation=2)
as children[2], mirroring the Lisp file-system-to-syntax/indentation layout.

When the downstream `SyntaxToText` is configured with expand/collapse markers,
pass `marker_eligible = filesystem_marker_eligible` so the fold marker lands on
the directory header node (the name line) and not on the indented body wrapper.
"""
module FileSystemToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..FileSystemModule: FileSystemDocument, FileSystemFile, FileSystemDirectory
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_black, color_default, color_solarized_blue, color_solarized_red
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, ProjectionReference, append_reference
import ..PrinterContextModule: child_context
export FileSystemFileToSyntaxLeaf, FileSystemDirectoryToSyntaxNode, FileSystemToSyntax,
       filesystem_marker_eligible

# ── FileSystemFileToSyntaxLeaf ────────────────────────────────────────────────

struct FileSystemFileToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
FileSystemFileToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_blue) =
    FileSystemFileToSyntaxLeaf(font, color)

function projection_print(p::FileSystemFileToSyntaxLeaf, recursion, f::FileSystemFile, ctx)
    SimpleIoMap(p, f, SyntaxLeaf(
        TextString("", p.font, color_default),
        TextString("", p.font, color_default),
        TextString(() -> " " * basename(f.pathname), p.font, p.color),
        f.selection))
end

# ── FileSystemDirectoryToSyntaxNode ───────────────────────────────────────────
#
# Output shape:
#   SyntaxNode(open="", close="", sep="", indentation=0):
#     children[1] = SyntaxLeaf(" <dirname>")          ← name leaf
#     children[2] = SyntaxNode(indentation=2):         ← body node
#                     children[1..n] = projected element outputs
#
# Selection mapping (filesystem domain → syntax domain):
#   .elements[i] + rest  →  .children[2].children[i] + child_sel

struct FileSystemDirectoryToSyntaxNode <: Projection
    name_font::StyleFont
    name_color::StyleColor
end
FileSystemDirectoryToSyntaxNode(; name_font=font_ubuntu_monospace_bold_24, name_color=color_solarized_red) =
    FileSystemDirectoryToSyntaxNode(name_font, name_color)


function projection_print(p::FileSystemDirectoryToSyntaxNode, recursion, d::FileSystemDirectory, ctx)
    child_iomaps = Cell(() -> [projection_print(recursion, recursion, elem,
                                   child_context(ctx, FieldReference("elements"), ElementReference(i)))
                               for (i, elem) in enumerate(d)])

    name_leaf = SyntaxLeaf(
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        TextString(() -> " " * _dir_name(d.pathname), p.name_font, p.name_color),
        d.selection)

    body_node = SyntaxNode(
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]]),
        2,
        Cell(false),
        Cell(nothing))

    sel = Cell(() -> begin
        path = d.selection
        path isa ConcreteReferencePath || return nothing
        h = path.head
        if h isa FieldReference && h.name == "elements"
            rest = path.tail
            rest isa ConcreteReferencePath || return nothing
            h2 = rest.head
            h2 isa RangeReference || return nothing
            child_i = h2.start + 1
            iomaps = child_iomaps[]
            child_i > length(iomaps) && return nothing
            child_sel = iomaps[child_i].output.selection
            child_sel === nothing && return nothing
            body_sel = ConcreteReferencePath(FieldReference("children"),
                           ConcreteReferencePath(ElementReference(child_i), child_sel))
            return ConcreteReferencePath(FieldReference("children"),
                       ConcreteReferencePath(ElementReference(2), body_sel))
        elseif h isa ProjectionReference
            return path
        end
        return nothing
    end)

    node = SyntaxNode(
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        TextString("", p.name_font, color_default),
        CellVector(Cell[Cell(name_leaf), Cell(body_node)]),
        0,
        Cell(false),
        sel)

    ChildrenIoMap(p, d, node, child_iomaps)
end

# ── Marker eligibility ──────────────────────────────────────────────────────────
#
# `SyntaxNodeToText`'s default rule marks every node with children. A directory
# is projected as a header node (the name leaf, at indentation 0) wrapping an
# indented body node (indentation 2) that holds the entries — so the default
# rule would mark BOTH, producing a stray marker on the indented block. This
# predicate restricts the marker to a non-empty directory header node:
#
#   • indentation == 0          → the header node, not the indented body wrapper
#   • children[2] is the body   → directory shape (name leaf + body node)
#   • body has children         → non-empty: there is something to fold
#
"""
    filesystem_marker_eligible(node::SyntaxNode) -> Bool

Predicate for `SyntaxToText(marker_eligible = …)` so the expand/collapse marker
lands on a non-empty directory header node and never on its indented body
wrapper. See [`FileSystemDirectoryToSyntaxNode`](@ref).
"""
function filesystem_marker_eligible(node::SyntaxNode)
    node.indentation == 0 || return false
    children = node.children
    length(children) >= 2 || return false
    body = children[2]
    body isa SyntaxNode && length(body.children) > 0
end

# ── Utility ───────────────────────────────────────────────────────────────────

function _dir_name(pathname::AbstractString)
    p = rstrip(pathname, '/')
    isempty(p) && return "/"
    basename(p)
end

# ── Compound constructor ──────────────────────────────────────────────────────

function FileSystemToSyntax()
    TypeDispatchingProjection(
        FileSystemFile      => FileSystemFileToSyntaxLeaf(),
        FileSystemDirectory => FileSystemDirectoryToSyntaxNode(),
    )
end

end # module
