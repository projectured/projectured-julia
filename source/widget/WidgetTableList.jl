# Fragment of `WidgetModule`.
#
# The list form of a table's printer. `rows` is a `ListNode` whose values are
# rows — each a `CellVector` of documents, the same shape an eager row has —
# and the printer draws the rows a viewport shows and no others.
#
# **The head is the anchor.** A list-backed canvas is walked both ways from its
# head: `prev` upward until a row is above the viewport, `next` downward until
# one is below. So the head is not the first row but the row the table looks
# at, and `rows[i]` counts from it: the head is row 1, `next` steps count up,
# and a row reached through `prev` has an index of zero or less. That is the
# arithmetic `ListNode` already answers to `getindex`.
#
# **A row is built when the walk reaches it**, and the canvas list mirrors the
# document list node for node: a canvas node holds its row's cell iomaps and
# lives as long as the document node it mirrors is reachable. Nothing is
# counted, nothing is cached beyond that, and a list whose `next` never answers
# `nothing` is infinite.
#
# **What a list needs.** Every column must be given a width — `Fixed`, or a
# weight — because a column that is its content would depend on cells that are
# never built. A weighted column with no minimum of its own is at least as wide
# as its header, which is the one cell of a column that is always drawn. Rows take `Fixed` or `Content`: a `Fixed` row is arithmetic, and
# a `Content` row costs the walk the renderer makes in any case, because each
# row's y is the previous row's y plus its height. A weight on the rows is
# refused, because it divides an offered height by a count and a list has none.
# A list draws no row headers.
#
# **What the table reports.** Its width, and no height: a list has no extent,
# and a table whose rows are a list belongs in a `WidgetScrollPane`, which
# measures its offset from the head. The pane stops at the first row and at the
# last row of a list that ends, once its walk from the head reaches them.
#
# **The empty list is an empty vector.** A `ListNode` holds a row, so a list
# of no rows cannot be one; a table drawn as a list whose `rows` cell later
# answers an empty `CellVector` draws its header and no rows, and draws the
# rows again when the cell answers a list again.

# What the list printer keeps for its readers: the geometry every row shares,
# and the rows built so far by their index from the head.
mutable struct WidgetTableListState
    ncols::Int
    widths::Cell             # Vector{Int}: the extent of every column
    columns::Cell            # Vector{Int}: the edge of every column, gaps included
    total_w::Cell            # Int: the table's width, the last edge and the rule
    pad_x::Int
    pad_y::Int
    bw::Int
    header_height::Cell      # Int: the header strip and the rule under it, or 0
    row_extent::Union{Nothing,Int}   # a Fixed row's cell height; nothing when a row is its content
    header_entries::Vector{Any}      # (x, y, iomap) per header cell
    built::Dict{Int,Any}     # index from the head => (canvas, entries)
    head::Cell               # the canvas ListNode the body draws from
end

@iomap struct WidgetTableListIoMap
    projection::Any
    input::Any
    output::Any
    state::Any
end

# ── What a list needs, said before anything is drawn ─────────────────────────

_wtl_column_policy(w::WidgetTable, c::Int) = begin
    policies = w.column_policies
    (policies isa AbstractVector && 1 <= c <= length(policies)) ? policies[c] : w.column_policy
end

_wtl_is_offered(policy::SizePolicy) =
    (policy.weight !== nothing && policy.weight > 0) || policy.preferred !== nothing

function _wtl_check(w::WidgetTable)
    ncols = Int(w.column_count)
    for c in 1:ncols
        _wtl_is_offered(_wtl_column_policy(w, c)) ||
            error("WidgetTable: a table whose rows are a list needs every column given a width, and column ",
                  c, " is its content")
    end
    policy = w.row_policy
    policy isa SizePolicy || error("WidgetTable: the row policy is a SizePolicy")
    (policy.weight !== nothing && policy.weight > 0) &&
        error("WidgetTable: a weight divides an offered height by a count, and a list of rows has none; ",
              "give the rows Fixed or Content")
    isempty(w.row_policies) ||
        error("WidgetTable: the rows of a list are all alike; name one row policy")
    isempty(w.row_headers) ||
        error("WidgetTable: a table whose rows are a list draws no row headers")
    nothing
end

# ── The cells of a row ───────────────────────────────────────────────────────

# The context a cell is printed in: the column's width when the cell wraps,
# withheld when it clips, and never a height — a row is its content or is
# told its height, and neither comes from the cell.
function _wtl_cell_context(ctx, w::WidgetTable, c::Int, widths::Cell)
    offered = _wt_column_cell_policy(w, c) === :wrap
    ctx = offered ? with_exact_size(ctx; width = Cell(@computation Int32(widths[][c]))) :
                    withhold_offer(ctx, :x)
    withhold_offer(ctx, :y)
end

_wtl_cell_document(row, c::Int) = (1 <= c <= length(row)) ? row[c] : nothing

_wtl_child_w(cim) = (cim !== nothing && cim.output isa GraphicsCanvas) ? Int(cim.output.w) : 0
_wtl_child_h(cim) = (cim !== nothing && cim.output isa GraphicsCanvas) ? Int(cim.output.h) : 0

# The band under a row: the whole row when the row is named, the one cell when
# a cell is, and nothing when neither. `kind` is `:hover` or `:selection`, and
# the rect reads the document itself, so a caret move rebuilds no row.
function _wtl_band(p::WidgetTableToGraphicsCanvas, w::WidgetTable, k::Int, st::WidgetTableListState,
                   height::Cell, kind::Symbol)
    bounds = Cell(@computation begin
        reference = kind === :hover ? w.hovered : w.selection
        named = _wtl_named(reference)
        named === nothing && return (0, 0)
        row, column = named
        row == k || return (0, 0)
        column === nothing && return (0, Int(st.total_w[]))
        edges = st.columns[]
        (1 <= column <= length(edges) - 1) || return (0, 0)
        (edges[column], edges[column + 1] - edges[column])
    end)
    color = kind === :hover ? p.layer_hovered_color : _get_state_color(p, w, :row; state = :selected)
    rect = GraphicsRect(0, 0, 0, 0; color, radius = _WT_ROW_RADIUS)
    set_cell_computation!(getfield(rect, :x), () -> Int32(bounds[][1]))
    set_cell_computation!(getfield(rect, :y), () -> Int32(st.bw))
    set_cell_computation!(getfield(rect, :w), () -> Int32(bounds[][2]))
    set_cell_computation!(getfield(rect, :h), () -> Int32(bounds[][2] == 0 ? 0 : max(0, Int(height[]) - st.bw)))
    rect
end

# The row and the cell a reference names: `rows[k]∅` is `(k, nothing)`,
# `rows[k][c]∅` is `(k, c)`, and anything else is `nothing`.
function _wtl_named(reference)
    terminal = _wt_field_element_terminal(reference)
    terminal !== nothing && terminal[1] == "rows" && return (terminal[2], nothing)
    cell = _wt_cell_terminal(reference)
    cell === nothing ? nothing : cell
end

# One row: its cells recursed and clipped to their columns, the rule above it,
# the segment of every column's rule, and its bands. The canvas's `y` is set by
# the node that links it, because a row is under the row before it or above
# the row after it, and the head is at zero.
function _wtl_row(p::WidgetTableToGraphicsCanvas, recursion, w::WidgetTable, ctx,
                  st::WidgetTableListState, k::Int, row)
    bw, pad_x, pad_y = st.bw, st.pad_x, st.pad_y
    entries = Any[]
    for c in 1:st.ncols
        document = _wtl_cell_document(row, c)
        cctx = make_child_context(ctx, w, (@reference_step rows), (@reference_step [k]),
                                  (@reference_step [c]))
        cctx = _wtl_cell_context(cctx, w, c, st.widths)
        cim = document === nothing ? nothing : print_child(recursion, document, cctx)
        x_cell = Cell(@computation Int32(st.columns[][c] + bw + pad_x +
            _wt_align_offset(_wt_column_align(w, c), st.widths[][c], _wtl_child_w(cim))))
        y_cell = Cell(Int32(bw + pad_y))
        push!(entries, (x_cell, y_cell, cim))
    end
    row_h = Cell(@computation(st.row_extent !== nothing ? st.row_extent :
        maximum((_wtl_child_h(entry[3]) for entry in entries); init = 0)))
    height = Cell(@computation Int32(bw + pad_y + Int(row_h[]) + pad_y))
    divider_stroke = _get_state_stroke(p, w, :divider)
    elements = CellVector(@computation begin
        total_w = Int(st.total_w[])
        edges = st.columns[]
        out = Any[]
        # A transparent rect the size of the row, so a click on the empty part
        # of a cell reaches the table through a container that gates on a hit.
        push!(out, GraphicsRect(0, 0, total_w, Int(height[]); color = color_transparent, radius = 0))
        push!(out, _wtl_band(p, w, k, st, height, :hover))
        push!(out, _wtl_band(p, w, k, st, height, :selection))
        for c in 1:st.ncols
            (x_cell, y_cell, cim) = entries[c]
            cim === nothing && continue
            child = cim.output
            child isa GraphicsDocument || continue
            slot_w = Cell(@computation Int32(st.widths[][c]))
            slot_h = Cell(@computation Int32(Int(row_h[])))
            push!(out, clip_child_to_slot(child, cim; x_cell, y_cell, slot_x = x_cell,
                                          slot_y = y_cell, slot_w, slot_h, clip_x = true,
                                          clip_y = st.row_extent !== nothing))
        end
        push!(out, GraphicsRect(0, 0, total_w, bw; color = divider_stroke.color))
        for edge in edges
            push!(out, GraphicsRect(edge, 0, bw, Int(height[]); color = divider_stroke.color))
        end
        out
    end)
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                            Cell(@computation Int32(Int(st.total_w[]))), height,
                            elements, layout_none, true, Cell(nothing))
    (canvas, entries)
end

# The canvas node that mirrors document node `k`. `above` is the canvas node
# of row `k - 1` when this row was reached from it, `below` that of row `k + 1`
# when it was reached from there; the head has neither and sits at zero. The
# neighbours are built when first read, and a document list that grows — its
# `next` answers a node it did not answer before — grows this list with it.
function _wtl_node(p, recursion, w::WidgetTable, ctx, st::WidgetTableListState, k::Int,
                   document_node::ListNode, above, below)
    canvas, entries = _wtl_row(p, recursion, w, ctx, st, k, document_node.value)
    st.built[k] = (canvas, entries)
    node = ListNode(canvas)
    if above !== nothing
        above_canvas = above.value
        set_cell_computation!(getfield(canvas, :y),
                           () -> Int32(Int(above_canvas.y) + Int(above_canvas.h)))
    elseif below !== nothing
        below_canvas = below.value
        set_cell_computation!(getfield(canvas, :y),
                           () -> Int32(Int(below_canvas.y) - Int(canvas.h)))
    end
    set_cell_computation!(getfield(node, :next), () -> begin
        following = document_node.next
        following === nothing && return nothing
        next_node = _wtl_node(p, recursion, w, ctx, st, k + 1, following, node, nothing)
        set_cell_value!(getfield(next_node, :prev), node)
        next_node
    end)
    set_cell_computation!(getfield(node, :prev), () -> begin
        preceding = document_node.prev
        preceding === nothing && return nothing
        prev_node = _wtl_node(p, recursion, w, ctx, st, k - 1, preceding, nothing, node)
        set_cell_value!(getfield(prev_node, :next), node)
        prev_node
    end)
    node
end

# The canvas node of row `k`, walked to from the head and built on the way.
# `nothing` when the list ends before it.
function _wtl_row_node(st::WidgetTableListState, k::Int)
    node = st.head[]
    node isa ListNode || return nothing
    if k >= 1
        for _ in 1:(k - 1)
            node = node.next
            node === nothing && return nothing
        end
    else
        for _ in 1:(1 - k)
            node = node.prev
            node === nothing && return nothing
        end
    end
    node
end

# ── The printer ──────────────────────────────────────────────────────────────

function _wtl_print(p::WidgetTableToGraphicsCanvas, recursion, w::WidgetTable, ctx)
    _wtl_check(w)
    ncols = Int(w.column_count)
    pad_x = _sc(Int(p.cell_padding.left[]))
    pad_y = _sc(Int(p.cell_padding.top[]))
    bw = max(1, _sc(Int(w.border_width)))
    hgap = 2 * pad_x + bw
    # The table's own box, outside the header and the rows. Its left and right
    # insets shift every column; its top inset shifts the header down (baked
    # into `header_height`, below) and, with it, every row. A list has no
    # bottom edge — rows are drawn one at a time with no total extent — so the
    # box paints no fill: only its geometry (the offset, and the width it takes
    # from the offer) applies. Transparent, zero-width by default, so nothing
    # about the list moves.
    inset_width, _ = _inset_total(p, w)
    content_x, content_y = _content_offset(p, w)
    avail_w = ctx === nothing ? nothing : get_exact_width(ctx)
    header_row_color = _get_state_color(p, w, :header_row)
    divider_stroke = _get_state_stroke(p, w, :divider)
    # The columns from the policies; a weighted column shares what the table was
    # offered, less the gaps, the closing rule and the box that the edges add.
    #
    # A weighted column with no minimum of its own takes the width of its header
    # as its minimum, so a narrow pane scrolls rather than cutting the names of
    # its columns. The header is drawn without an offer, so its width does not
    # depend on the column's. A column whose cells wrap offers its width to the
    # header as well, so it has no such floor.
    function header_floor(c::Int, policy::SizePolicy)
        (policy.weight !== nothing && policy.weight > 0 && policy.min === nothing) || return policy
        _wt_column_cell_policy(w, c) === :wrap && return policy
        c <= length(st.header_entries) || return policy
        floor = _wtl_child_w(st.header_entries[c][3])
        SizePolicy(floor, max(floor, something(policy.preferred, 0)), policy.max, policy.weight)
    end
    widths = Cell(@computation(compute_axis_extents(
        SizePolicy[header_floor(c, _wtl_column_policy(w, c)) for c in 1:ncols], hgap,
        avail_w === nothing ? nothing :
            max(0, Int(avail_w[]) - hgap - bw - inset_width))))
    columns = Cell(@computation compute_axis_offsets(widths[], hgap))
    total_w = Cell(@computation last(columns[]) + bw)
    row_policy = w.row_policy::SizePolicy
    row_extent = row_policy.preferred === nothing ? nothing : Int(row_policy.preferred)
    # `header_height` is the body's y from the table's own origin, which is
    # the content offset even with no header strip.
    st = WidgetTableListState(ncols, widths, columns, total_w, pad_x, pad_y, bw,
                              Cell(content_y), row_extent, Any[], Dict{Int,Any}(), Cell(nothing))

    # The header strip: the column names, a filled band behind them, drawn at
    # the top and held still by an enclosing pane. Its height (plus the content
    # offset) is the body's y.
    has_header = length(w.column_headers) > 0
    header_canvas = nothing
    if has_header
        for c in 1:ncols
            document = c <= length(w.column_headers) ? w.column_headers[c] : nothing
            cctx = make_child_context(ctx, w, (@reference_step column_headers), (@reference_step [c]))
            cctx = _wtl_cell_context(cctx, w, c, widths)
            cim = document === nothing ? nothing : print_child(recursion, document, cctx)
            x_cell = Cell(@computation Int32(columns[][c] + bw + pad_x +
                _wt_align_offset(_wt_column_align(w, c), widths[][c], _wtl_child_w(cim))))
            y_cell = Cell(Int32(bw + pad_y))
            push!(st.header_entries, (x_cell, y_cell, cim))
        end
        header_h = Cell(@computation maximum((_wtl_child_h(entry[3]) for entry in st.header_entries); init = 0))
        strip_h = Cell(@computation bw + pad_y + Int(header_h[]) + pad_y)
        set_cell_computation!(st.header_height, () -> content_y + Int(strip_h[]))
        header_elements = CellVector(@computation begin
            out = Any[GraphicsRect(0, 0, Int(total_w[]), Int(strip_h[]); color = header_row_color)]
            for c in 1:ncols
                (x_cell, y_cell, cim) = st.header_entries[c]
                cim === nothing && continue
                child = cim.output
                child isa GraphicsDocument || continue
                slot_w = Cell(@computation Int32(widths[][c]))
                slot_h = Cell(@computation Int32(Int(header_h[])))
                push!(out, clip_child_to_slot(child, cim; x_cell, y_cell, slot_x = x_cell,
                                              slot_y = y_cell, slot_w, slot_h,
                                              clip_x = true, clip_y = false))
            end
            push!(out, GraphicsRect(0, 0, Int(total_w[]), bw; color = divider_stroke.color))
            for edge in columns[]
                push!(out, GraphicsRect(edge, 0, bw, Int(strip_h[]); color = divider_stroke.color))
            end
            out
        end)
        header_canvas = GraphicsCanvas(Cell(Int32(content_x)), Cell(Int32(content_y)),
                                       Cell(@computation Int32(Int(total_w[]))),
                                       Cell(@computation Int32(Int(strip_h[]))),
                                       header_elements, layout_none, true, Cell(nothing))
    end

    # The body: a canvas whose elements are the canvas list, built from the
    # head. A new head in `rows` drops every row built and starts again, and
    # no head — an empty vector — is no rows.
    set_cell_computation!(st.head, () -> begin
        rows = w.rows
        empty!(st.built)
        rows isa ListNode ? _wtl_node(p, recursion, w, ctx, st, 1, rows, nothing, nothing) : nothing
    end)
    body_elements = Cell(@computation begin
        head = st.head[]
        head === nothing ? CellVector() : head
    end)
    body = GraphicsCanvas(Cell(Int32(content_x)), Cell(@computation Int32(Int(st.header_height[]))),
                          Cell(@computation Int32(Int(total_w[]))), Cell(Int32(0)),
                          body_elements, layout_vertical, false, Cell(nothing))
    ox, oy = _origin(w.position::Point2D)
    elements = CellVector(Cell[Cell(e) for e in (has_header ? Any[header_canvas, body] : Any[body])])
    canvas = GraphicsCanvas(Cell(Int32(ox)), Cell(Int32(oy)),
                            Cell(@computation Int32(Int(total_w[]) + inset_width)), Cell(Int32(0)),
                            elements, layout_none, true, Cell(nothing))
    WidgetTableListIoMap(p, w, canvas, st)
end

get_frozen_extent(iomap::WidgetTableListIoMap) =
    Cell(@computation (0, Int(iomap.state.header_height[])))

# ── References ───────────────────────────────────────────────────────────────

_wtl_cell_reference(k::Int, c::Int, tail) =
    ConcreteReference(FieldReferenceStep("rows"),
        ConcreteReference(RangeReferenceStep(k - 1, k),
            ConcreteReference(RangeReferenceStep(c - 1, c), tail)))

_wtl_row_reference(k::Int) =
    ConcreteReference(FieldReferenceStep("rows"),
        ConcreteReference(RangeReferenceStep(k - 1, k), EmptyReference()))

_wtl_column_reference(c::Int) =
    ConcreteReference(FieldReferenceStep("column_headers"),
        ConcreteReference(RangeReferenceStep(c - 1, c), EmptyReference()))

# Forward: `rows[k][c].…` is answered by the cell's own iomap, once row `k` is
# built, and a point it answers is moved by the row's place and the header's.
# `column_headers[c].…` is the header cell's own answer, at the top. Both are
# in body-local coordinates, so the table's own content offset (the box) is
# added; `st.header_height` already carries it on the y axis.
function map_reference_forward(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableListIoMap, reference)
    st = iomap.state
    reference isa ConcreteReference || return nothing
    head = reference.head
    head isa FieldReferenceStep || return nothing
    content_x, _ = _content_offset(p, iomap.input)
    if head.name == "column_headers"
        image = descend_reference_forward(st.header_entries, "column_headers", reference)
        image isa PointReferenceStep || return image
        return PointReferenceStep(Int(image.x[]) + content_x, Int(image.y[]))
    elseif head.name == "rows"
        split = _wt_cell_split(reference)
        split === nothing && return nothing
        k, c, tail = split
        _wtl_row_node(st, k) === nothing && return nothing
        canvas, entries = st.built[k]
        (1 <= c <= length(entries)) || return nothing
        # The whole cell is where the cell begins; anything inside it is the
        # cell's own answer, moved by the row's place and the header's.
        if tail isa EmptyReference
            (x_cell, y_cell, _) = entries[c]
            return PointReferenceStep(Int(x_cell[]) + content_x,
                                      Int(y_cell[]) + Int(st.header_height[]) + Int(canvas.y))
        end
        image = descend_reference_forward(entries, "children",
            ConcreteReference(FieldReferenceStep("children"),
                ConcreteReference(RangeReferenceStep(c - 1, c), tail)))
        image isa PointReferenceStep || return image
        return PointReferenceStep(Int(image.x[]) + content_x,
                                  Int(image.y[]) + Int(st.header_height[]) + Int(canvas.y))
    end
    nothing
end

# Backward: a path into the table's own canvas names a row canvas by its index
# from the head and a cell by its slot, which is what a walk of the list built.
# Nothing produces such a path today, so it is not answered.
map_reference_backward(::WidgetTableToGraphicsCanvas, ::WidgetTableListIoMap, reference) = nothing

# ── Reading ──────────────────────────────────────────────────────────────────

# The row whose canvas holds body coordinate `y`, walked from the head in the
# direction of `y` and built on the way; `nothing` past the end.
function _wtl_row_at(st::WidgetTableListState, y::Int)
    node = st.head[]
    node isa ListNode || return nothing
    k = 1
    if y >= 0
        while y >= Int(node.value.y) + Int(node.value.h)
            node = node.next
            node === nothing && return nothing
            k += 1
        end
    else
        while y < Int(node.value.y)
            node = node.prev
            node === nothing && return nothing
            k -= 1
        end
    end
    k
end

# Outside the table's own box (its full outer width) there is no column to
# answer; inside it, a press on the margin, the border or the padding is
# clamped into the grid, like every other reader that maps a position to a
# row or a column.
function _wtl_click(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableListIoMap, g::MousePress)
    st = iomap.state
    w = iomap.input
    content_x, _ = _content_offset(p, w)
    inset_width, _ = _inset_total(p, w)
    edges = st.columns[]
    (0 <= g.x < last(edges) + st.bw + inset_width) || return nothing
    x = clamp(g.x - content_x, 0, max(0, last(edges) + st.bw - 1))
    c = find_axis_band(edges, x)
    c === nothing && return nothing
    header_height = Int(st.header_height[])
    if g.y < header_height
        header_height > 0 || return nothing
        return ReplaceSelectionOperation(_wtl_column_reference(c))
    end
    k = _wtl_row_at(st, g.y - header_height)
    k === nothing && return nothing
    g.modifiers.alt && return ReplaceSelectionOperation(_wtl_cell_reference(k, c, EmptyReference()))
    _wtl_route_cell_click(iomap, k, c, g, content_x)
end

# A click inside a cell goes to the cell's own reader, in the cell's own
# coordinates. Its answer is re-rooted under `rows[k][c]`; an operation that
# names its own document stays as it is, which is what lets a checkbox or a
# button in a cell be pressed. A cell that declines
# the click — a label has nothing to say to one — leaves the click to the row,
# and the row is selected: a table of text is a table of rows, and a list
# draws no row-header strip to click on instead.
function _wtl_route_cell_click(iomap::WidgetTableListIoMap, k::Int, c::Int, g::MousePress, content_x::Int)
    st = iomap.state
    _wtl_row_node(st, k) === nothing && return nothing
    canvas, entries = st.built[k]
    (x_cell, y_cell, cim) = entries[c]
    row = ReplaceSelectionOperation(_wtl_row_reference(k))
    cim === nothing && return row
    cell = cim.output
    cell isa GraphicsCanvas || return row
    cell_x = content_x + Int(x_cell[]) + Int(cell.x)
    cell_y = Int(st.header_height[]) + Int(canvas.y) + Int(y_cell[]) + Int(cell.y)
    op = read_intent(cim.projection, cim, MousePress(g.button, g.x - cell_x, g.y - cell_y, g.count, g.modifiers;
                                                     time = g.time))
    op === nothing && return row
    reroot_operation(op, _wt_get_cell_steps(k, c))
end

# The row, or the row and the cell, under the pointer, written to `hovered`.
# Outside the table's own box there is no row to hover.
function _wtl_hover(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableListIoMap, x::Int, y::Int, force::Bool)
    st = iomap.state
    w = iomap.input
    inset_width, _ = _inset_total(p, w)
    edges = st.columns[]
    inside = 0 <= x < last(edges) + st.bw + inset_width && y >= Int(st.header_height[])
    k = inside ? _wtl_row_at(st, y - Int(st.header_height[])) : nothing
    reference = k === nothing ? nothing : _wtl_row_reference(k)
    current = w.hovered
    if !force
        same = (current === nothing && reference === nothing) ||
               (current !== nothing && reference !== nothing &&
                _widget_element_selected(current, "rows") == k)
        same && return nothing
    end
    _write_view_state(w, "hovered", reference)
end

function _wtl_key_navigate(iomap::WidgetTableListIoMap, evt::KeyDown)
    st = iomap.state
    ncols = st.ncols
    ncols == 0 && return nothing
    w = iomap.input
    sel = w.selection
    if evt.key === :home && evt.modifiers.ctrl && evt.modifiers.alt
        return ReplaceSelectionOperation(EmptyReference())
    end
    named = _wtl_named(sel)
    named === nothing && return nothing
    k, c = named
    exists(row) = _wtl_row_node(st, row) !== nothing
    if evt.key === :return
        c === nothing && return ReplaceSelectionOperation(_wtl_cell_reference(k, 1, EmptyReference()))
        return _wtl_enter_cell(iomap, k, c)
    end
    if evt.key === :space && (evt.modifiers.shift ⊻ evt.modifiers.ctrl)
        c === nothing && return nothing
        return evt.modifiers.shift ? ReplaceSelectionOperation(_wtl_row_reference(k)) : nothing
    end
    (evt.modifiers.alt || named !== nothing) && evt.key in (:up, :down, :left, :right) || return nothing
    if c === nothing
        evt.key === :up && return exists(k - 1) ? ReplaceSelectionOperation(_wtl_row_reference(k - 1)) : nothing
        evt.key === :down && return exists(k + 1) ? ReplaceSelectionOperation(_wtl_row_reference(k + 1)) : nothing
        evt.key === :right && return ReplaceSelectionOperation(_wtl_cell_reference(k, 1, EmptyReference()))
        return nothing
    end
    if evt.key === :up
        exists(k - 1) || return nothing
        k -= 1
    elseif evt.key === :down
        exists(k + 1) || return nothing
        k += 1
    elseif evt.key === :left
        c = max(1, c - 1)
    elseif evt.key === :right
        c = min(ncols, c + 1)
    end
    ReplaceSelectionOperation(_wtl_cell_reference(k, c, EmptyReference()))
end

# Enter puts the caret at the start of the cell's own content.
function _wtl_enter_cell(iomap::WidgetTableListIoMap, k::Int, c::Int)
    st = iomap.state
    _wtl_row_node(st, k) === nothing && return nothing
    _, entries = st.built[k]
    cim = entries[c][3]
    cim === nothing && return nothing
    op = read_intent(cim.projection, cim, KeyDown(:home, ModifierKeys(ctrl = true);
                                                  time = time()))
    op isa ReplaceSelectionOperation || return nothing
    ReplaceSelectionOperation(_wtl_cell_reference(k, c, op.path))
end

# An event that is not a gesture of the table's own goes to the cell the
# selection is in, and its answer is re-rooted under that cell.
function _wtl_passthrough(iomap::WidgetTableListIoMap, event)
    st = iomap.state
    prefix = _wt_cell_prefix(iomap.input.selection)
    prefix === nothing && return nothing
    k, c = prefix
    _wtl_row_node(st, k) === nothing && return nothing
    _, entries = st.built[k]
    (1 <= c <= length(entries)) || return nothing
    cim = entries[c][3]
    cim === nothing && return nothing
    reroot_operation(read_intent(cim.projection, cim, event), _wt_get_cell_steps(k, c))
end

function read_intent(p::WidgetTableToGraphicsCanvas, recursion, change::Intent, iomap::WidgetTableListIoMap)
    g = change.gesture
    if change.operation === nothing && g isa MousePress && g.button === :left
        return Intent(g, _wtl_click(p, iomap, g))
    end
    change.operation === nothing && g isa MouseEnter && return Intent(g, _wtl_hover(p, iomap, g.x, g.y, true))
    change.operation === nothing && g isa MouseMove && return Intent(g, _wtl_hover(p, iomap, g.x, g.y, false))
    change.operation === nothing && g isa MouseLeave &&
        return Intent(g, iomap.input.hovered === nothing ? nothing :
                         _write_view_state(iomap.input, "hovered", nothing))
    if change.operation === nothing && g isa KeyDown
        op = _wtl_key_navigate(iomap, g)
        op === nothing || return Intent(g, op)
    end
    payload = change.operation === nothing ? g : change.operation
    Intent(g, _wtl_passthrough(iomap, payload))
end

function read_intent(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableListIoMap, event)
    if event isa MousePress || event isa KeyDown ||
       event isa MouseEnter || event isa MouseMove || event isa MouseLeave
        return read_intent(p, nothing, Intent(event, nothing), iomap).operation
    end
    _wtl_passthrough(iomap, event)
end
