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
import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read, map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..FileSystemModule: FileSystemDocument, FileSystemFile, FileSystemDirectory
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_black, color_default, color_solarized_blue, color_solarized_red
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, ProjectionReference, append_reference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation
import ..PrinterContextModule: child_context
export FileSystemFileToSyntaxLeaf, FileSystemDirectoryToSyntaxNode, FileSystemToSyntax,
       filesystem_marker_eligible

# ── FileSystemFileToSyntaxLeaf ────────────────────────────────────────────────

@projection struct FileSystemFileToSyntaxLeaf <: Projection
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_blue)
end

function projection_print(p::FileSystemFileToSyntaxLeaf, recursion, f::FileSystemFile, ctx)
    SimpleIoMap(p, f, SyntaxLeaf(
        TextString(() -> " " * basename(f.pathname), p.style);
        selection=f.selection))
end

# The name leaf shares the file's selection cell, so a file's input reference and
# its leaf output reference are the same path — the mappers are the identity.
map_reference_forward(::FileSystemFileToSyntaxLeaf, iomap::SimpleIoMap, reference) = reference
map_reference_backward(::FileSystemFileToSyntaxLeaf, iomap::SimpleIoMap, reference) = reference

function projection_read(p::FileSystemFileToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing && return nothing
    ReplaceSelectionOperation(result)
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

@projection struct FileSystemDirectoryToSyntaxNode <: Projection
    name::StyleText = StyleText(font_ubuntu_monospace_bold_24, color_solarized_red)
end


function projection_print(p::FileSystemDirectoryToSyntaxNode, recursion, d::FileSystemDirectory, ctx)
    child_iomaps = Cell(() -> [projection_printer_recurse(recursion, elem,
                                   child_context(ctx, FieldReference("elements"), ElementReference(i)))
                               for (i, elem) in enumerate(d.elements)])

    name_leaf = SyntaxLeaf(
        TextString(() -> " " * _dir_name(d.pathname), p.name);
        selection=d.selection)

    body_node = SyntaxNode(
        CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]]);
        indentation=2)

    # Wire the output selection canonically: map d.selection forward through this
    # projection's own map_reference_forward (School A — delegate the tail through
    # child_iomaps). The not-yet-built iomap is supplied via the deferred-iomap
    # trick (iomap_cell), as in JsonArrayToSyntaxNode / CopyingProjection.
    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = d.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(Cell[Cell(name_leaf), Cell(body_node)]);
        selection=sel)

    iomap = ChildrenIoMap(p, d, node, child_iomaps)
    iomap_cell[] = iomap
    return iomap
end

# Selection mapping (FileSystemDirectory → SyntaxNode):
#   .elements[i].rest  →  .children[2].children[i].<child-mapped rest>
# where children[1] is the name leaf and children[2] the indented body node whose
# children are the projected elements. Both directions delegate the tail through
# the stored child iomaps (School A); the two mappers are the single source of
# truth, reused by the printer's selection cell and the reader below.
function map_reference_forward(p::FileSystemDirectoryToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::FileSystemDirectory.elements{s:e}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children[2].children[child_i].^(inner)
        end
    end
end

function map_reference_backward(p::FileSystemDirectoryToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::FileSystemDirectory
        ::SyntaxNode.children[2].children{s:e}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::FileSystemDirectory.elements[child_i].^(inner)
        end
    end
end

function projection_read(p::FileSystemDirectoryToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing && return nothing
    ReplaceSelectionOperation(result)
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
