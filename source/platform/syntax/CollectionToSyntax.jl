# Fragment of `SyntaxModule`.
#
# Collection → Syntax projection. Handles `CellVector` and `ListNode`
# as top-level collection documents, mapping each element through recursion.
#
# - `CellVector` → `SyntaxNode` with `[`, `]` delimiters and eager children.
# - `ListNode`   → `ListNode(projected)` preserving lazy structure (no wrapping
#    delimiters for infinite lists).
# ── CollectionCellVectorToSyntax ─────────────────────────────────────────────

@projection UntrackedCell struct CollectionCellVectorToSyntax
    delim::StyleText
    sep::StyleText
end

CollectionCellVectorToSyntax(; theme = nothing,
                             delim = get_syntax_style(theme, :delimiter_text),
                             sep = get_syntax_style(theme, :separator_text)) =
    CollectionCellVectorToSyntax(delim, sep)

# A bracket, a separator or the layout of the array is a part that this projection
# printed: the backward map names it by the projection's own introduced step, which
# holds its path in the syntax node, and the forward map answers that path.
function map_reference_forward(p::CollectionCellVectorToSyntax, iomap::ChildrenIoMap, reference)
    reference === nothing && return nothing
    @reference_case reference begin
        ∅ => EmptyReference()
        proj(^(p), inner) => inner
        [j].rest... => begin
            1 <= j <= min(length(iomap.input), length(iomap.child_iomaps)) || return nothing
            child = iomap.child_iomaps[j]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            ConcreteReference(FieldReferenceStep("children"),
                ConcreteReference(RangeReferenceStep(j - 1, j - 1), inner))
        end
    end
end

function map_reference_backward(p::CollectionCellVectorToSyntax, iomap::ChildrenIoMap, reference)
    reference === nothing && return nothing
    @reference_case reference begin
        ∅ => EmptyReference()
        children{s:_}.rest... => begin
            j = s + 1
            1 <= j <= min(length(iomap.input), length(iomap.child_iomaps)) ||
                return make_introduced_reference(p, iomap, reference)
            child = iomap.child_iomaps[j]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            ConcreteReference(ElementReferenceStep(j), inner)
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
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
    paths = make_output_path_cells(cv, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)
    node = SyntaxNode(
        CellVector(@computation SyntaxDocument[im.output for im in child_iomaps[]]);
        open=TextString("[", p.delim),
        close=TextString("]", p.delim),
        sep=TextString(", ", p.sep),
        indentation=1,
        paths...)
    iomap = ChildrenIoMap(p, cv, node, child_iomaps)
    iomap_cell[] = iomap
    iomap
end

function read_intent(p::CollectionCellVectorToSyntax, iomap::ChildrenIoMap,
                     op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

# ── CollectionListNodeToSyntax ───────────────────────────────────────────────

struct CollectionListNodeToSyntax <: Projection end

# The IO map of a lazy list: the IO map of each element that the printer printed,
# by the index of the element from the head, as `getindex` of a `ListNode` counts
# (1 is the head, 0 the element before it).
@iomap struct CollectionListNodeToSyntaxIoMap
    projection::Any
    input::ListNode
    output::ListNode
    element_iomaps::Dict{Int, Any}
end

# A part of element `k` maps to element `k` of the output list, which is the image
# of the element, followed by the forward map of the element. The index counts
# from the head in both lists, so an element that the printer did not reach yet
# maps too: the output list is read up to it, which prints it.
function map_reference_forward(::CollectionListNodeToSyntax, iomap::CollectionListNodeToSyntaxIoMap, reference)
    reference isa EmptyReference && return EmptyReference()
    reference isa ConcreteReference || return nothing
    step = get_reference_head(reference)
    (step isa ARangeReferenceStep && is_element_reference_step(step)) || return nothing
    index = step.start + 1
    element = ElementReferenceStep(index)
    rest = get_reference_tail(reference)
    rest isa EmptyReference && return ConcreteReference(element, EmptyReference())
    child = _find_element_iomap(iomap, index)
    child === nothing && return nothing
    inner = map_reference_forward(child.projection, child, rest)
    inner === nothing ? nothing : ConcreteReference(element, inner)
end

function map_reference_backward(::CollectionListNodeToSyntax, iomap, reference)
    return nothing
end

# The IO map of element `index`, or `nothing` when the list has no such element.
function _find_element_iomap(iomap::CollectionListNodeToSyntaxIoMap, index::Int)
    element_iomaps = iomap.element_iomaps
    haskey(element_iomaps, index) && return element_iomaps[index]
    find_list_node(iomap.output, index) === nothing && return nothing
    get(element_iomaps, index, nothing)
end

"""
    print_document(::CollectionListNodeToSyntax, recursion, ln::ListNode, ctx)

Maps each element in the `ListNode` through `recursion` lazily.
The output is a `ListNode(projected)` preserving the lazy structure.
"""
function print_document(p::CollectionListNodeToSyntax, recursion, ln::ListNode, ctx)
    element_iomaps = Dict{Int, Any}()
    out_head = _map_listnode(recursion, ln, ctx, 1, element_iomaps)
    CollectionListNodeToSyntaxIoMap(p, ln, out_head, element_iomaps)
end

function _map_listnode(recursion, input_node::ListNode, ctx, index::Int, element_iomaps::Dict{Int, Any})
    child_ctx = make_child_context(ctx, ElementReferenceStep(index))
    child_iomap = print_child(recursion, input_node.value, child_ctx)
    element_iomaps[index] = child_iomap
    out_node = ListNode(child_iomap.output)

    # Lazy next
    set_cell_computation!(getfield(out_node, :next), () -> begin
        input_next = input_node.next
        input_next === nothing && return nothing
        next_out = _map_listnode(recursion, input_next, ctx, index + 1, element_iomaps)
        set_cell_value!(getfield(next_out, :prev), out_node)
        next_out
    end)

    # Lazy prev
    set_cell_computation!(getfield(out_node, :prev), () -> begin
        input_prev = input_node.prev
        input_prev === nothing && return nothing
        prev_out = _map_listnode(recursion, input_prev, ctx, index - 1, element_iomaps)
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
function CollectionToSyntax(; theme = nothing)
    TypeDispatchingProjection(
        CellVector => CollectionCellVectorToSyntax(; theme),
        ListNode   => CollectionListNodeToSyntax(),
    )
end
