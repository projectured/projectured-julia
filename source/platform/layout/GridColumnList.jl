# Fragment of `LayoutModule`.
#
# The grid of a list whose columns are a list too: `children` is a `ListNode`
# of rows, each row is a `ListNode` of the documents of its cells, and
# `column_policies` is a `ListNode` of the policy of each column, anchored at
# the same column as the cells of every row. The grid draws the rows and the
# columns that a viewport shows and no others.
#
# **The heads are the anchors.** `children[k][c]` names the cell in the column
# `c` counted from the head column, of the row `k` counted from the head row,
# and a column before the head column has an index of 0 or less, as a row
# before the head row has.
#
# **What it needs.** Every column is `Fixed`, and so is every row: a width of a
# column that its cells decided, or a height of a row that its cells decided,
# would change as a viewport reaches more cells. A weight has no count to
# divide by.
#
# **What the grid places.** Two lists, one level down: the rows, down, and the
# columns, to the side, as canvases as wide as the columns that draw nothing.
# A `WidgetScrollPane` finds each list by its axis and stops at its ends. A
# row draws its cells as a list to the side, each cell at the place of its
# column: the node of cell `c` pairs with the node of column `c`, so a walk of
# the cells walks the columns with them.

# The width of a column from its policy, which must be `Fixed`.
function _get_column_list_width(policy)
    (policy isa SizePolicy && policy.preferred !== nothing &&
     (policy.weight === nothing || policy.weight == 0)) ||
        error("GridLayout: a grid whose columns are a list needs every column Fixed, not ",
              repr(policy))
    Int(policy.preferred)
end

# The canvas node of column `k`, placed after the column before it or before
# the column after it; the head column is at 0. Its neighbours are built when
# first read, from the neighbours of `policy_node`, and of `align_node`, the
# node of the alignment of the column when the alignments are a list too,
# which `aligns` keeps by the index of the column.
function _make_grid_column_node(hgap::Cell, k::Int, policy_node::ListNode, align_node,
                                aligns::Dict{Int,Any}, before, after)
    aligns[k] = align_node isa ListNode ? align_node : nothing
    width = Cell(@computation Int32(_get_column_list_width(policy_node.value)))
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), width, Cell(Int32(0)), CellVector(),
                            layout_none, true, Cell(nothing))
    if before !== nothing
        before_canvas = before.value
        set_cell_computation!(getfield(canvas, :x),
            () -> Int32(Int(before_canvas.x) + Int(before_canvas.w) + Int(hgap[])))
    elseif after !== nothing
        after_canvas = after.value
        set_cell_computation!(getfield(canvas, :x),
            () -> Int32(Int(after_canvas.x) - Int(canvas.w) - Int(hgap[])))
    end
    node = ListNode(canvas)
    set_cell_computation!(getfield(node, :next), () -> begin
        following = policy_node.next
        following === nothing && return nothing
        next_node = _make_grid_column_node(hgap, k + 1, following,
                                           align_node isa ListNode ? align_node.next : nothing,
                                           aligns, node, nothing)
        set_cell_value!(getfield(next_node, :prev), node)
        next_node
    end)
    set_cell_computation!(getfield(node, :prev), () -> begin
        preceding = policy_node.prev
        preceding === nothing && return nothing
        prev_node = _make_grid_column_node(hgap, k - 1, preceding,
                                           align_node isa ListNode ? align_node.prev : nothing,
                                           aligns, nothing, node)
        set_cell_value!(getfield(prev_node, :next), node)
        prev_node
    end)
    node
end

# Whether the one entry of `offers`, which names every column or every row of
# a grid whose columns are a list, keeps the extent from the cells.
_is_offer_withheld(offers) = offers isa AbstractVector && !isempty(offers) && first(offers) === false

# The node of cell `c` of row `k`: the document of `cell_node` printed through
# the recursion and clipped to the slot of the column of `column_node`. A cell
# with no document, or with no graphics, is an empty canvas at its column, so
# the renderer still walks past it. The drawn cells are kept in `cells` by
# their index from the head column.
function _make_grid_cell_node(recursion, doc, ctx, state::GridListState, k::Int, c::Int,
                              cell_node::ListNode, column_node::ListNode, height::Cell,
                              cells::Dict{Int,Any}, before, after)
    column = column_node.value
    document = cell_node.value
    cctx = make_child_context(ctx, doc, (@reference_step children), (@reference_step [k]),
                              (@reference_step [c]))
    if cctx !== nothing
        cctx = _is_offer_withheld(doc.column_offers) ? with_free_axis(cctx, :x) :
                   with_exact_size(cctx; width = getfield(column, :w))
        cctx = _is_offer_withheld(doc.row_offers) ? with_free_axis(cctx, :y) :
                   with_exact_size(cctx; height = height)
    end
    cim = document === nothing ? nothing : _recurse_child(recursion, document, cctx)
    align_node = get(state.column_aligns, c, nothing)
    halign = align_node isa ListNode ? align_node.value : doc.horizontal_align
    valign = doc.vertical_align
    x_cell = Cell(@computation Int32(Int(column.x) + _get_layout_list_align_offset(
        Symbol(halign), Int(column.w), cim === nothing ? 0 : _child_w(cim))))
    y_cell = Cell(@computation Int32(_get_layout_list_align_offset(
        Symbol(valign), Int(height[]), cim === nothing ? 0 : _child_h(cim))))
    child = cim === nothing ? nothing : cim.output
    element = if child isa GraphicsDocument
        cells[c] = (x_cell, y_cell, cim)
        clip_child_to_slot(child, cim; x_cell, y_cell, slot_x = getfield(column, :x),
                           slot_y = Cell(Int32(0)), slot_w = getfield(column, :w), slot_h = height,
                           clip_x = true, clip_y = true)
    else
        cells[c] = (x_cell, y_cell, nothing)
        GraphicsCanvas(getfield(column, :x), Cell(Int32(0)), getfield(column, :w), height,
                       CellVector(), layout_none, true, Cell(nothing))
    end
    node = ListNode(element)
    set_cell_computation!(getfield(node, :next), () -> begin
        (following, following_column) = (cell_node.next, column_node.next)
        (following === nothing || following_column === nothing) && return nothing
        next_node = _make_grid_cell_node(recursion, doc, ctx, state, k, c + 1, following,
                                         following_column, height, cells, node, nothing)
        set_cell_value!(getfield(next_node, :prev), node)
        next_node
    end)
    set_cell_computation!(getfield(node, :prev), () -> begin
        (preceding, preceding_column) = (cell_node.prev, column_node.prev)
        (preceding === nothing || preceding_column === nothing) && return nothing
        prev_node = _make_grid_cell_node(recursion, doc, ctx, state, k, c - 1, preceding,
                                         preceding_column, height, cells, nothing, node)
        set_cell_value!(getfield(prev_node, :next), node)
        prev_node
    end)
    node
end

# One row whose cells are a list: a canvas as tall as the row, whose elements
# are the list of its cells from the head column. The canvas's `y` is set by
# the node that links it.
function _make_grid_column_list_row(recursion, doc, ctx, state::GridListState, k::Int, row)
    height = Cell(@computation Int32(doc.row_policy.preferred))
    cells = Dict{Int,Any}()
    elements = Cell(@computation begin
        column = state.column_head[]
        (row isa ListNode && column isa ListNode) || return CellVector()
        _make_grid_cell_node(recursion, doc, ctx, state, k, 1, row, column, height, cells,
                             nothing, nothing)
    end)
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), height, elements,
                            layout_horizontal, false, Cell(nothing))
    (canvas, cells, height)
end

function _print_grid_column_list(p, recursion, doc, ctx)
    # The kind of the row policy is read with no dependency, and its height in
    # the cell of each row, so a height that a caller computes follows.
    row_policy = peek(getfield(doc, :row_policy))
    (row_policy isa SizePolicy && row_policy.preferred !== nothing &&
     (row_policy.weight === nothing || row_policy.weight == 0)) ||
        error("GridLayout: a grid whose columns are a list needs its rows Fixed, not ",
              repr(row_policy))
    hgap = getfield(doc, :horizontal_gap)
    vgap = getfield(doc, :vertical_gap)
    state = GridListState(0, Dict{Int,Any}(), Cell(nothing), Cell(nothing), Dict{Int,Any}())
    # A new head in `column_policies` builds the columns again, and so does a
    # new head in `children` build the rows again. `column_align` is a list
    # anchored with the columns, or one alignment for every column.
    set_cell_computation!(state.column_head, () -> begin
        policies = doc.column_policies
        empty!(state.column_aligns)
        policies isa ListNode ?
            _make_grid_column_node(hgap, 1, policies, doc.column_align, state.column_aligns,
                                   nothing, nothing) :
            nothing
    end)
    set_cell_computation!(state.head, () -> begin
        list = doc.children
        empty!(state.built)
        list isa ListNode ?
            _make_grid_list_node(recursion, doc, ctx, state, Cell[], Cell[], Cell(Int32(0)), 1, list,
                                 nothing, nothing) :
            nothing
    end)
    rows = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)),
                          Cell(@computation (head = state.head[]; head === nothing ? CellVector() : head)),
                          layout_vertical, false, Cell(nothing))
    columns = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)),
                             Cell(@computation (head = state.column_head[];
                                                head === nothing ? CellVector() : head)),
                             layout_horizontal, false, Cell(nothing))
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)),
                            CellVector(Cell[Cell(rows), Cell(columns)]), layout_none, true, Cell(nothing))
    GridLayoutListIoMap(p, doc, canvas, state, Cell[], Cell[], hgap, vgap, Cell(Int32(0)))
end

# ── The columns the walk has built ───────────────────────────────────────────

"""
    get_grid_list_column_head(iomap::GridLayoutListIoMap) -> ListNode or nothing

The node of the head column of a grid whose columns are a list, or `nothing`
for a grid whose columns are not a list or that has no column. Its values are
canvases as wide as the columns, at their places, so a container walks it to
draw graphics beside the columns that a viewport shows. The read is a
dependency.
"""
get_grid_list_column_head(iomap::GridLayoutListIoMap) =
    iomap.state.column_head === nothing ? nothing : iomap.state.column_head[]
get_grid_list_column_head(iomap::IoMap) =
    get_grid_list_column_head(_get_grid_list_iomap(iomap))

# The index of the column under `x`, counted from the head column, walking from
# the head toward it, or `nothing` in a gap or past an end.
function _find_grid_list_column_node_at(state::GridListState, x::Int)
    node = state.column_head[]
    node isa ListNode || return nothing
    c = 1
    while x < Int(node.value.x)
        node = node.prev
        node === nothing && return nothing
        c -= 1
    end
    while x >= Int(node.value.x) + Int(node.value.w)
        following = node.next
        following === nothing && return nothing
        x < Int(following.value.x) && return nothing       # in the gap
        node = following
        c += 1
    end
    c
end

"""
    find_grid_list_cell(iomap::GridLayoutListIoMap, k, c) -> (x, y, iomap) or nothing

The cell in row `k` and column `c` of a grid of a list, each counted from its
head, walked to and built on the way: the `x` of the cell in the grid, its `y`
in the canvas of the row, and its IO map, which is `nothing` for an empty cell.
`nothing` when a list ends before it.
"""
find_grid_list_cell(iomap::IoMap, k::Integer, c::Integer) =
    find_grid_list_cell(_get_grid_list_iomap(iomap), k, c)

function find_grid_list_cell(iomap::GridLayoutListIoMap, k::Integer, c::Integer)
    state = iomap.state
    found = _find_grid_list_row(state, Int(k))
    found === nothing && return nothing
    canvas, entries, _ = found
    if state.column_head === nothing
        1 <= c <= length(entries) || return nothing
        return entries[c]
    end
    node = canvas.elements
    node isa ListNode || return nothing
    for _ in 1:abs(c - 1)
        node = c > 1 ? node.next : node.prev
        node === nothing && return nothing
    end
    get(entries, Int(c), nothing)
end
