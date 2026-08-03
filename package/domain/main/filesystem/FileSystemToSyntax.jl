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

import ..CellModule: Cell, ComputedCell
import ..CollectionModule: CellVector, ComputedCellVector
import ..ProjectionApiModule: print_document, print_child, read_intent, map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..FileSystemModule: FileSystemDocument, FileSystemFile, FileSystemDirectory
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20
import ..ColorModule: StyleColor, color_black, color_default, color_solarized_blue, color_solarized_red
import ..StyleTextModule: StyleText, DStyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReference, ElementReferenceStep, PositionReferenceStep, RangeReferenceStep, FieldReferenceStep, extend_reference
import ..ProjectionReferenceStepModule: ProjectionReferenceStep, is_introduced_reference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
import ..PrinterContextModule: make_child_context
export FileSystemFileToSyntaxLeaf, FileSystemDirectoryToSyntaxNode, FileSystemToSyntax,
       filesystem_marker_eligible

# ── FileSystemFileToSyntaxLeaf ────────────────────────────────────────────────

@projection struct FileSystemFileToSyntaxLeaf
    style::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
end

function print_document(p::FileSystemFileToSyntaxLeaf, recursion, f::FileSystemFile, ctx)
    # The leaf renders the file's basename — introduced text with no input field to
    # bind (the value is derived from `.pathname`, not stored). A whole-file selection
    # (∅) shares the file's path unchanged, but a *caret* on the introduced value has
    # no file-domain pre-image, so it is carried as a projection-introduced reference
    # (`proj(p, …)`). The leaf therefore cannot share `f.selection` verbatim; it gets
    # its own cell that maps the file's selection forward (School A / deferred-iomap
    # trick, as in FileSystemDirectoryToSyntaxNode), unwrapping our introduced caret
    # back into the leaf's own `.value{k}` span.
    iomap_cell = Cell(nothing)
    sel = ComputedCell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = f.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)
    leaf = SyntaxLeaf(TextString(() -> " " * basename(f.pathname), p.style); selection=sel)
    iomap = SimpleIoMap(p, f, leaf)
    iomap_cell[] = iomap
    return iomap
end

# Selection mapping (FileSystemFile ↔ SyntaxLeaf):
#   ∅ / whole-file        ↔  the whole leaf                       (identity — same path)
#   caret on the value    →  proj(p, ::SyntaxLeaf.value{k})       (introduced: no pre-image)
# The value span is projection-introduced (derived basename), so a caret there names
# the whole file (`is_introduced_reference` / `named_node_reference`) while carrying a
# bounded position for rendering and navigation — the established introduced-token
# pattern (cf. XmlElementToSyntaxNode).
function map_reference_forward(p::FileSystemFileToSyntaxLeaf, iomap::SimpleIoMap, reference)
    is_introduced_reference(reference, p) && return reference.head.output_path
    reference
end

function map_reference_backward(p::FileSystemFileToSyntaxLeaf, iomap::SimpleIoMap, reference)
    is_introduced_reference(reference, p) && return reference
    caret = @reference_case reference begin
        ::SyntaxLeaf.value{k} => reference
    end
    caret === nothing && return reference
    ConcreteReference(ProjectionReferenceStep(p, caret))
end

function read_intent(p::FileSystemFileToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing && return nothing
    ReplaceSelectionOperation(result)
end

# The basename is derived display text, not an editable field, so a text-range
# edit (backspace / delete / type-in) is declined — the leaf is navigable but
# read-only. This must name the operation type exactly (not a catch-all `op`),
# because `ReaderDefaults`' `read_intent(::Projection, iomap, ::ReplaceStringRangeOperation)`
# is equally specific on the operation; a bare `op` would be ambiguous with it.
# The `ReplaceSelectionOperation` method above still maps carets, so navigation works.
read_intent(::FileSystemFileToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceStringRangeOperation) = nothing

# ── FileSystemDirectoryToSyntaxNode ───────────────────────────────────────────
#
# Output shape:
#   SyntaxNode (no delimiters — a bare, foldable node):
#     children[1] = SyntaxLeaf(" <dirname>")          ← name leaf
#     children[2] = SyntaxNode(indentation=2):         ← body node
#                     children[1..n] = projected element outputs
#
# Selection mapping (filesystem domain → syntax domain):
#   .elements[i] + rest  →  .children[2].children[i] + child_sel

@projection struct FileSystemDirectoryToSyntaxNode
    name::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_red)
end


function print_document(p::FileSystemDirectoryToSyntaxNode, recursion, d::FileSystemDirectory, ctx)
    child_iomaps = ComputedCell(() -> [print_child(recursion, elem,
                                   make_child_context(ctx, FieldReferenceStep("elements"), ElementReferenceStep(i)))
                               for (i, elem) in enumerate(d.elements)])

    name_leaf = SyntaxLeaf(
        TextString(() -> " " * _dir_name(d.pathname), p.name);
        selection=d.selection)

    body_node = SyntaxNode(
        ComputedCellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]]);
        indentation=2)

    # Wire the output selection canonically: map d.selection forward through this
    # projection's own map_reference_forward (School A — delegate the tail through
    # child_iomaps). The not-yet-built iomap is supplied via the deferred-iomap
    # trick (iomap_cell), as in JsonArrayToSyntaxNode / CopyingProjection.
    iomap_cell = Cell(nothing)
    sel = ComputedCell(() -> begin
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
            iomaps = iomap.child_iomaps
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[2]::SyntaxNode.children::CellVector[child_i].^(inner)
        end
    end
end

function map_reference_backward(p::FileSystemDirectoryToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::FileSystemDirectory
        ::SyntaxNode.children[2].children{s:e}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::FileSystemDirectory.elements::CellVector[child_i].^(inner)
        end
    end
end

function read_intent(p::FileSystemDirectoryToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing && return nothing
    ReplaceSelectionOperation(result)
end

# ── Marker eligibility ──────────────────────────────────────────────────────────
#
# `SyntaxCompoundToText`'s default rule marks every node with children. A directory
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
