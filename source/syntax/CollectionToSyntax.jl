# Fragment of `SyntaxModule`.
#
# Collection → Syntax projection. Handles `CellVector` and `ListNode`
# as top-level collection documents, mapping each element through recursion.
#
# - `CellVector` → `SyntaxNode` with `[`, `]` delimiters and eager children.
# - `ListNode`   → `ListNode(projected)` preserving lazy structure (no wrapping
#    delimiters for infinite lists).
# ── CollectionCellVectorToSyntax ─────────────────────────────────────────────

@projection struct CollectionCellVectorToSyntax
    delim::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
    sep::ImmutableCell{StyleText}   = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

function map_reference_forward(p::CollectionCellVectorToSyntax, iomap::ChildrenIoMap, reference)
    reference === nothing && return nothing
    core = reference
    core isa EmptyReference && return EmptyReference()
    if core isa ConcreteReference
        # A projection-introduced position (structural delimiter) was encoded as
        # proj(p, {flat}) by the reader.  Keep it wrapped so that
        # SyntaxCompoundToText._syntax_to_flat can extract the flat position via its
        # `h isa ProjectionReferenceStep` branch — same pattern as JsonToSyntax's
        # `_node_forward` which also returns the wrapped reference unchanged.
        if is_introduced_reference(core, p)
            return reference
        end
        # Structural child path: [j].rest → .children[j-1].rest (SyntaxNode domain).
        # ElementReferenceStep(j) is RangeReferenceStep(j-1, j); start+1 recovers the
        # 1-based child index.
        h = core.head
        if h isa RangeReferenceStep && is_element_reference_step(h)
            j = h.start + 1  # 1-based child index
            1 <= j <= length(iomap.input) || return nothing
            child_iomaps_vec = iomap.child_iomaps
            1 <= j <= length(child_iomaps_vec) || return nothing
            child = child_iomaps_vec[j]
            inner = map_reference_forward(child.projection, child, core.tail)
            inner === nothing && return nothing
            return ConcreteReference(FieldReferenceStep("children"),
                       ConcreteReference(RangeReferenceStep(j - 1, j - 1), inner))
        end
    end
    nothing
end

function map_reference_backward(::CollectionCellVectorToSyntax, iomap, reference)
    return nothing
end

function print_document(p::CollectionCellVectorToSyntax, recursion, cv::CellVector, ctx)
    child_iomaps = Cell(@computation([print_child(recursion, x,
                                  make_child_context(ctx, ElementReferenceStep(i)))
                               for (i, x) in enumerate(cv)]))
    # Wire the output SyntaxNode's selection cell to forward-project the input
    # CellVector's selection.  The iomap_cell trick (same as DbCatalogToSyntax)
    # avoids a forward reference: we build the iomap after the node, then fill in
    # the cell so the lazy sel thunk closes over a valid iomap.
    iomap_cell = Cell(nothing)
    sel = Cell(@computation begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = cv.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)
    node = SyntaxNode(
        CellVector(@computation SyntaxDocument[im.output for im in child_iomaps[]]);
        open=TextString("[", p.delim),
        close=TextString("]", p.delim),
        sep=TextString(", ", p.sep),
        indentation=1,
        selection=sel)
    iomap = ChildrenIoMap(p, cv, node, child_iomaps)
    iomap_cell[] = iomap
    iomap
end

# Maps a SyntaxNode path (children[i].rest) back to the CellVector domain.
# Returns ConcreteReference(ElementReferenceStep(child_i), rest) or nothing.
function _translate_collection_path(cv::CellVector, path::Reference)
    path = path
    path isa ConcreteReference || return nothing
    h = path.head
    h isa FieldReferenceStep && h.name == "children" || return nothing
    rest0 = path.tail
    rest0 isa ConcreteReference || return nothing
    h2 = rest0.head
    h2 isa RangeReferenceStep || return nothing
    child_i = h2.start + 1
    1 <= child_i <= length(cv) || return nothing
    ConcreteReference(ElementReferenceStep(child_i), rest0.tail)
end

function read_intent(p::CollectionCellVectorToSyntax,
                          iomap::ChildrenIoMap,
                          op::ReplaceSelectionOperation)
    result = _translate_collection_path(iomap.input::CellVector, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(
        make_introduced_reference(p, iomap.input, ConcreteReference(PositionReferenceStep(flat))))
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
    print_document(::CollectionListNodeToSyntax, recursion, ln::ListNode, ctx)

Maps each element in the `ListNode` through `recursion` lazily.
The output is a `ListNode(projected)` preserving the lazy structure.
"""
function print_document(p::CollectionListNodeToSyntax, recursion, ln::ListNode, ctx)
    out_head = _map_listnode(recursion, ln, ctx, 1)
    SimpleIoMap(p, ln, out_head)
end

function _map_listnode(recursion, input_node::ListNode, ctx, index::Int)
    child_ctx = make_child_context(ctx, ElementReferenceStep(index))
    child_iomap = print_child(recursion, input_node.value, child_ctx)
    out_node = ListNode(child_iomap.output)

    # Lazy next
    set_cell_computation!(getfield(out_node, :next), () -> begin
        input_next = input_node.next
        input_next === nothing && return nothing
        next_out = _map_listnode(recursion, input_next, ctx, index + 1)
        set_cell_value!(getfield(next_out, :prev), out_node)
        next_out
    end)

    # Lazy prev
    set_cell_computation!(getfield(out_node, :prev), () -> begin
        input_prev = input_node.prev
        input_prev === nothing && return nothing
        prev_out = _map_listnode(recursion, input_prev, ctx, index - 1)
        set_cell_value!(getfield(prev_out, :next), out_node)
        prev_out
    end)

    out_node
end

# ── CollectionToSyntax (composite) ───────────────────────────────────────────


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
