# Fragment of `LayoutModule`.
#
# The list form of a grid layout: `children` is a `ListNode` of rows, and each
# row is a vector of the documents of its cells, one for each column. The grid
# draws the rows that a viewport shows and no others. `nothing` is a list with
# no rows: the grid is printed in the list form, and draws the rows of a list
# that `children` holds later.
#
# **The head is the anchor**, as in the list form of a linear layout
# (`LayoutList.jl`): `children[k][c]` names the cell in column `c` of the row
# `k` counted from the head, and a row before the head has an index of 0 or
# less.
#
# **What a list needs.** Every column has an extent that no cell decides: a
# `Fixed` policy, or a weight of the extent that the parent offers, because a
# row that is not built can not be measured. A row takes no weight, because a
# weight divides an offered extent by a count and a list has none; a row is
# `Fixed` or as tall as its cells.
#
# **What the grid reports.** Its width, and no height, so it belongs in a
# `WidgetScrollPane`. Its IO map gives the rows it placed and the edges of the
# columns, so a container can draw graphics around the cells: a layout
# positions and draws nothing.

# What the printer of a grid of a list keeps for its readers: the rows built so
# far, by their index from the head, and the canvas lists that it draws from.
mutable struct GridListState
    columns::Int             # the count of the columns, or 0 when they are a list
    built::Dict{Int,Any}     # index from the head => (row canvas, cell entries, row height)
    head::Cell               # the canvas node of the head row, or nothing
    column_head::Union{Nothing,Cell}   # the canvas node of the head column when the columns are a list
    column_aligns::Dict{Int,Any}       # the node of the alignment of each column built, when they are a list
end

"""
    GridLayoutListIoMap

The IO map of a `GridLayout` whose `children` is a list of rows. Beside the
rows that it placed (`state`), it gives the edges and the widths of the
columns as cells, `col_x` and `col_w`, and the width of the grid, so a
container can draw graphics around the cells without the grid drawing any.
"""
@iomap struct GridLayoutListIoMap
    projection::Any
    input::Any
    output::Any
    state::Any
    col_x::Vector{Cell}
    col_w::Vector{Cell}
    horizontal_gap::Cell
    vertical_gap::Cell
    w::Cell
end

# ── What a list needs, said before anything is drawn ─────────────────────────

function _check_grid_list(n::Int, policy_of_column, row_policy, avail_w)
    for c in 1:n
        policy = policy_of_column(c)
        _gl_offers(policy) ||
            error("GridLayout: a grid whose rows are a list needs every column given a width, ",
                  "and column ", c, " is its content")
        weighted = policy.weight !== nothing && policy.weight > 0
        weighted && avail_w === nothing &&
            error("GridLayout: column ", c, " has a weight, and a grid whose rows are a list ",
                  "has no offered width to divide")
    end
    row_policy isa SizePolicy || error("GridLayout: the row policy is a SizePolicy")
    (row_policy.weight !== nothing && row_policy.weight > 0) &&
        error("GridLayout: a weight divides an offered height by a count, and a list of ",
              "rows has none; give the rows Fixed or Content")
    nothing
end

# ── The printer ──────────────────────────────────────────────────────────────

function _print_grid_list(p, recursion, doc, ctx)
    # Policies that are a list make the columns a list too (`GridColumnList.jl`).
    peek(getfield(doc, :column_policies)) isa ListNode &&
        return _print_grid_column_list(p, recursion, doc, ctx)
    n = Int(doc.columns)
    row_policy = doc.row_policy
    # The kind of a column policy is read now, with no dependency, and its
    # numbers in the extent cells, as the eager grid reads them.
    policy_of_column(k::Int) = _gl_policy_at(doc.column_policies, k, doc.column_policy)
    peek_column_policy(k::Int) = _gl_policy_at(peek(getfield(doc, :column_policies)), k,
                                               peek(getfield(doc, :column_policy)))
    avail_w = ctx === nothing ? nothing : get_exact_width(ctx)
    _check_grid_list(n, peek_column_policy, row_policy, avail_w)
    hgap = getfield(doc, :horizontal_gap)
    vgap = getfield(doc, :vertical_gap)
    # Every column is given its extent, so no cell is read to find it.
    no_content = Cell[Cell(0) for _ in 1:n]
    col_extents = _gl_extents_cell(getfield(doc, :columns), policy_of_column, no_content, hgap,
                                   avail_w; reads = k -> false)
    col_w = Cell[_gl_extent_cell(col_extents, k) for k in 1:n]
    col_x = Cell[_gl_col_x_cell(k, col_w, hgap) for k in 1:n]
    total_w = Cell(@computation Int32(sum((Int(col_w[k][])::Int for k in 1:n); init = 0) +
                                      max(0, n - 1) * Int(hgap[])))
    state = GridListState(n, Dict{Int,Any}(), Cell(nothing), nothing, Dict{Int,Any}())
    # A new head in `children` drops every row built and starts again, and a
    # grid whose children are no list draws no rows.
    set_cell_computation!(state.head, () -> begin
        list = doc.children
        empty!(state.built)
        list isa ListNode ?
            _make_grid_list_node(recursion, doc, ctx, state, col_x, col_w, total_w, 1, list,
                                 nothing, nothing) :
            nothing
    end)
    elements = Cell(@computation begin
        head = state.head[]
        head === nothing ? CellVector() : head
    end)
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), total_w, Cell(Int32(0)), elements,
                            layout_vertical, false, Cell(nothing))
    GridLayoutListIoMap(p, doc, canvas, state, col_x, col_w, hgap, vgap, total_w)
end

# One row: its cells printed through the recursion and placed in their columns.
# The canvas's `y` is set by the node that links it, because a row is under the
# row before it or above the row after it, and the head is at zero.
function _make_grid_list_row(recursion, doc, ctx, state::GridListState, col_x, col_w,
                             total_w::Cell, k::Int, row)
    n = state.columns
    row_policy = doc.row_policy
    fixed_h = row_policy.preferred
    column_offers = doc.column_offers
    halign = doc.horizontal_align
    valign = doc.vertical_align
    column_align = doc.column_align
    entries = Any[]
    for c in 1:n
        document = (row !== nothing && 1 <= c <= length(row)) ? row[c] : nothing
        cctx = make_child_context(ctx, doc, (@reference_step children), (@reference_step [k]),
                                  (@reference_step [c]))
        if cctx !== nothing
            withheld = column_offers isa AbstractVector && c <= length(column_offers) &&
                       column_offers[c] === false
            cctx = withheld ? with_free_axis(cctx, :x) :
                              with_exact_size(cctx; width = _gl_int32_cell(col_w[c]))
            cctx = fixed_h === nothing ? with_free_axis(cctx, :y) :
                                         with_exact_size(cctx; height = Cell(Int32(fixed_h)))
        end
        cim = document === nothing ? nothing : _recurse_child(recursion, document, cctx)
        align = _col_align(column_align, c, halign)
        x_cell = Cell(@computation begin
            width = cim === nothing ? 0 : _child_w(cim)
            Int32(Int(col_x[c][]) + _get_layout_list_align_offset(align, Int(col_w[c][]), width))
        end)
        push!(entries, (x_cell, Cell(Int32(0)), cim))
    end
    cims = Any[entry[3] for entry in entries]
    row_h = Cell(@computation Int32(fixed_h !== nothing ? Int(fixed_h) :
        maximum((cim === nothing ? 0 : _child_h(cim) for cim in cims); init = 0)))
    cells = Any[]
    for c in 1:n
        (x_cell, _, cim) = entries[c]
        cim === nothing && continue
        child = cim.output
        child isa GraphicsDocument || continue
        y_cell = Cell(@computation Int32(_get_layout_list_align_offset(
            Symbol(valign), Int(row_h[]), _child_h(cim))))
        push!(cells, clip_child_to_slot(child, cim; x_cell, y_cell,
                                        slot_x = col_x[c], slot_y = Cell(Int32(0)),
                                        slot_w = col_w[c], slot_h = row_h,
                                        clip_x = true, clip_y = fixed_h !== nothing))
        entries[c] = (x_cell, y_cell, cim)
    end
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), total_w, row_h,
                            CellVector(Cell[Cell(e) for e in cells]), layout_none, true,
                            Cell(nothing))
    (canvas, entries, row_h)
end

# The canvas node of row `k`, linked as a node of a linear list is
# (`_make_layout_list_node`).
function _make_grid_list_node(recursion, doc, ctx, state::GridListState, col_x, col_w,
                              total_w::Cell, k::Int, document_node::ListNode, before, after)
    canvas, entries, row_h = state.column_head === nothing ?
        _make_grid_list_row(recursion, doc, ctx, state, col_x, col_w, total_w, k, document_node.value) :
        _make_grid_column_list_row(recursion, doc, ctx, state, k, document_node.value)
    state.built[k] = (canvas, entries, row_h)
    vgap = getfield(doc, :vertical_gap)
    if before !== nothing
        before_canvas = before.value
        set_cell_computation!(getfield(canvas, :y),
            () -> Int32(Int(before_canvas.y) + Int(before_canvas.h) + Int(vgap[])))
    elseif after !== nothing
        after_canvas = after.value
        set_cell_computation!(getfield(canvas, :y),
            () -> Int32(Int(after_canvas.y) - Int(canvas.h) - Int(vgap[])))
    end
    node = ListNode(canvas)
    set_cell_computation!(getfield(node, :next), () -> begin
        following = document_node.next
        following === nothing && return nothing
        next_node = _make_grid_list_node(recursion, doc, ctx, state, col_x, col_w, total_w,
                                         k + 1, following, node, nothing)
        set_cell_value!(getfield(next_node, :prev), node)
        next_node
    end)
    set_cell_computation!(getfield(node, :prev), () -> begin
        preceding = document_node.prev
        preceding === nothing && return nothing
        prev_node = _make_grid_list_node(recursion, doc, ctx, state, col_x, col_w, total_w,
                                         k - 1, preceding, nothing, node)
        set_cell_value!(getfield(prev_node, :next), node)
        prev_node
    end)
    node
end

# ── The rows the walk has built ──────────────────────────────────────────────

"""
    get_grid_list_head(iomap::GridLayoutListIoMap) -> ListNode or nothing

The node of the head row among the rows that a grid of a list placed, or
`nothing` for a grid with no rows. Its values are the canvases of the rows, so a
container walks it to draw graphics around the rows that a viewport shows. The
read is a dependency: a new head in `children` reaches the reader.
"""
get_grid_list_head(iomap::GridLayoutListIoMap) = iomap.state.head[]

# The grid of a list behind a wrapper of its IO map, such as a fault barrier at
# the recursion point that printed the grid.
function _get_grid_list_iomap(iomap::IoMap)
    content = get_content_iomap(iomap)
    content isa GridLayoutListIoMap ||
        throw(ArgumentError("no grid of a list behind a $(typeof(iomap))"))
    content
end

get_grid_list_head(iomap::IoMap) = get_grid_list_head(_get_grid_list_iomap(iomap))

"""
    find_grid_list_row(iomap::GridLayoutListIoMap, k) -> (canvas, entries, height) or nothing

Row `k` of a grid of a list, counted from the head, walked to from the head and
built on the way; `nothing` when the list ends before it. `entries` has one
`(x, y, iomap)` for each column: the `x` of the cell in the grid, its `y` in the
canvas of the row, and its IO map, which is `nothing` for an empty cell. When
the columns are a list, `entries` holds the cells built so far, by their index
from the head column; `find_grid_list_cell` gives any one of them.
"""
find_grid_list_row(iomap::GridLayoutListIoMap, k::Integer) = _find_grid_list_row(iomap.state, Int(k))
find_grid_list_row(iomap::IoMap, k::Integer) = find_grid_list_row(_get_grid_list_iomap(iomap), k)

# Row `k` as `(row canvas, cell entries, row height)`, walked to from the head
# and built on the way, or `nothing` when the list ends before it.
function _find_grid_list_row(state::GridListState, k::Int)
    node = state.head[]
    node isa ListNode || return nothing
    for _ in 1:abs(k - 1)
        node = k >= 1 ? node.next : node.prev
        node === nothing && return nothing
    end
    get(state.built, k, nothing)
end

# The index of the row under `y`, walking from the head toward it, or `nothing`.
function _find_grid_list_row_at(state::GridListState, y::Int)
    node = state.head[]
    node isa ListNode || return nothing
    k = 1
    if y < Int(node.value.y)
        while y < Int(node.value.y)
            node = node.prev
            node === nothing && return nothing
            k -= 1
        end
    else
        while y >= Int(node.value.y) + Int(node.value.h)
            node = node.next
            node === nothing && return nothing
            k += 1
        end
    end
    y >= Int(node.value.y) ? k : nothing
end

# The column under `x`, or `nothing` in a gap or past the last column.
function _find_grid_list_column_at(col_x::Vector{Cell}, col_w::Vector{Cell}, x::Int)
    for c in eachindex(col_x)
        left = Int(col_x[c][])
        left <= x < left + Int(col_w[c][]) && return c
    end
    nothing
end

# ── Reference mapping ────────────────────────────────────────────────────────

# `children[k][c] + rest`, with `k` counted from the head, or `nothing`.
function _split_grid_list_reference(reference)
    k, rest = _split_layout_list_reference(reference)
    k === nothing && return nothing
    (rest isa ConcreteReference && rest.head isa RangeReferenceStep) || return nothing
    (k, rest.head.start + 1, rest.tail)
end

# `children[k][c] + rest` maps to the node that draws the cell: row `k` is node `k`
# of the canvas list, counted from its head. In a row of a vector of columns the
# cell takes a slot among the drawn cells (`make_slot_reference`). A grid whose
# columns are a list draws its rows as the first of its two canvases, and a cell
# is node `c` of its row.
function map_reference_forward(::GridLayoutToGraphicsCanvas, iomap::GridLayoutListIoMap, reference)
    strip_reference_types(reference) isa EmptyReference && return EmptyReference()
    named = _split_grid_list_reference(reference)
    named === nothing && return nothing
    k, c, rest = named
    found = _find_grid_list_row(iomap.state, k)
    found === nothing && return nothing
    cell = find_grid_list_cell(iomap, k, c)
    cell === nothing && return nothing
    cim = cell[3]
    (cim === nothing || !(cim.output isa GraphicsDocument)) && return nothing
    inner = map_reference_forward(cim.projection, cim, rest)
    inner === nothing && return nothing
    if iomap.state.column_head === nothing
        in_row = make_slot_reference(found[1], found[2], c, inner)
        return in_row === nothing ? nothing : _make_list_node_reference(k, in_row)
    end
    in_row = _make_list_cell_reference(found[1], c, inner)
    in_row === nothing ? nothing : _make_wrapped_reference(_make_list_node_reference(k, in_row))
end

# The output reference of cell `c` of a row that is a list of columns, followed by
# `inner`: node `c` of the row, counted from its head column, and the child in the
# wrapper that the node holds, one `content` step deeper in a viewport.
function _make_list_cell_reference(row::GraphicsCanvas, c::Int, inner::Reference)
    head = unwrap_cell(getfield(row, :elements))
    head isa ListNode || return nothing
    node = find_list_node(head, c)
    node === nothing && return nothing
    below = _make_wrapped_reference(inner)
    unwrap_cell(node.value) isa GraphicsViewport &&
        (below = ConcreteReference(FieldReferenceStep("content"), below))
    _make_list_node_reference(c, below)
end

# A path into the canvas of a list goes through nodes that name no row by a
# fixed index, so it maps to no path into the document.
map_reference_backward(::GridLayoutToGraphicsCanvas, ::GridLayoutListIoMap, reference) = nothing

# ── Reading ──────────────────────────────────────────────────────────────────

# A pointer event goes to the cell under the pointer, and a key to the cell that
# the selection of the grid names. The answer is rooted at `children[k][c]`.
function read_intent(::GridLayoutToGraphicsCanvas, iomap::GridLayoutListIoMap, evt)
    found = _read_grid_list_cell(iomap, evt)
    found === nothing && return read_container_gesture(nothing, evt, iomap.input)
    read_container_gesture(found[1], evt, iomap.input; steps = found[2])
end

# The answer of the cell that `evt` reaches, rooted at `children[k][c]`, with the
# steps to that cell; `nothing` when it reaches no cell.
function _read_grid_list_cell(iomap::GridLayoutListIoMap, evt)
    state = iomap.state
    pointer = hasproperty(evt, :x) && hasproperty(evt, :y)
    k, c = if pointer
        row = _find_grid_list_row_at(state, Int(evt.y))
        column = state.column_head === nothing ?
            _find_grid_list_column_at(iomap.col_x, iomap.col_w, Int(evt.x)) :
            _find_grid_list_column_node_at(state, Int(evt.x))
        (row, column)
    else
        named = _split_grid_list_reference(getfield(iomap.input, :selection)[])
        named === nothing ? (nothing, nothing) : (named[1], named[2])
    end
    (k === nothing || c === nothing) && return nothing
    found = _find_grid_list_row(state, k)
    found === nothing && return nothing
    canvas = found[1]
    entry = find_grid_list_cell(iomap, k, c)
    (entry === nothing || entry[3] === nothing) && return nothing
    answer = if pointer
        row_y = Int(canvas.y)
        point = _find_child_point(entry, Int(evt.x), Int(evt.y) - row_y; bounded = true)
        point === nothing && return nothing
        local_event = _translate_layout_list_event(evt, point...)
        local_event === nothing && return nothing
        shift_operation_position(read_child_event(entry[3], local_event),
                                 Int(evt.x) - point[1], Int(evt.y) - point[2])
    else
        read_intent(entry[3].projection, entry[3], evt)
    end
    steps = (FieldReferenceStep("children"), RangeReferenceStep(k - 1, k),
             RangeReferenceStep(c - 1, c))
    answer isa Operation || return (nothing, steps)
    (_annotate_operation(iomap.input, reroot_operation(answer, steps)), steps)
end
