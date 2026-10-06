# Fragment of `WidgetModule`.
#
# The printer of a table whose rows are a list, and the parts that it shares
# with the printer of a table whose rows are a vector: the pane of a part, the
# region that shows the graphics of the table behind that pane, the floor that
# a header sets on its column, the wheel, and the forward map into a part.
#
# The table scrolls its own parts: the header row and the cells are each a grid
# in a `WidgetScrollPane` of their own, and the table owns the one offset of
# both, `scroll_position`. The pane of the cells shares that cell, and the pane
# of the header row reads its `x`, so the two parts never disagree.
#
# **A part is a layout.** The cells are a `GridLayout` over `rows`, which it
# draws one row at a time as a viewport reaches it, and the header row is a
# `GridLayout` of one row over `column_headers`. A layout positions and draws
# nothing, so the table draws its rules and its bands itself, behind the pane
# of each part, at the places that the grids report: the edges of the columns,
# and for the cells a list of row graphics that mirrors the list of rows that
# the grid placed. The renderer walks the mirror as it walks the rows, so only
# the rows that a viewport shows have graphics.
#
# **The coordinates of the rules** of a part are the coordinates of its grid,
# moved by the padding of a cell and the width of a rule: the rule to the left
# of the first column is at 0, and the rule above a row is at the `y` of the
# canvas of that row. The pane of each part has that padding and that rule as
# its own padding, so the rules sit in the padding of the pane and in the gaps
# of the grid.
#
# **The widths.** The cells decide the width of every column: the policy of the
# column, and at least the width of its header when the column has a weight
# and no minimum of its own, so a narrow table scrolls rather than cut the
# names of its columns. The header row takes those widths as `Fixed`. A header
# clips, so its width does not depend on the width of its column.
#
# **The head is the anchor**, as in the list form of a layout: `rows[k]` and
# `cells[k]` count from the head of the list, the head is row 1, and a row before the head has
# an index of 0 or less.
#
# **What a list needs.** An offered height, because a list has no extent to
# size the table by. A width for every column that no cell decides, and rows
# that are `Fixed` or as tall as their cells, as a `GridLayout` of a list
# needs. Row headers that are a list too, beside the rows, and then rows that
# are `Fixed`, so the header column and the cells have the same rows.
#
# **The header column and the corner.** The header column is a third pane, a
# grid of one column over the row headers, which scrolls with the `y` of the
# offset. Its width is the widest of the corner and of the header of the head
# row, because a column of a list takes a width that no walk decides. The
# corner sits where the header row and the header column meet, and it is also
# a floor for the height of the header row.

# What the printer keeps for its readers: the panes of the parts, and the
# edges of the columns in the coordinates of the rules.
struct WidgetTablePartsState
    columns::Int             # the count of the columns, or 0 when they are a list
    bw::Int                  # the width of a rule
    pad_x::Int               # the padding of a cell, left and right
    pad_y::Int               # the padding of a cell, above and below
    column_header_pane::Any  # the IO map of the pane of the header row, or nothing
    cells_pane::Any          # the IO map of the pane of the cells
    header_height::Cell      # Int: the height of the header row, or 0 with no header
    edges::Cell              # Vector{Int}: the rule left of each column, and the last rule
    column_list::Bool        # whether the columns are a list, whose edges the cells place
    row_header_pane::Any     # the IO map of the pane of the header column, or nothing
    corner::Any              # the IO map of the corner, or nothing
    header_width::Cell       # Int: the width of the header column, or 0 with no header column
end

"""
    WidgetTableListIoMap

The IO map of a `WidgetTable` whose rows are a list. Its `state` holds the IO
maps of the panes of the header row and of the cells, the height of the header
row, and the edges of the columns.
"""
@iomap struct WidgetTableListIoMap
    projection::Any
    input::Any
    output::Any
    state::Any
end

# ── What a list needs, said before anything is drawn ─────────────────────────

function _check_table_parts(w::WidgetTable, height)
    height === nothing &&
        error("WidgetTable: a table whose rows are a list needs an offered height, ",
              "because a list has no extent to size it by")
    headers = w.row_headers
    headers isa ListNode || isempty(headers) ||
        error("WidgetTable: a table whose rows are a list takes its row headers as a list")
    body = _get_body_rows(w)
    body isa ListNode || isempty(body) ||
        error("WidgetTable: a table with a corner draws its rows as a list, and takes a list ",
              "of rows or an empty vector")
    if headers isa ListNode || w.corner !== nothing
        policy = w.row_policy
        (policy isa SizePolicy && policy.preferred !== nothing &&
         (policy.weight === nothing || policy.weight == 0)) ||
            error("WidgetTable: a table whose rows and row headers are lists needs a Fixed ",
                  "row policy, so the header column and the cells have the same rows")
    end
    w.corner === nothing || _has_table_column_headers(w) ||
        error("WidgetTable: a corner sits where the header row and the header column meet, ",
              "so it needs column headers")
    w.rows isa WidgetTableRows ||
        error("WidgetTable: the rows of a list are all alike; name one row policy")
    nothing
end

# ── The widths of the columns ────────────────────────────────────────────────

# The policy of body column `c`: the column's own when it names one, else the
# table's.
function _get_table_column_policy(w::WidgetTable, c::Int)
    column = _get_table_column_data(w, c)
    policy = column === nothing ? nothing : column.policy
    policy isa SizePolicy ? policy : w.column_policy
end

# The width of what a part printed for one cell, or 0 for no cell.
_get_part_child_width(cim) =
    (cim !== nothing && cim.output isa GraphicsCanvas) ? Int(cim.output.w) : 0

# The policy of column `c` of the cells. A column with no minimum of its own is
# at least as wide as its header, `header`, which is the IO map of the header;
# a column with a weight is also at least as wide as `widest`, a cell of the
# width of its widest cell, when the cells are measured. A column with a weight
# whose cells wrap offers its width to its header as well, so the width of its
# header depends on the column and is no floor.
function _get_cells_column_policy(w::WidgetTable, c::Int, header, widest = nothing)
    policy = _get_table_column_policy(w, c)
    (header === nothing || policy.min !== nothing) && return policy
    if policy.weight !== nothing && policy.weight > 0
        _wt_column_cell_policy(w, c) === :wrap && return policy
        floor = max(_get_part_child_width(header), widest === nothing ? 0 : Int(widest[]))
        return SizePolicy(floor, max(floor, something(policy.preferred, 0)), policy.max, policy.weight)
    end
    policy.preferred === nothing || return policy
    SizePolicy(_get_part_child_width(header), nothing, policy.max, policy.weight)
end

# ── The panes of the parts ───────────────────────────────────────────────────

# The pane of a part: a grid that scrolls by `offset`, with the padding of a
# cell and a rule as its own padding. It has no fill, because the table draws
# its bands behind it, and no bar.
_make_part_pane(grid, offset::Cell, padding::Inset) =
    WidgetScrollPane(Cell(grid), Cell(nothing), Cell(nothing), offset, Cell(false),
                     Cell(nothing), Cell(nothing), Cell(true),
                     Cell(nothing), Cell(nothing), Cell(padding),
                     Cell(WidgetStyle(; content_color = color_transparent)), Cell(nothing))

# The canvas that the pane of a part draws its grid in. Its `x` and `y` are the
# offset that the pane draws with, negated.
_get_part_content(pane) = only(e for e in pane.output.elements if e isa GraphicsViewport).content

# The region of a part at `(x, y)` in the table: the graphics of the table in a
# viewport over the box of the pane, and the pane over them. `(origin_x,
# origin_y)` is the place of the region in the coordinates of the graphics, and
# the grid of the pane sits one padding of a cell and one rule inside it, as the
# padding of the pane says. So the canvas that holds the graphics moves with
# the grid in the pane.
function _make_part_region(pane, graphics; x::Cell, y::Cell, origin_x::Cell = Cell(0),
                           origin_y::Cell = Cell(0), pad_x::Int, pad_y::Int, bw::Int,
                           layout::LayoutDirection = layout_none)
    out = pane.output
    content = _get_part_content(pane)
    cox, coy = _content_offset(get_content_iomap(pane).projection, pane.input)
    graphics_x = Cell(@computation Int32(cox - pad_x - bw + Int(content.x) - Int(origin_x[])))
    graphics_y = Cell(@computation Int32(coy - pad_y - bw + Int(content.y) - Int(origin_y[])))
    canvas = GraphicsCanvas(graphics_x, graphics_y, Cell(Int32(0)), Cell(Int32(0)), graphics,
                            layout, layout == layout_none, Cell(nothing))
    viewport = GraphicsViewport(Cell(Int32(0)), Cell(Int32(0)), getfield(out, :w), getfield(out, :h),
                                Cell(canvas), Cell(affine_identity), Cell(nothing))
    GraphicsCanvas(x, y, getfield(out, :w), getfield(out, :h),
                   CellVector(Cell[Cell(viewport), Cell(out)]), layout_none, true, Cell(nothing))
end

# A turn of the wheel over a table, sent to the pane of its cells at a point in
# the viewport of that pane, because the pane scrolls only under its viewport.
# The pane stops it at the ends of its content, and the panes of the headers
# follow the offset. `(x, y)` is the place of the region of the cells in the
# table.
function _read_cells_wheel(table, pane, x::Int, y::Int, evt::MouseScroll)
    (0 <= evt.x < Int(table.w) && 0 <= evt.y < Int(table.h)) || return nothing
    cox, coy = _content_offset(get_content_iomap(pane).projection, pane.input)
    tx, ty = _inset_total(get_content_iomap(pane).projection, pane.input)
    view_w = max(1, Int(pane.output.w) - tx)
    view_h = max(1, Int(pane.output.h) - ty)
    point_x = clamp(evt.x - x, cox, cox + view_w - 1)
    point_y = clamp(evt.y - y, coy, coy + view_h - 1)
    read_intent(pane.projection, pane, MouseScroll(evt.dx, evt.dy, point_x, point_y, evt.modifiers;
                                                   time = evt.time))
end

# The rows that the grid of the cells walks: the list of rows, or `nothing`, a
# list with no rows, while the rows are a vector. So the grid is a list from its
# first print on, and draws a list that the rows hold later.
_get_row_list(w::WidgetTable) = Cell(@computation (body = _get_body_rows(w); body isa ListNode ? body : nothing))

# ── The order of the cells ───────────────────────────────────────────────────

# The body of `w` as rows of cells, as the parts walk it: the body of a
# row-major table, and in a column-major one a view that turns it, whose cells
# are the same documents (`_turn_columns`).
_get_body_rows(w::WidgetTable) = _is_column_major(w) ? _turn_columns(w.cells) : w.cells

# The rows of `columns`, the body of a column-major table, as a list of rows
# that starts at the first row of each column; an empty vector when no column
# has a row. The columns are a vector or a list, and each column is a vector or
# a list.
function _turn_columns(columns)
    if columns isa ListNode
        places = _make_mapped_node(columns, _get_first_place)
        return _has_turned_row(places) ? _make_turned_row_node(places) : CellVector()
    end
    places = Any[_get_first_place(column) for column in columns]
    _has_turned_row(places) ? _make_turned_row_node(places) : CellVector()
end

# The place of a column at one row: its node when the column is a list, a
# `_ColumnPlace` when it is a vector, and `nothing` past its end.
struct _ColumnPlace
    column::Any
    k::Int
end

_get_first_place(column::ListNode) = column
_get_first_place(::Nothing) = nothing
_get_first_place(column) = isempty(column) ? nothing : _ColumnPlace(column, 1)

# The place `d` rows after `place`, or before it when `d` is negative.
_step_place(place::ListNode, d::Int) = d > 0 ? place.next : place.prev
_step_place(place::_ColumnPlace, d::Int) =
    (k = place.k + d; 1 <= k <= length(place.column) ? _ColumnPlace(place.column, k) : nothing)
_step_place(::Nothing, d::Int) = nothing

# The cell at `place`.
_get_place_cell(place::ListNode) = place.value
_get_place_cell(place::_ColumnPlace) = place.column[place.k]
_get_place_cell(::Nothing) = nothing

# The node of the rows of a column-major body at `places`, the place of each
# column at one row: a vector of places, or a list of places that mirrors a list
# of columns. The row holds the cell at each place. The row after it steps each
# place by one; the list ends where no column has a row, or, for a list of
# columns, where the head column ends.
function _make_turned_row_node(places)
    node = ListNode(nothing)
    set_cell_computation!(getfield(node, :value), () -> _make_turned_row(places))
    set_cell_computation!(getfield(node, :next), () -> _make_turned_neighbour(node, places, 1))
    set_cell_computation!(getfield(node, :prev), () -> _make_turned_neighbour(node, places, -1))
    node
end

# The node of the row `d` rows from `node`, the row at `places`, or nothing past
# an end.
function _make_turned_neighbour(node::ListNode, places, d::Int)
    stepped = _step_places(places, d)
    _has_turned_row(stepped) || return nothing
    neighbour = _make_turned_row_node(stepped)
    set_cell_value!(getfield(neighbour, d > 0 ? :prev : :next), node)
    neighbour
end

_step_places(places::ListNode, d::Int) = _make_mapped_node(places, place -> _step_place(place, d))
_step_places(places, d::Int) = Any[_step_place(place, d) for place in places]

_has_turned_row(places::ListNode) = places.value !== nothing
_has_turned_row(places) = any(!isnothing, places)

# The row at `places`: a list that mirrors a list of places, or a `CellVector`
# whose cells follow the cells at the places.
_make_turned_row(places::ListNode) = _make_mapped_node(places, _get_place_cell)
_make_turned_row(places) = CellVector(Cell[Cell(@computation _get_place_cell(place)) for place in places])

# A list that mirrors `source`, whose node holds `f` of the value of its node of
# `source`, built when a walk first reaches it.
function _make_mapped_node(source::ListNode, f)
    node = ListNode(nothing)
    set_cell_computation!(getfield(node, :value), () -> f(source.value))
    set_cell_computation!(getfield(node, :next), () -> begin
        following = source.next
        following === nothing && return nothing
        next_node = _make_mapped_node(following, f)
        set_cell_value!(getfield(next_node, :prev), node)
        next_node
    end)
    set_cell_computation!(getfield(node, :prev), () -> begin
        preceding = source.prev
        preceding === nothing && return nothing
        prev_node = _make_mapped_node(preceding, f)
        set_cell_value!(getfield(prev_node, :next), node)
        prev_node
    end)
    node
end

# The writes that move the head of the body of `w` to its row `k`: `cells` to
# node `k` of a list of rows. In a column-major table, `cells` to a list that
# mirrors a list of columns, each column from its row `k` on, or each column of
# a vector to its node `k`. `nothing` when a column of a vector is not a list or
# has no row `k`.
function _write_body_head(w::WidgetTable, k::Int)
    cells = w.cells
    if !_is_column_major(w)
        head = _find_list_node(cells, k)
        return head === nothing ? nothing : Any[_write_view_state(w, "cells", head)]
    end
    cells isa ListNode && return Any[_write_view_state(w, "cells", _make_advanced_row_node(cells, k))]
    heads = Any[_find_list_node(column, k) for column in cells]
    any(isnothing, heads) && return nothing
    Any[ReplaceViewStateOperation(ReplaceReferencedValueOperation(w,
            extend_reference(EmptyReference(), FieldReferenceStep("cells"), RangeReferenceStep(c - 1, c)), head))
        for (c, head) in enumerate(heads)]
end

# ── The header column and the corner ─────────────────────────────────────────

# Whether the table has a header row: a list of headers, or a vector with one.
_has_table_column_headers(w::WidgetTable) =
    w.column_headers isa ListNode || length(w.column_headers) > 0

# The corner, printed at the size that it measures, or `nothing` for none.
_print_table_corner(recursion, w::WidgetTable, inner) =
    w.corner === nothing ? nothing :
        print_child(recursion, w.corner,
                    with_free_axis(
                        with_free_axis(
                            make_child_context(inner, FieldReferenceStep("corner")),
                            :x),
                        :y))

# The node of a list that mirrors the headers of `header_node` as rows of one
# cell, the form of a row of a grid. A node is built when a walk first reaches
# it, so the header column reaches as far as the rows do.
function _make_header_row_node(header_node::ListNode)
    header = header_node.value
    node = ListNode(CellVector(Cell[Cell(header === nothing ? _wt_empty_cell() : header)]))
    set_cell_computation!(getfield(node, :next), () -> begin
        following = header_node.next
        following === nothing && return nothing
        next_node = _make_header_row_node(following)
        set_cell_value!(getfield(next_node, :prev), node)
        next_node
    end)
    set_cell_computation!(getfield(node, :prev), () -> begin
        preceding = header_node.prev
        preceding === nothing && return nothing
        prev_node = _make_header_row_node(preceding)
        set_cell_value!(getfield(prev_node, :next), node)
        prev_node
    end)
    node
end

# The pane of the header column, `height` tall, or `nothing` with no row
# headers: a grid of one column over the row headers as rows of one cell, which
# scrolls with the `y` of the offset. The column is as wide as `corner` and as
# the header of the head row, which the grid measures once it prints.
function _print_header_column(recursion, w::WidgetTable, inner, corner, height::Cell,
                              pad_x::Int, pad_y::Int, bw::Int)
    # A move of the head writes the row headers, and the parts do not depend on
    # it. A corner makes a header column, which holds no rows while the rows are
    # an empty vector.
    peek(getfield(w, :row_headers)) isa ListNode || w.corner !== nothing || return nothing
    hgap = 2 * pad_x + bw
    vgap = 2 * pad_y + bw
    grid_iomap = Cell(nothing)
    width = Cell(@computation begin
        grid = grid_iomap[]
        cell = grid === nothing ? nothing : find_grid_list_cell(grid, 1, 1)
        max(_get_part_child_width(corner), cell === nothing ? 0 : _get_part_child_width(cell[3]))
    end)
    rows = Cell(@computation (headers = w.row_headers;
                              headers isa ListNode ? _make_header_row_node(headers) : nothing))
    grid = GridLayout(rows, Cell(1), Cell(:left), Cell(:top), Cell(hgap), Cell(vgap), Cell(Symbol[]),
                      Cell(@computation Fixed(width[])), getfield(w, :row_policy), Cell(Any[]),
                      Cell(Any[]), Cell(Bool[false]), Cell(Bool[]), Cell(nothing))
    offset = getfield(w, :scroll_position)
    pane = _make_part_pane(grid, Cell(@computation Point2D(0, Int((offset[]::Point2D).y[]))),
                           Inset(bw + pad_y, bw + pad_y, bw + pad_x, pad_x))
    iomap = print_child(recursion, pane,
                        with_exact_size(with_free_axis(inner, :x); height))
    grid_iomap[] = iomap.content_iomap
    iomap
end

# The band of the light or of the selection in row `k` of the header column:
# the whole column for the table, for the header column, for row `k` or for its
# header, and nothing else.
function _get_header_column_band_span(named, k, st::WidgetTablePartsState)
    named === nothing && return (0, 0)
    shape, row, _ = named
    (shape in (:table, :header_column) || (shape in (:row, :row_header) && row == k)) || return (0, 0)
    (0, Int(st.header_width[]))
end

# The graphics of row `k` of the header column, in the coordinates of its rules:
# the band of the header column, the bands of the light and of the selection of
# its row, the rule above it, and the rule under the last row. `row_node` is the
# node of the row that the grid placed.
function _make_header_column_row_graphics(p::WidgetTableToGraphicsCanvas, w::WidgetTable,
                                          st::WidgetTablePartsState, k::Int, row_node::ListNode)
    row = row_node.value
    bw = st.bw
    vgap = 2 * st.pad_y + bw
    height = Cell(@computation Int32(Int(row.h) + vgap + (row_node.next === nothing ? bw : 0)))
    band_height = Cell(@computation Int(row.h) + 2 * st.pad_y)
    color = _get_state_color(p, w, :header_row)
    divider = _get_state_stroke(p, w, :divider).color
    bands = Any[_make_row_band(p, w, st, k, band_height, :light; span_of = _get_header_column_band_span),
                _make_row_band(p, w, st, k, band_height, :selection; span_of = _get_header_column_band_span)]
    elements = CellVector(@computation begin
        h = Int(height[])
        width = Int(st.header_width[])
        out = Any[GraphicsRect(0, 0, width, h; color), bands...,
                  GraphicsRect(0, 0, width, bw; color = divider)]
        row_node.next === nothing && push!(out, GraphicsRect(0, h - bw, width, bw; color = divider))
        out
    end)
    GraphicsCanvas(Cell(Int32(0)), Cell(@computation Int32(Int(row.y))), Cell(Int32(0)), height,
                   elements, layout_none, true, Cell(nothing))
end

# The node of the graphics that mirrors `row_node`, the node of row `k` of the
# header column, as `_make_row_graphics_node` mirrors the rows of the cells.
function _make_header_column_graphics_node(p::WidgetTableToGraphicsCanvas, w::WidgetTable,
                                           st::WidgetTablePartsState, k::Int, row_node::ListNode)
    node = ListNode(_make_header_column_row_graphics(p, w, st, k, row_node))
    set_cell_computation!(getfield(node, :next), () -> begin
        following = row_node.next
        following === nothing && return nothing
        next_node = _make_header_column_graphics_node(p, w, st, k + 1, following)
        set_cell_value!(getfield(next_node, :prev), node)
        next_node
    end)
    set_cell_computation!(getfield(node, :prev), () -> begin
        preceding = row_node.prev
        preceding === nothing && return nothing
        prev_node = _make_header_column_graphics_node(p, w, st, k - 1, preceding)
        set_cell_value!(getfield(prev_node, :next), node)
        prev_node
    end)
    node
end

# The region of the header column, under the corner, or `nothing` with none.
function _make_header_column_region(p::WidgetTableToGraphicsCanvas, w::WidgetTable,
                                    st::WidgetTablePartsState, content_x::Int, content_y::Int)
    pane = st.row_header_pane
    pane === nothing && return nothing
    grid = pane.content_iomap
    mirror = Cell(@computation begin
        head = get_grid_list_head(grid)
        head isa ListNode ? _make_header_column_graphics_node(p, w, st, 1, head) : CellVector()
    end)
    _make_part_region(pane, mirror; x = Cell(Int32(content_x)),
                      y = Cell(@computation Int32(content_y + Int(st.header_height[]))),
                      pad_x = st.pad_x, pad_y = st.pad_y, bw = st.bw, layout = layout_vertical)
end

# The region of the corner at the top left of the parts, as wide as the header
# column and as tall as the header row: the band of the header row, the band of
# the selection when it is the corner or the table, the rule above it, and the
# corner at the place of a header in the header row.
function _make_corner_region(p::WidgetTableToGraphicsCanvas, w::WidgetTable, st::WidgetTablePartsState,
                             content_x::Int, content_y::Int)
    st.row_header_pane === nothing && return nothing
    width = Cell(@computation Int32(Int(st.header_width[])))
    height = Cell(@computation Int32(Int(st.header_height[])))
    color = _get_state_color(p, w, :header_row)
    divider = _get_state_stroke(p, w, :divider).color
    corner = st.corner === nothing ? nothing :
        GraphicsCanvas(Cell(Int32(st.bw + st.pad_x)), Cell(Int32(st.bw + st.pad_y)),
                       getfield(st.corner.output, :w), getfield(st.corner.output, :h),
                       CellVector(Cell[Cell(st.corner.output)]), layout_none, true, Cell(nothing))
    # The band reads the selection itself, so a move of the selection builds no
    # region again.
    selected = Cell(@computation (selection = w.selection;
                                  selection isa EmptyReference || _wt_field_terminal(selection) == "corner"))
    band = GraphicsRect(0, 0, 0, 0; color = _get_state_color(p, w, :row; state = :selected), radius = p.row_radius)
    set_cell_computation!(getfield(band, :y), () -> Int32(st.bw))
    set_cell_computation!(getfield(band, :w), () -> Int32(selected[] ? Int(width[]) : 0))
    set_cell_computation!(getfield(band, :h), () -> Int32(selected[] ? Int(height[]) - st.bw : 0))
    elements = CellVector(@computation begin
        out = Any[GraphicsRect(0, 0, Int(width[]), Int(height[]); color), band,
                  GraphicsRect(0, 0, Int(width[]), st.bw; color = divider)]
        corner === nothing || push!(out, corner)
        out
    end)
    GraphicsCanvas(Cell(Int32(content_x)), Cell(Int32(content_y)), width, height, elements,
                   layout_none, true, Cell(nothing))
end

# ── The graphics of the rows ─────────────────────────────────────────────────

# What a reference names in a table of a list, as `(shape, row, column)`:
# `(:table, 0, 0)` for `∅`, `(:row, k, 0)` for `rows[k]∅`, `(:column, 0, c)` for
# `columns[c]∅`, `(:cell, k, c)` for `cells[k][c]∅`, and the header of a row or of
# a column, a part of its own, `(:row_header, k, 0)` for `row_headers[k]∅` and
# `(:column_header, 0, c)` for `column_headers[c]∅`, and the strips of the
# headers, `(:header_row, 0, 0)` for `column_headers∅` and `(:header_column, 0, 0)`
# for `row_headers∅`; `nothing` for anything else. A row can have an index of 0
# or less, before the head.
function _find_named_part(w::WidgetTable, reference)
    reference isa EmptyReference && return (:table, 0, 0)
    field = _wt_field_terminal(reference)
    field == "column_headers" && return (:header_row, 0, 0)
    field == "row_headers" && return (:header_column, 0, 0)
    terminal = _wt_field_element_terminal(reference)
    if terminal !== nothing
        field, index = terminal
        field == "rows" && return (:row, index, 0)
        field == "row_headers" && return (:row_header, index, 0)
        field == "columns" && return (:column, 0, index)
        field == "column_headers" && return (:column_header, 0, index)
        return nothing
    end
    cell = _wt_cell_terminal(w, reference)
    cell === nothing ? nothing : (:cell, cell[1], cell[2])
end

# The head of the list of the columns that the cells placed, when the columns
# are a list.
_get_table_column_head(st::WidgetTablePartsState) =
    get_grid_list_column_head(st.cells_pane.content_iomap)

# The left edge and the width of the box of column `c` in the coordinates of
# the rules: the rule to its left, its padding, its cells and the padding after
# them. `nothing` past an end.
function _get_table_column_span(st::WidgetTablePartsState, c::Int)
    if !st.column_list
        edges = st.edges[]
        (1 <= c < length(edges)) || return nothing
        return (edges[c], edges[c + 1] - edges[c])
    end
    node = _find_list_node(_get_table_column_head(st), c)
    node === nothing && return nothing
    (Int(node.value.x), Int(node.value.w) + 2 * st.pad_x + st.bw)
end

# The left edge and the width of a whole row: from the first rule to the last,
# or, when the columns are a list, the box of the pane of the cells, where it
# shows the columns.
function _get_table_row_span(st::WidgetTablePartsState)
    st.column_list || return (0, last(st.edges[]) + st.bw)
    (-Int(_get_part_content(st.cells_pane).x), Int(st.cells_pane.output.w))
end

# The column whose box holds `x`, in the coordinates of the rules, or `nothing`
# past an end.
function _find_table_column_at(st::WidgetTablePartsState, x::Int)
    st.column_list || return find_axis_band(st.edges[], x)
    node = _get_table_column_head(st)
    node isa ListNode || return nothing
    hgap = 2 * st.pad_x + st.bw
    c = 1
    while x < Int(node.value.x)
        node = node.prev
        node === nothing && return nothing
        c -= 1
    end
    while x >= Int(node.value.x) + Int(node.value.w) + hgap
        node = node.next
        node === nothing && return nothing
        c += 1
    end
    c
end

# How near, in pixels, a press must be to the right edge of a header to start
# the drag of the width of its column, and the narrowest width that a drag gives.
const _COLUMN_EDGE_REACH = 3
const _MIN_COLUMN_WIDTH = 24

# The band of the edge whose rule starts at `edge`, where a press starts the drag
# of the width of a column, as `(start, extent)`: `_COLUMN_EDGE_REACH` on each side
# of the middle of the rule. The reader and the region of the pointer shape both
# read it.
_get_column_edge_band(edge::Int, bw::Int) =
    (edge + bw ÷ 2 - _COLUMN_EDGE_REACH, 2 * _COLUMN_EDGE_REACH + 1)

# The region of the pointer shape over the band of the edge whose rule starts at
# `edge`, `height` tall.
function _make_column_edge_region(edge::Int, bw::Int, height::Int)
    start, extent = _get_column_edge_band(edge, bw)
    GraphicsPointerShape(start, 0, extent, height, :double_arrow_horizontal)
end

# The column whose right edge is within `_COLUMN_EDGE_REACH` of `x`, in the
# coordinates of the rules, and the width of its cells, as `(c, width)`;
# `nothing` when `x` is near no edge. The edge of a column is the rule of the
# column after it.
function _find_table_column_edge_at(st::WidgetTablePartsState, x::Int)
    hgap = 2 * st.pad_x + st.bw
    near(edge) = (band = _get_column_edge_band(edge, st.bw); band[1] <= x < band[1] + band[2])
    if !st.column_list
        edges = st.edges[]
        for c in 1:(length(edges) - 1)
            near(edges[c + 1]) && return (c, edges[c + 1] - edges[c] - hgap)
        end
        return nothing
    end
    node = _get_table_column_head(st)
    node isa ListNode || return nothing
    c = 1
    # The column whose band holds `x`, then the one before it, whose edge is at
    # the left of that band.
    while x < Int(node.value.x) && node.prev !== nothing
        node = node.prev
        c -= 1
    end
    while x >= Int(node.value.x) + Int(node.value.w) + hgap && node.next !== nothing
        node = node.next
        c += 1
    end
    for (candidate, column) in ((node, c), (node.prev, c - 1))
        candidate === nothing && continue
        x0, w0 = Int(candidate.value.x), Int(candidate.value.w)
        near(x0 + w0 + hgap) && return (column, w0)
    end
    nothing
end

# The reference of the right edge of column `c`: the width of the column, which
# a drag of the edge sets. A point on the edge maps to it, so the edge is the
# part under the pointer, and it lights.
_wt_edge_ref(c::Int) =
    ConcreteReference(FieldReferenceStep("columns"), ConcreteReference(RangeReferenceStep(c - 1, c),
        ConcreteReference(FieldReferenceStep("policy"), EmptyReference())))

# The column whose right edge `target` names, `columns[c].policy`, or 0.
function _find_column_edge(target)
    c = _widget_element_selected(target, "columns")
    c > 0 || return 0
    rest = target.tail.tail
    (rest isa ConcreteReference && rest.head == FieldReferenceStep("policy")) ? c : 0
end

# The x of the rule at the right edge of column `c`, in the coordinates of the
# rules, or `nothing` when the table places no such column.
function _get_table_column_edge_x(st::WidgetTablePartsState, c::Int)
    hgap = 2 * st.pad_x + st.bw
    if !st.column_list
        edges = st.edges[]
        return 1 <= c < length(edges) ? edges[c + 1] : nothing
    end
    node = _get_table_column_head(st)
    node isa ListNode || return nothing
    for _ in 2:c
        node = node.next
        node === nothing && return nothing
    end
    for _ in c:0
        node = node.prev
        node === nothing && return nothing
    end
    Int(node.value.x) + Int(node.value.w) + hgap
end

# The light of the right edge of the column whose width is the mouse target of
# the table: a bar over the rule, as tall as `height`, so a person sees where a
# drag of the edge starts.
function _make_column_edge_light(p::WidgetTableToGraphicsCanvas, w::WidgetTable,
                                 st::WidgetTablePartsState, height::Cell)
    stroke = p.edge_hovered_stroke
    place = Cell(@computation begin
        c = _find_column_edge(get_mouse_target(w))
        x = c == 0 ? nothing : _get_table_column_edge_x(st, c)
        x === nothing ? (0, 0) : (x + st.bw ÷ 2 - Int(stroke.width) ÷ 2, Int(stroke.width))
    end)
    rect = GraphicsRect(0, 0, 0, 0; color = stroke.color)
    set_cell_computation!(getfield(rect, :x), () -> Int32(place[][1]))
    set_cell_computation!(getfield(rect, :w), () -> Int32(place[][2]))
    set_cell_computation!(getfield(rect, :h), () -> Int32(place[][2] == 0 ? 0 : Int(height[])))
    rect
end

# The left edge and the width of the band that `named` draws in row `k`, or in
# the header row for `k === nothing`; `(0, 0)` for no band there. The table and
# a column band every row and the header row, a row and a cell only their own
# row, a column header and the header row only the header row, and a row header
# and the header column none here.
function _get_band_span(named, k, st::WidgetTablePartsState)
    named === nothing && return (0, 0)
    shape, row, column = named
    shape === :table && return _get_table_row_span(st)
    shape === :column && return something(_get_table_column_span(st, column), (0, 0))
    shape === :column_header &&
        return k === nothing ? something(_get_table_column_span(st, column), (0, 0)) : (0, 0)
    shape === :header_row && return k === nothing ? _get_table_row_span(st) : (0, 0)
    shape in (:row_header, :header_column) && return (0, 0)
    (k === nothing || row != k) && return (0, 0)
    shape === :row && return _get_table_row_span(st)
    something(_get_table_column_span(st, column), (0, 0))
end

# The band of the light or of the selection, `kind`, in row `k`, or in the
# header row for `k === nothing`, under the rule above it and `band_height`
# tall. The light is the row or the column of the mouse target of the table. The
# rect reads the reference itself, so a move of the selection or of the pointer
# builds no row again. `span_of` gives the left edge and the width of the band
# in its part.
function _make_row_band(p::WidgetTableToGraphicsCanvas, w::WidgetTable, st::WidgetTablePartsState,
                        k, band_height::Cell, kind::Symbol; span_of = _get_band_span)
    reference() = kind === :light ? _find_wt_lit_reference(w, get_mouse_target(w)) : w.selection
    span = Cell(@computation span_of(_find_named_part(w, reference()), k, st))
    color = kind === :light ? p.layer_hovered_color : _get_state_color(p, w, :row; state = :selected)
    rect = GraphicsRect(0, 0, 0, 0; color, radius = p.row_radius)
    set_cell_computation!(getfield(rect, :x), () -> Int32(span[][1]))
    set_cell_computation!(getfield(rect, :y), () -> Int32(st.bw))
    set_cell_computation!(getfield(rect, :w), () -> Int32(span[][2]))
    set_cell_computation!(getfield(rect, :h), () -> Int32(span[][2] == 0 ? 0 : Int(band_height[])))
    rect
end

# The graphics of row `k` of the cells, in the coordinates of the rules: the
# bands of the light and of the selection, the rule above the row, a segment
# of the rule of every column, and the rule under the row when it is the last.
# `row_node` is the node of the row that the grid placed, and the canvas reads
# the place and the height of that row.
function _make_row_graphics(p::WidgetTableToGraphicsCanvas, w::WidgetTable,
                            st::WidgetTablePartsState, k::Int, row_node::ListNode)
    row = row_node.value
    bw = st.bw
    vgap = 2 * st.pad_y + bw
    # The rule above, the padding, the cells and the padding under them; and
    # the rule under the last row.
    height = Cell(@computation Int32(Int(row.h) + vgap + (row_node.next === nothing ? bw : 0)))
    band_height = Cell(@computation Int(row.h) + 2 * st.pad_y)
    span = Cell(@computation _get_table_row_span(st))
    divider = _get_state_stroke(p, w, :divider).color
    bands = Any[_make_row_band(p, w, st, k, band_height, :light),
                _make_row_band(p, w, st, k, band_height, :selection)]
    # The rules of the columns are the row's own when the columns are a vector;
    # when they are a list, the region draws them once, down the whole pane.
    elements = CellVector(@computation begin
        h = Int(height[])
        left, width = span[]
        out = Any[bands..., GraphicsRect(left, 0, width, bw; color = divider)]
        # The frame of each open cell of this row whose last commit failed.
        for cell in something(w.open_cells, ())
            (cell.row == k && cell.reason !== nothing) || continue
            column = _get_table_column_span(st, cell.column)
            column === nothing && continue
            append!(out, _make_cell_mark_rects(column[1] + bw, bw, column[2] - bw, Int(band_height[]),
                                               p.cell_mark_stroke))
        end
        if !st.column_list
            for edge in st.edges[]
                push!(out, GraphicsRect(edge, 0, bw, h; color = divider))
            end
        end
        row_node.next === nothing && push!(out, GraphicsRect(left, h - bw, width, bw; color = divider))
        out
    end)
    GraphicsCanvas(Cell(Int32(0)), Cell(@computation Int32(Int(row.y))), Cell(Int32(0)), height,
                   elements, layout_none, true, Cell(nothing))
end

# The node of the row graphics that mirrors `row_node`, the node of row `k`.
# Its neighbours are built when first read, from the neighbours of `row_node`,
# so the mirror reaches as far as the rows do.
function _make_row_graphics_node(p::WidgetTableToGraphicsCanvas, w::WidgetTable,
                                 st::WidgetTablePartsState, k::Int, row_node::ListNode)
    node = ListNode(_make_row_graphics(p, w, st, k, row_node))
    set_cell_computation!(getfield(node, :next), () -> begin
        following = row_node.next
        following === nothing && return nothing
        next_node = _make_row_graphics_node(p, w, st, k + 1, following)
        set_cell_value!(getfield(next_node, :prev), node)
        next_node
    end)
    set_cell_computation!(getfield(node, :prev), () -> begin
        preceding = row_node.prev
        preceding === nothing && return nothing
        prev_node = _make_row_graphics_node(p, w, st, k - 1, preceding)
        set_cell_value!(getfield(prev_node, :next), node)
        prev_node
    end)
    node
end

# ── The printer ──────────────────────────────────────────────────────────────

function _print_table_parts(p::WidgetTableToGraphicsCanvas, recursion, w::WidgetTable, ctx)
    # Headers that are a list make the columns a list too.
    w.column_headers isa ListNode && return _print_table_column_parts(p, recursion, w, ctx)
    inset_width, inset_height = _inset_total(p, w)
    inner = ctx === nothing ? nothing : with_inner_size(ctx; width = inset_width, height = inset_height)
    height = inner === nothing ? nothing : get_exact_height(inner)
    _check_table_parts(w, height)
    # The parts, built again when the table changes its shape, and only then: a
    # column added or removed, a header, an alignment or a cell policy changed.
    # What a part reads as it prints, such as the rows that the grid of the cells
    # walks, is no change of shape, so the parts are built in a cell of their own
    # that the parts only peek at.
    # The width of a column is no change of shape: a drag writes the `policy` of
    # its column, which the shape does not read.
    shape = Cell(@computation begin
        n = something(get_widget_table_column_count(w), 0)
        (n, Any[header for header in w.column_headers],
         Any[(_wt_column_align(w, c), _wt_column_cell_policy(w, c)) for c in 1:n], w.cell_policy, w.corner)
    end)
    parts = Cell(@computation begin
        shape[]
        peek(Cell(@computation _print_vector_column_parts(p, recursion, w, inner, height)))
    end)
    # Read once now, so a table that a list can not draw raises its error here.
    parts[]
    _make_table_list_iomap(p, w, parts)
end

# The parts of a table whose columns are a vector, as `(; state, regions)`.
function _print_vector_column_parts(p::WidgetTableToGraphicsCanvas, recursion, w::WidgetTable, inner,
                                    height)
    n = something(get_widget_table_column_count(w), 0)
    pad_x = Int(p.cell_padding.left[])
    pad_y = Int(p.cell_padding.top[])
    bw = max(1, _sc(Int(w.border_width)))
    hgap = 2 * pad_x + bw
    vgap = 2 * pad_y + bw
    content_x, content_y = _content_offset(p, w)
    aligns = Symbol[_wt_column_align(w, c) for c in 1:n]
    offers = Bool[_wt_column_cell_policy(w, c) === :wrap for c in 1:n]
    offset = getfield(w, :scroll_position)
    # The width of every column, which the cells decide once they print.
    widths = Cell[Cell(0) for _ in 1:n]
    # The corner first: it is a floor for the header row and the header column.
    # The header row and the cells are offered the width beside the header
    # column, which it decides once it prints.
    corner = _print_table_corner(recursion, w, inner)
    header_width = Cell(0)
    beside = with_inner_size(inner; width = header_width)

    # The header row first: the cells read the width of each header.
    column_header_pane = nothing
    if length(w.column_headers) > 0
        headers = CellVector(Cell[Cell(c <= length(w.column_headers) && w.column_headers[c] !== nothing ?
                                       w.column_headers[c] : _wt_empty_cell()) for c in 1:n])
        grid = GridLayout(headers, Cell(n), Cell(:left), Cell(:top), Cell(hgap), Cell(vgap),
                          Cell(aligns), Cell(Fixed(0)), _get_header_row_policy(corner),
                          Cell(@computation Any[Fixed(Int(widths[c][])) for c in 1:n]),
                          Cell(Any[]), Cell(offers), Cell(Bool[]), Cell(nothing))
        header_offset = Cell(@computation Point2D(Int((offset[]::Point2D).x[]), 0))
        pane = _make_part_pane(grid, header_offset, Inset(bw + pad_y, pad_y, bw + pad_x, bw + pad_x))
        column_header_pane = print_child(recursion, pane, with_free_axis(beside, :y))
    end
    header_height = column_header_pane === nothing ? Cell(0) : Cell(@computation Int(column_header_pane.output.h))

    header_grid = column_header_pane === nothing ? nothing : column_header_pane.content_iomap
    get_header(c) = header_grid === nothing ? nothing : header_grid.child_iomaps[c][3]
    policies = Cell(@computation Any[_get_cells_column_policy(w, c, get_header(c)) for c in 1:n])
    grid = GridLayout(_get_row_list(w), Cell(n), Cell(:left), Cell(:top), Cell(hgap), Cell(vgap),
                      Cell(aligns), getfield(w, :column_policy), getfield(w, :row_policy),
                      policies, Cell(Any[]), Cell(offers), Cell(Bool[]), Cell(nothing))
    cells_height = Cell(@computation Int32(max(0, Int(height[]) - Int(header_height[]))))
    row_header_pane = _print_header_column(recursion, w, inner, corner, cells_height, pad_x, pad_y, bw)
    row_header_pane === nothing || set_cell_computation!(header_width, () -> Int(row_header_pane.output.w))
    cells_pane = print_child(recursion,
                             _make_part_pane(grid, offset, Inset(bw + pad_y, bw + pad_y, bw + pad_x, bw + pad_x)),
                             with_exact_size(beside; height = cells_height))
    cells_grid = cells_pane.content_iomap
    for c in 1:n
        set_cell_computation!(widths[c], () -> Int(cells_grid.col_w[c][]))
    end
    edges = Cell(@computation compute_axis_offsets(Int[Int(cells_grid.col_w[c][]) for c in 1:n], hgap))
    st = WidgetTablePartsState(n, bw, pad_x, pad_y, column_header_pane, cells_pane, header_height, edges,
                               false, row_header_pane, corner, header_width)
    parts_x = Cell(@computation Int32(content_x + Int(header_width[])))

    # The graphics of the header row: its band, the bands of a lit or a
    # selected column, the rule above it, and the rule of every column.
    divider = _get_state_stroke(p, w, :divider).color
    header_row_color = _get_state_color(p, w, :header_row)
    header_region = nothing
    if column_header_pane !== nothing
        band_height = Cell(@computation Int(header_height[]) - bw)
        bands = Any[_make_row_band(p, w, st, nothing, band_height, :light),
                    _make_row_band(p, w, st, nothing, band_height, :selection)]
        edge_light = _make_column_edge_light(p, w, st, Cell(@computation Int(header_height[])))
        header_graphics = CellVector(@computation begin
            width = last(edges[]) + bw
            h = Int(header_height[])
            out = Any[GraphicsRect(0, 0, width, h; color = header_row_color), bands...,
                      GraphicsRect(0, 0, width, bw; color = divider)]
            for edge in edges[]
                push!(out, GraphicsRect(edge, 0, bw, h; color = divider))
            end
            # Where a press starts the drag of the width of a column.
            for edge in edges[][2:end]
                push!(out, _make_column_edge_region(edge, bw, h))
            end
            push!(out, edge_light)
            out
        end)
        header_region = _make_part_region(column_header_pane, header_graphics;
                                          x = parts_x, y = Cell(Int32(content_y)), pad_x, pad_y, bw)
    end
    # The graphics of the rows mirror the rows that the grid placed. A new head
    # in `cells` builds them again, and no head is no rows.
    mirror = Cell(@computation begin
        head = get_grid_list_head(cells_grid)
        head isa ListNode ? _make_row_graphics_node(p, w, st, 1, head) : CellVector()
    end)
    cells_region = _make_part_region(cells_pane, mirror; x = parts_x,
                                     y = Cell(@computation Int32(content_y + Int(header_height[]))),
                                     pad_x, pad_y, bw, layout = layout_vertical)

    regions = _collect_table_regions(p, w, st, header_region, cells_region, content_x, content_y)
    (; state = st, regions)
end

# The policy of the header row: as tall as its headers, and at least as tall as
# the corner.
_get_header_row_policy(corner) =
    corner === nothing ? Cell(Content) :
        Cell(@computation SizePolicy(_get_part_child_height(corner), nothing, nothing, 0))

# The regions of the parts of a table of a list, in the order they are drawn:
# the corner and the header column when there are row headers, the header row
# when there are column headers, and the cells.
function _collect_table_regions(p::WidgetTableToGraphicsCanvas, w::WidgetTable, st::WidgetTablePartsState,
                                header_region, cells_region, content_x::Int, content_y::Int)
    regions = Any[_make_corner_region(p, w, st, content_x, content_y),
                  _make_header_column_region(p, w, st, content_x, content_y), header_region, cells_region]
    Any[region for region in regions if region !== nothing]
end

# The IO map of a table of a list, from a cell of its parts: its canvas holds the
# box of the table, the regions of the parts, and a transparent rect the size of
# the table, so a press anywhere on it reaches the table through a container
# that gates on a hit. Its state is the state of the parts that the cell holds.
function _make_table_list_iomap(p::WidgetTableToGraphicsCanvas, w::WidgetTable, parts::Cell)
    inset_width, inset_height = _inset_total(p, w)
    state = Cell(@computation parts[].state)
    table_w = Cell(@computation (st = state[];
                                 Int32(Int(st.header_width[]) + Int(st.cells_pane.output.w) + inset_width)))
    table_h = Cell(@computation (st = state[];
                                 Int32(Int(st.header_height[]) + Int(st.cells_pane.output.h) + inset_height)))
    hit_target = GraphicsRect(0, 0, 0, 0; color = color_transparent, radius = 0)
    set_cell_computation!(getfield(hit_target, :w), () -> Int32(table_w[]))
    set_cell_computation!(getfield(hit_target, :h), () -> Int32(table_h[]))
    box = _get_box_insets(p, w)
    colors = _get_box_colors(p, w)
    elements = CellVector(@computation begin
        out = Any[hit_target]
        _push_box_parts!(out, box, colors, Int(table_w[]) - inset_width, Int(table_h[]) - inset_height)
        append!(out, parts[].regions)
        out
    end)
    ox, oy = _origin(w.position::Point2D)
    canvas = GraphicsCanvas(Cell(Int32(ox)), Cell(Int32(oy)), table_w, table_h, elements,
                            layout_none, true, Cell(nothing))
    WidgetTableListIoMap(p, w, canvas, state)
end

# ── Columns that are a list ──────────────────────────────────────────────────

# The node of the policy of column `k`, which mirrors the node of its header:
# the policy that `given`, the node of the list of policies of the table, holds,
# else `Fixed`, `width` wide and at least as wide as the header, which the grid
# of the header row prints; `header_grid` holds that grid once it prints.
function _make_column_policy_node(header_node::ListNode, k::Int, width::Int, header_grid::Cell, given)
    node = ListNode(Fixed(width))
    set_cell_computation!(getfield(node, :value), () -> begin
        column = given isa ListNode ? given.value : nothing
        policy = column isa WidgetTableColumn ? column.policy : nothing
        policy isa SizePolicy && return policy
        grid = header_grid[]
        cell = grid === nothing ? nothing : find_grid_list_cell(grid, 1, k)
        Fixed(max(width, cell === nothing ? 0 : _get_part_child_width(cell[3])))
    end)
    set_cell_computation!(getfield(node, :next), () -> begin
        following = header_node.next
        following === nothing && return nothing
        next_node = _make_column_policy_node(following, k + 1, width, header_grid,
                                             given isa ListNode ? given.next : nothing)
        set_cell_value!(getfield(next_node, :prev), node)
        next_node
    end)
    set_cell_computation!(getfield(node, :prev), () -> begin
        preceding = header_node.prev
        preceding === nothing && return nothing
        prev_node = _make_column_policy_node(preceding, k - 1, width, header_grid,
                                             given isa ListNode ? given.prev : nothing)
        set_cell_value!(getfield(prev_node, :next), node)
        prev_node
    end)
    node
end

# A list that mirrors `column_node`, a list of the data of the columns, with the
# alignment of each column, which a grid of a list reads beside its columns.
function _make_column_align_node(column_node::ListNode)
    node = ListNode(:left)
    set_cell_computation!(getfield(node, :value), () -> begin
        column = column_node.value
        align = column isa WidgetTableColumn ? column.align : nothing
        align === nothing ? :left : align
    end)
    set_cell_computation!(getfield(node, :next), () -> begin
        following = column_node.next
        following === nothing && return nothing
        next_node = _make_column_align_node(following)
        set_cell_value!(getfield(next_node, :prev), node)
        next_node
    end)
    set_cell_computation!(getfield(node, :prev), () -> begin
        preceding = column_node.prev
        preceding === nothing && return nothing
        prev_node = _make_column_align_node(preceding)
        set_cell_value!(getfield(prev_node, :next), node)
        prev_node
    end)
    node
end

# The rule to the left of the column of `column_node`, from `top` down `height`
# in the coordinates of the rules, and the rule after it when it is the last
# column: a list that mirrors the columns that a grid placed, so only the
# columns that a viewport shows have rules. With `edge_regions`, each canvas also
# holds the regions of the pointer shape over the bands of the edge at its left,
# after a column, and of the edge at its right: a list walks only the column at a
# point, so each half of a band is in the canvas of its own column.
function _make_column_rules_node(st::WidgetTablePartsState, column_node::ListNode, top::Cell,
                                 height::Cell, color; edge_regions::Bool = false)
    column = column_node.value
    hgap = 2 * st.pad_x + st.bw
    elements = CellVector(@computation begin
        out = Any[GraphicsRect(0, Int(top[]), st.bw, Int(height[]); color)]
        column_node.next === nothing &&
            push!(out, GraphicsRect(Int(column.w) + hgap, Int(top[]), st.bw, Int(height[]); color))
        if edge_regions
            column_node.prev === nothing ||
                push!(out, _make_column_edge_region(0, st.bw, Int(height[])))
            push!(out, _make_column_edge_region(Int(column.w) + hgap, st.bw, Int(height[])))
        end
        out
    end)
    canvas = GraphicsCanvas(getfield(column, :x), Cell(Int32(0)),
                            Cell(@computation Int32(Int(column.w) + hgap)), Cell(Int32(0)), elements,
                            layout_none, true, Cell(nothing))
    node = ListNode(canvas)
    set_cell_computation!(getfield(node, :next), () -> begin
        following = column_node.next
        following === nothing && return nothing
        next_node = _make_column_rules_node(st, following, top, height, color; edge_regions)
        set_cell_value!(getfield(next_node, :prev), node)
        next_node
    end)
    set_cell_computation!(getfield(node, :prev), () -> begin
        preceding = column_node.prev
        preceding === nothing && return nothing
        prev_node = _make_column_rules_node(st, preceding, top, height, color; edge_regions)
        set_cell_value!(getfield(prev_node, :next), node)
        prev_node
    end)
    node
end

# A canvas whose elements are the rules of the columns that `grid` placed, and with
# `edge_regions` the regions of the pointer shape over the edges of the columns.
_make_column_rules(st::WidgetTablePartsState, grid, top::Cell, height::Cell, color;
                   edge_regions::Bool = false) =
    GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)),
                   Cell(@computation (head = get_grid_list_column_head(grid);
                                      head isa ListNode ?
                                          _make_column_rules_node(st, head, top, height, color;
                                                                  edge_regions) :
                                          CellVector())),
                   layout_horizontal, false, Cell(nothing))

# The printer of a table whose rows are a list and whose `column_headers` are a
# list too, anchored at the same column as the cells of every row. The columns
# are `Fixed`: `column_policy`, and at least as wide as the header, from a list
# of policies that mirrors the headers, which the header row and the cells
# share. The header row is as tall as the header of the head column.
function _print_table_column_parts(p::WidgetTableToGraphicsCanvas, recursion, w::WidgetTable, ctx)
    inset_width, inset_height = _inset_total(p, w)
    inner = ctx === nothing ? nothing : with_inner_size(ctx; width = inset_width, height = inset_height)
    height = inner === nothing ? nothing : get_exact_height(inner)
    _check_table_parts(w, height)
    base = w.column_policy
    (base isa SizePolicy && base.preferred !== nothing && (base.weight === nothing || base.weight == 0)) ||
        error("WidgetTable: a table whose columns are a list needs a Fixed column policy")
    pad_x = Int(p.cell_padding.left[])
    pad_y = Int(p.cell_padding.top[])
    bw = max(1, _sc(Int(w.border_width)))
    hgap = 2 * pad_x + bw
    vgap = 2 * pad_y + bw
    content_x, content_y = _content_offset(p, w)
    offset = getfield(w, :scroll_position)
    width = Int(base.preferred)
    # The corner first, and the width beside the header column, as in
    # `_print_table_parts`.
    corner = _print_table_corner(recursion, w, inner)
    header_width = Cell(0)
    beside = with_inner_size(inner; width = header_width)
    # The grid of the header row, once it prints: the policies read the width
    # of each header from it, and the header row its height.
    header_grid = Cell(nothing)
    policies = Cell(@computation begin
        headers = w.column_headers
        given = w.columns
        headers isa ListNode ?
            _make_column_policy_node(headers, 1, width, header_grid, given isa ListNode ? given : nothing) :
            nothing
    end)
    header_row_policy = Cell(@computation begin
        grid = header_grid[]
        cell = grid === nothing ? nothing : find_grid_list_cell(grid, 1, 1)
        Fixed(max(_get_part_child_height(corner), cell === nothing ? 0 : _get_part_child_height(cell[3])))
    end)
    header_row = Cell(@computation (headers = w.column_headers;
                                    headers isa ListNode ? ListNode(headers) : CellVector()))
    # The alignment of each column, a list beside the headers when the data of
    # the columns is a list, which the header row and the cells read alike.
    aligns = Cell(@computation (columns = w.columns;
                                columns isa ListNode ? _make_column_align_node(columns) : Symbol[]))
    grid = GridLayout(header_row, Cell(1), Cell(:left), Cell(:top), Cell(hgap), Cell(vgap),
                      aligns, Cell(Fixed(width)), header_row_policy, policies,
                      Cell(Any[]), Cell(Bool[false]), Cell(Bool[false]), Cell(nothing))
    pane = _make_part_pane(grid, Cell(@computation Point2D(Int((offset[]::Point2D).x[]), 0)),
                           Inset(bw + pad_y, pad_y, bw + pad_x, bw + pad_x))
    # A grid of a list reports no height, so the pane is offered the height of
    # the row and of its own padding.
    header_offer = Cell(@computation Int32(Int(header_row_policy[].preferred) + bw + 2 * pad_y))
    column_header_pane = print_child(recursion, pane, with_exact_size(beside; height = header_offer))
    header_grid[] = column_header_pane.content_iomap
    header_height = Cell(@computation Int(column_header_pane.output.h))

    grid = GridLayout(_get_row_list(w), Cell(1), Cell(:left), Cell(:top), Cell(hgap), Cell(vgap),
                      aligns, Cell(Fixed(width)), getfield(w, :row_policy),
                      policies, Cell(Any[]), Cell(Bool[false]), Cell(Bool[]), Cell(nothing))
    cells_height = Cell(@computation Int32(max(0, Int(height[]) - Int(header_height[]))))
    row_header_pane = _print_header_column(recursion, w, inner, corner, cells_height, pad_x, pad_y, bw)
    row_header_pane === nothing || set_cell_computation!(header_width, () -> Int(row_header_pane.output.w))
    cells_pane = print_child(recursion,
                             _make_part_pane(grid, offset, Inset(bw + pad_y, bw + pad_y, bw + pad_x, bw + pad_x)),
                             with_exact_size(beside; height = cells_height))
    cells_grid = cells_pane.content_iomap
    st = WidgetTablePartsState(0, bw, pad_x, pad_y, column_header_pane, cells_pane, header_height,
                               Cell(Int[]), true, row_header_pane, corner, header_width)
    parts_x = Cell(@computation Int32(content_x + Int(header_width[])))

    # The graphics of the header row: its band, the bands of a lit or a
    # selected column, the rule above it, and the rules of its columns; and of
    # the cells: the rows, and the rules of the columns down the whole pane.
    divider = _get_state_stroke(p, w, :divider).color
    header_row_color = _get_state_color(p, w, :header_row)
    band_height = Cell(@computation Int(header_height[]) - bw)
    bands = Any[_make_row_band(p, w, st, nothing, band_height, :light),
                _make_row_band(p, w, st, nothing, band_height, :selection)]
    span = Cell(@computation _get_table_row_span(st))
    header_rules = _make_column_rules(st, column_header_pane.content_iomap, Cell(0), header_height, divider;
                                      edge_regions = true)
    edge_light = _make_column_edge_light(p, w, st, Cell(@computation Int(header_height[])))
    header_graphics = CellVector(@computation begin
        left, row_width = span[]
        h = Int(header_height[])
        Any[GraphicsRect(left, 0, row_width, h; color = header_row_color), bands...,
            GraphicsRect(left, 0, row_width, bw; color = divider), header_rules, edge_light]
    end)
    header_region = _make_part_region(column_header_pane, header_graphics;
                                      x = parts_x, y = Cell(Int32(content_y)), pad_x, pad_y, bw)
    mirror = Cell(@computation begin
        head = get_grid_list_head(cells_grid)
        head isa ListNode ? _make_row_graphics_node(p, w, st, 1, head) : CellVector()
    end)
    rows = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), mirror,
                          layout_vertical, false, Cell(nothing))
    content = _get_part_content(cells_pane)
    cells_rules = _make_column_rules(st, cells_grid, Cell(@computation -Int(content.y)),
                                     Cell(@computation Int(cells_pane.output.h)), divider)
    cells_region = _make_part_region(cells_pane, CellVector(Cell[Cell(rows), Cell(cells_rules)]);
                                     x = parts_x,
                                     y = Cell(@computation Int32(content_y + Int(header_height[]))),
                                     pad_x, pad_y, bw)
    regions = _collect_table_regions(p, w, st, header_region, cells_region, content_x, content_y)
    _make_table_list_iomap(p, w, Cell((; state = st, regions)))
end

# ── Places ───────────────────────────────────────────────────────────────────

# A point of the pane of a part, in the coordinates of the rules of that part.
function _get_rule_point(st::WidgetTablePartsState, pane, x::Int, y::Int)
    content = _get_part_content(pane)
    cox, coy = _content_offset(get_content_iomap(pane).projection, pane.input)
    (x - cox + st.pad_x + st.bw - Int(content.x), y - coy + st.pad_y + st.bw - Int(content.y))
end

# The part under the point `(x, y)` of the table, as `(part, x, y)` with the
# point in the coordinates of the rules of the part, which is `:header` or
# `:cells`, or `:row_header` for the header column; for `:corner`, the point is
# in the coordinates of the corner. A point on the margin, the border or the
# padding of the table is moved into its parts, as every reader that maps a
# place to a row or a column does. `nothing` outside the table.
function _find_table_part_at(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableListIoMap,
                             x::Int, y::Int)
    st = iomap.state
    canvas = iomap.output
    (0 <= x < Int(canvas.w) && 0 <= y < Int(canvas.h)) || return nothing
    content_x, content_y = _content_offset(p, iomap.input)
    cells = st.cells_pane.output
    header_h = Int(st.header_height[])
    header_w = Int(st.header_width[])
    local_x = clamp(x - content_x, 0, max(0, header_w + Int(cells.w) - 1))
    local_y = clamp(y - content_y, 0, max(0, header_h + Int(cells.h) - 1))
    if local_x < header_w
        local_y < header_h && return (:corner, local_x - st.bw - st.pad_x, local_y - st.bw - st.pad_y)
        return (:row_header, _get_rule_point(st, st.row_header_pane, local_x, local_y - header_h)...)
    end
    local_x -= header_w
    local_y < header_h && return (:header, _get_rule_point(st, st.column_header_pane, local_x, local_y)...)
    (:cells, _get_rule_point(st, st.cells_pane, local_x, local_y - header_h)...)
end

# The row whose box holds `y`, in the coordinates of the rules of the cells:
# the rule above the row, its padding, its cells and the padding under them.
# It is walked to from the head, and `nothing` past an end.
function _find_table_row_at(st::WidgetTablePartsState, y::Int)
    node = get_grid_list_head(st.cells_pane.content_iomap)
    node isa ListNode || return nothing
    vgap = 2 * st.pad_y + st.bw
    k = 1
    while y < Int(node.value.y)
        node = node.prev
        node === nothing && return nothing
        k -= 1
    end
    while y >= Int(node.value.y) + Int(node.value.h) + vgap
        node = node.next
        node === nothing && return nothing
        k += 1
    end
    k
end

# The IO map of the cell in row `k` and column `c`, and the place of its canvas
# in the coordinates of the rules; `nothing` for a row past an end or an empty
# cell. The header of row `k` is the cell in row `k` and column 1 of the pane of
# the header column.
_find_table_cell(st::WidgetTablePartsState, k::Int, c::Int) = _find_part_cell(st, st.cells_pane, k, c)

_find_table_row_header(st::WidgetTablePartsState, k::Int) =
    st.row_header_pane === nothing ? nothing : _find_part_cell(st, st.row_header_pane, k, 1)

function _find_part_cell(st::WidgetTablePartsState, pane, k::Int, c::Int)
    grid = pane.content_iomap
    found = find_grid_list_row(grid, k)
    found === nothing && return nothing
    row = found[1]
    cell = find_grid_list_cell(grid, k, c)
    cell === nothing && return nothing
    (x_cell, y_cell, cim) = cell
    cim === nothing && return nothing
    out = cim.output
    out isa GraphicsCanvas || return nothing
    (cim, Int(x_cell[]) + Int(out.x) + st.pad_x + st.bw,
          Int(row.y) + Int(y_cell[]) + Int(out.y) + st.pad_y + st.bw)
end

# The IO map of the header of column `c`, and the place of its canvas in the
# coordinates of the rules of the header row; `nothing` for no header.
function _find_table_header_cell(st::WidgetTablePartsState, c::Int)
    st.column_header_pane === nothing && return nothing
    header = _find_header_entry(st, c)
    header === nothing && return nothing
    (x_cell, y_cell, cim) = header
    cim === nothing && return nothing
    out = cim.output
    out isa GraphicsCanvas || return nothing
    (cim, Int(x_cell[]) + Int(out.x) + st.pad_x + st.bw, Int(y_cell[]) + Int(out.y) + st.pad_y + st.bw)
end

# The entry `(x, y, iomap)` of the header of column `c` in the grid of the
# header row: a grid of one row, whose cells are a vector or a list.
function _find_header_entry(st::WidgetTablePartsState, c::Int)
    grid = st.column_header_pane.content_iomap
    st.column_list && return find_grid_list_cell(grid, 1, c)
    entries = grid.child_iomaps
    1 <= c <= length(entries) ? entries[c] : nothing
end

# ── References ───────────────────────────────────────────────────────────────

# The image of `children` and `inner` in the grid of the part in `pane`, from the
# canvas of the table: the steps to the canvas of the pane, found by identity
# after the parts of the box, and the answer of the pane for `content.children`
# and `inner`.
function _map_part_forward(iomap, pane, inner::Reference)
    image = map_reference_forward(pane.projection, pane,
        ConcreteReference(FieldReferenceStep("content"),
            ConcreteReference(FieldReferenceStep("children"), inner)))
    image === nothing && return nothing
    outer = find_node_reference(iomap.output, unwrap_cell(pane.output))
    outer === nothing ? nothing : concat_references(outer, image)
end

# Forward: `cells[k][c].…` is the answer of the pane of the cells for
# `children[k][c].…`, once row `k` is built, and `column_headers[c].…` is the
# answer of the pane of the header row for `children[c].…`, or for
# `children[1][c].…` when the columns are a list. `row_headers[k].…` is the
# answer of the pane of the header column for `children[k][1].…`, and
# `corner.…` the answer of the corner. The table itself is its own canvas. A
# whole row has no node of its own, because its band is drawn in the graphics
# of the rows, so it has no image.
function map_reference_forward(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableListIoMap, reference)
    reference isa Reference || return nothing
    reference = strip_reference_types(reference)
    reference isa EmptyReference && return EmptyReference()
    reference isa ConcreteReference || return nothing
    st = iomap.state
    head = reference.head
    head isa FieldReferenceStep || return nothing
    if head.name == "column_headers"
        st.column_header_pane === nothing && return nothing
        tail = reference.tail
        (tail isa ConcreteReference && tail.head isa RangeReferenceStep) || return nothing
        inner = st.column_list ? ConcreteReference(RangeReferenceStep(0, 1), tail) : tail
        return _map_part_forward(iomap, st.column_header_pane, inner)
    elseif head.name == "cells"
        split = _wt_cell_split(iomap.input, reference)
        split === nothing && return nothing
        # The pane of the cells lays out rows, so the rest goes in as `[r][c]…`
        # whatever the order of the table.
        k, c, rest = split
        return _map_part_forward(iomap, st.cells_pane,
            ConcreteReference(RangeReferenceStep(k - 1, k), ConcreteReference(RangeReferenceStep(c - 1, c), rest)))
    elseif head.name == "row_headers"
        st.row_header_pane === nothing && return nothing
        tail = reference.tail
        (tail isa ConcreteReference && tail.head isa RangeReferenceStep) || return nothing
        inner = ConcreteReference(tail.head, ConcreteReference(RangeReferenceStep(0, 1), tail.tail))
        return _map_part_forward(iomap, st.row_header_pane, inner)
    elseif head.name == "corner"
        st.corner === nothing && return nothing
        image = map_reference_forward(st.corner.projection, st.corner, reference.tail)
        image === nothing && return nothing
        outer = find_node_reference(iomap.output, unwrap_cell(st.corner.output))
        return outer === nothing ? nothing : concat_references(outer, image)
    end
    nothing
end

# Backward: a point maps to the corner, the row header, the column header or
# the cell at it, the reference that an Alt+click there selects. A path into the
# canvas of a list names a row by no fixed index, so it maps to no path into the
# table.
function map_reference_backward(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableListIoMap,
                                reference)
    point = find_reference_point(reference)
    point === nothing && return nothing
    found = _find_table_part_at(p, iomap, point.x, point.y)
    found === nothing && return nothing
    part, x, y = found
    st = iomap.state
    part === :corner && return ConcreteReference(FieldReferenceStep("corner"), EmptyReference())
    if part === :row_header
        k = _find_table_row_at(st, y)
        return k === nothing ? nothing : ConcreteReference(FieldReferenceStep("row_headers"),
            ConcreteReference(RangeReferenceStep(k - 1, k), EmptyReference()))
    end
    if part === :header
        edge = _find_table_column_edge_at(st, x)
        edge === nothing || return _wt_edge_ref(first(edge))
    end
    c = _find_table_column_at(st, x)
    c === nothing && return nothing
    part === :header && return _wt_column_header_ref(c)
    k = _find_table_row_at(st, y)
    k === nothing ? nothing : _wt_cell_ref(iomap.input, k, c)
end

# ── Reading ──────────────────────────────────────────────────────────────────

# An event with a place, sent to the cell in row `k` and column `c`, from the
# point `(x, y)` in the coordinates of the rules. The answer is rooted under
# `cells[k][c]`; an operation that names its own document, such as the toggle
# of a checkbox, stays as it is. `nothing` when the cell has nothing to say.
function _read_table_cell_press(w::WidgetTable, st::WidgetTablePartsState, k::Int, c::Int, g::MouseClick,
                                x::Int, y::Int)
    found = _find_table_cell(st, k, c)
    found === nothing && return nothing
    cim, left, top = found
    op = read_intent(cim.projection, cim, MouseClick(g.button, x - left, y - top, g.count,
                                                     g.modifiers; time = g.time))
    op === nothing && return nothing
    reroot_operation(op, _wt_get_cell_steps(w, k, c))
end

# A left press on a header, `found` its IO map and the place of its canvas in
# the coordinates of the rules of its part, from the point `(x, y)` there, read
# by the header and rooted under `steps`; `nothing` for no header or when the
# header has nothing to say.
function _read_table_header_press(found, steps::Tuple, g::MouseClick, x::Int, y::Int)
    found === nothing && return nothing
    cim, left, top = found
    op = read_intent(cim.projection, cim, MouseClick(g.button, x - left, y - top, g.count,
                                                     g.modifiers; time = g.time))
    op === nothing && return nothing
    reroot_operation(op, steps)
end

# A left press. An Alt+press selects the part itself: the corner, a header or a
# cell. A plain press goes to the part first: the corner, a header or a cell. A
# press that the part declines selects its line: the corner the table, a row
# header its row, a column header its column, `columns[c]`, and a cell its row —
# a label has nothing to say to one, and a table of text is a table of rows.
function _read_table_parts_press(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableListIoMap,
                                 g::MouseClick)
    st = iomap.state
    found = _find_table_part_at(p, iomap, g.x, g.y)
    found === nothing && return nothing
    part, x, y = found
    if part === :corner
        g.modifiers.alt && st.corner !== nothing &&
            return ReplaceSelectionOperation(ConcreteReference(FieldReferenceStep("corner"), EmptyReference()))
        op = _read_table_corner(st, MouseClick(g.button, x, y, g.count, g.modifiers; time = g.time))
        return op === nothing ? ReplaceSelectionOperation(EmptyReference()) : op
    end
    if part === :row_header
        k = _find_table_row_at(st, y)
        k === nothing && return nothing
        g.modifiers.alt && return ReplaceSelectionOperation(_wt_row_header_ref(k))
        op = _read_table_header_press(_find_table_row_header(st, k),
                                      (FieldReferenceStep("row_headers"), RangeReferenceStep(k - 1, k)), g, x, y)
        return op === nothing ? ReplaceSelectionOperation(_wt_row_ref(k)) : op
    end
    c = _find_table_column_at(st, x)
    c === nothing && return nothing
    if part === :header
        g.modifiers.alt && return ReplaceSelectionOperation(_wt_column_header_ref(c))
        op = _read_table_header_press(_find_table_header_cell(st, c),
                                      (FieldReferenceStep("column_headers"), RangeReferenceStep(c - 1, c)), g, x, y)
        return op === nothing ? ReplaceSelectionOperation(_wt_col_ref(c)) : op
    end
    k = _find_table_row_at(st, y)
    k === nothing && return nothing
    g.modifiers.alt && return ReplaceSelectionOperation(_wt_cell_ref(iomap.input, k, c))
    op = _read_table_cell_press(iomap.input, st, k, c, g, x, y)
    op === nothing ? ReplaceSelectionOperation(_wt_row_ref(k)) : op
end

# A turn of the wheel over either part goes to the pane of the cells. The table
# adds the row at the top to what the pane answers, and moves the head of the
# list to that row when it is far from the head.
function _read_table_parts_wheel(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableListIoMap,
                                 evt::MouseScroll)
    content_x, content_y = _content_offset(p, iomap.input)
    scroll = _read_cells_wheel(iomap.output, iomap.state.cells_pane,
                               content_x + Int(iomap.state.header_width[]),
                               content_y + Int(iomap.state.header_height[]), evt)
    _add_top_row(iomap, scroll)
end

# How far from the head the row at the top may be before the table moves the
# head to it. A small number builds the visible rows again often; a large one
# keeps more rows reachable from the head.
const _TABLE_RELOCATION_DISTANCE = 200

# The offset that a scroll writes, or `nothing` for any other answer.
function _find_written_offset(op)
    op isa ReplaceViewStateOperation || return nothing
    inner = get_wrapped_operation(op)
    (inner isa ReplaceReferencedValueOperation && inner.value isa Point2D &&
     inner.reference isa ConcreteReference && inner.reference.head isa FieldReferenceStep &&
     inner.reference.head.name == "scroll_position") || return nothing
    inner.value::Point2D
end

# A scroll of the cells, and the write of the row at the top of the offset it
# writes when that row changes. When the row is more than
# `_TABLE_RELOCATION_DISTANCE` rows from the head, the answer moves the head of
# the body (`_write_body_head`), and of `row_headers` when they are a list, to
# it instead, and moves the offset by the place of that row, so the same row
# stays at the same place on the screen; a selection of a row moves with it. A projection that owns
# the rows turns the write of `cells` into an edit of its own.
function _add_top_row(iomap::WidgetTableListIoMap, op)
    w = iomap.input
    offset = _find_written_offset(op)
    offset === nothing && return op
    st = iomap.state
    x, y = Int(offset.x[]), Int(offset.y[])
    k = _find_table_row_at(st, y + st.pad_y + st.bw)
    k === nothing && return op
    if abs(k - 1) <= _TABLE_RELOCATION_DISTANCE
        moved = st.column_list ? _move_head_column(iomap, x, y) : nothing
        moved === nothing || return moved
        k == w.top_row && return op
        return CompoundOperation(Any[op, _write_view_state(w, "top_row", k)])
    end
    writes = _write_body_head(w, k)
    found = find_grid_list_row(st.cells_pane.content_iomap, k)
    (writes === nothing || found === nothing) && return op
    moved = Any[writes...,
                _write_view_state(w, "scroll_position", Point2D(x, y - Int(found[1].y))),
                _write_view_state(w, "top_row", 1)]
    # The row headers move in step with the rows.
    header = _find_list_node(w.row_headers, k)
    header === nothing || push!(moved, _write_view_state(w, "row_headers", header))
    selection = _shift_row_reference(w, w.selection, k - 1)
    selection === w.selection || push!(moved, ReplaceSelectionOperation(selection))
    CompoundOperation(moved)
end

# When the column at the left edge of the offset `(x, y)` is more than
# `_TABLE_RELOCATION_DISTANCE` columns from the head column, the answer that
# moves the head column to it: `column_headers` and a list alignment written to
# their nodes of that column, `cells` to a list that mirrors the rows with each
# row from that column on, the offset less the place of that column, and a
# selection of a column or a cell moved by the same number of columns.
# `nothing` when the column is near the head. A projection that owns
# the columns turns the write of `column_headers` into an edit of its own.
function _move_head_column(iomap::WidgetTableListIoMap, x::Int, y::Int)
    w = iomap.input
    st = iomap.state
    c = _find_table_column_at(st, x + st.pad_x + st.bw)
    (c === nothing || abs(c - 1) <= _TABLE_RELOCATION_DISTANCE) && return nothing
    header = _find_list_node(w.column_headers, c)
    span = _get_table_column_span(st, c)
    # A column-major table moves the head of its list of columns.
    body = _is_column_major(w) ? _find_list_node(w.cells, c) : _make_advanced_row_node(w.cells, c)
    (header === nothing || span === nothing || body === nothing) && return nothing
    moved = Any[_write_view_state(w, "column_headers", header),
                _write_view_state(w, "cells", body),
                _write_view_state(w, "scroll_position", Point2D(x - span[1], y))]
    columns = w.columns
    columns isa ListNode && push!(moved, _write_view_state(w, "columns", _find_list_node(columns, c)))
    selection = _shift_column_reference(w, w.selection, c - 1)
    selection === w.selection || push!(moved, ReplaceSelectionOperation(selection))
    CompoundOperation(moved)
end

# The node of a list that mirrors the rows of `row_node`, each row from its
# column `c` on, counted from the head of the row. A node is built when a walk
# first reaches it, so a row is walked to its column `c` once, when it shows.
function _make_advanced_row_node(row_node, c::Int)
    row_node isa ListNode || return row_node
    node = ListNode(nothing)
    set_cell_computation!(getfield(node, :value), () -> _find_list_node(row_node.value, c))
    set_cell_computation!(getfield(node, :next), () -> begin
        following = row_node.next
        following === nothing && return nothing
        next_node = _make_advanced_row_node(following, c)
        set_cell_value!(getfield(next_node, :prev), node)
        next_node
    end)
    set_cell_computation!(getfield(node, :prev), () -> begin
        preceding = row_node.prev
        preceding === nothing && return nothing
        prev_node = _make_advanced_row_node(preceding, c)
        set_cell_value!(getfield(prev_node, :next), node)
        prev_node
    end)
    node
end

# `columns[c]…`, `column_headers[c]…` and the cell paths of `w` with `c` counted
# from a head column `distance` columns further on; any other reference, the
# same object.
function _shift_column_reference(w::WidgetTable, reference, distance::Int)
    reference isa ConcreteReference && reference.head isa FieldReferenceStep || return reference
    tail = reference.tail
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep) || return reference
    name = reference.head.name
    (name in ("columns", "column_headers") || (name == "cells" && _is_column_major(w))) &&
        return _shift_reference_step(reference, 1, distance)
    name == "cells" ? _shift_reference_step(reference, 2, distance) : reference
end

# `reference` with its element step `which`, 1 or 2 after the field, counted from
# a head `distance` further on; the same object when it has no such step.
function _shift_reference_step(reference::ConcreteReference, which::Int, distance::Int)
    shift(step) = RangeReferenceStep(step.start - distance, step.stop - distance)
    tail = reference.tail
    which == 1 && return ConcreteReference(reference.head, ConcreteReference(shift(tail.head), tail.tail))
    rest = tail.tail
    (rest isa ConcreteReference && rest.head isa RangeReferenceStep) || return reference
    ConcreteReference(reference.head, ConcreteReference(tail.head, ConcreteReference(shift(rest.head), rest.tail)))
end

# Node `k` of a list, counted from `head`, or `nothing` past an end.
function _find_list_node(head, k::Int)
    head isa ListNode || return nothing
    node = head
    for _ in 1:abs(k - 1)
        node = k > 1 ? node.next : node.prev
        node === nothing && return nothing
    end
    node
end

# `rows[r]…`, `row_headers[r]…` and the cell paths of `w` with `r` counted from a
# head `distance` rows further on; any other reference, the same object.
function _shift_row_reference(w::WidgetTable, reference, distance::Int)
    (reference isa ConcreteReference && reference.head isa FieldReferenceStep &&
     reference.head.name in ("rows", "cells", "row_headers")) || return reference
    tail = reference.tail
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep) || return reference
    which = (reference.head.name == "cells" && _is_column_major(w)) ? 2 : 1
    _shift_reference_step(reference, which, distance)
end

# The keys of the table: Ctrl+Alt+Home selects the table; the arrows move a
# selected row, column, cell or header, and stop at the ends of the list; from a
# column header, Down goes to its cell in the row at the top, and from a row
# header, Right goes to its first cell; Return goes from a row to its first
# cell, from a column to its cell in the row at the top, and from a cell into
# its content; Shift+Space and Ctrl+Space select in the row and the column
# direction.
function _read_table_parts_key(iomap::WidgetTableListIoMap, evt::KeyDown)
    st = iomap.state
    st.columns == 0 && !st.column_list && return nothing
    evt.key === :home && evt.modifiers.ctrl && evt.modifiers.alt &&
        return ReplaceSelectionOperation(EmptyReference())
    # The column before or after `c`, or `c` at an end.
    step_column(c, d) = _get_table_column_span(st, c + d) === nothing ? c : c + d
    named = _find_named_part(iomap.input, iomap.input.selection)
    named === nothing && return nothing
    shape, k, c = named
    exists(row) = find_grid_list_row(st.cells_pane.content_iomap, row) !== nothing
    # Shift+Space selects in the row direction and Ctrl+Space in the column
    # direction: from a column header the header row or its column, from a row
    # header its row or the header column, and from a cell its row or its column.
    line_key = evt.key === :space && (evt.modifiers.shift ⊻ evt.modifiers.ctrl)
    row_direction = evt.modifiers.shift
    if shape === :column_header
        line_key && return ReplaceSelectionOperation(row_direction ? _wt_header_row_ref() : _wt_col_ref(c))
        evt.key === :left && return ReplaceSelectionOperation(_wt_column_header_ref(step_column(c, -1)))
        evt.key === :right && return ReplaceSelectionOperation(_wt_column_header_ref(step_column(c, 1)))
        evt.key === :down && return ReplaceSelectionOperation(_wt_cell_ref(iomap.input, iomap.input.top_row, c))
        return nothing
    end
    if shape === :row_header
        line_key && return ReplaceSelectionOperation(row_direction ? _wt_row_ref(k) : _wt_header_column_ref())
        evt.key === :up && return exists(k - 1) ? ReplaceSelectionOperation(_wt_row_header_ref(k - 1)) : nothing
        evt.key === :down && return exists(k + 1) ? ReplaceSelectionOperation(_wt_row_header_ref(k + 1)) : nothing
        evt.key === :right && return ReplaceSelectionOperation(_wt_cell_ref(iomap.input, k, 1))
        return nothing
    end
    shape in (:table, :header_row, :header_column) && return nothing
    if shape === :column
        top = iomap.input.top_row
        evt.key === :return && return ReplaceSelectionOperation(_wt_cell_ref(iomap.input, top, c))
        evt.key === :down && return ReplaceSelectionOperation(_wt_cell_ref(iomap.input, top, c))
        evt.key === :left && return ReplaceSelectionOperation(_wt_col_ref(step_column(c, -1)))
        evt.key === :right && return ReplaceSelectionOperation(_wt_col_ref(step_column(c, 1)))
        return nothing
    end
    c == 0 && (c = nothing)
    if evt.key === :return
        c === nothing && return ReplaceSelectionOperation(_wt_cell_ref(iomap.input, k, 1))
        return _enter_table_cell(iomap.input, st, k, c)
    end
    if line_key
        c === nothing && return nothing
        return ReplaceSelectionOperation(row_direction ? _wt_row_ref(k) : _wt_col_ref(c))
    end
    evt.key in (:up, :down, :left, :right) || return nothing
    if c === nothing
        evt.key === :up && return exists(k - 1) ? ReplaceSelectionOperation(_wt_row_ref(k - 1)) : nothing
        evt.key === :down && return exists(k + 1) ? ReplaceSelectionOperation(_wt_row_ref(k + 1)) : nothing
        evt.key === :right && return ReplaceSelectionOperation(_wt_cell_ref(iomap.input, k, 1))
        return nothing
    end
    if evt.key === :up
        exists(k - 1) || return nothing
        k -= 1
    elseif evt.key === :down
        exists(k + 1) || return nothing
        k += 1
    elseif evt.key === :left
        c = step_column(c, -1)
    else
        c = step_column(c, 1)
    end
    ReplaceSelectionOperation(_wt_cell_ref(iomap.input, k, c))
end

# Return puts the caret at the start of the content of the cell.
function _enter_table_cell(w::WidgetTable, st::WidgetTablePartsState, k::Int, c::Int)
    found = _find_table_cell(st, k, c)
    found === nothing && return nothing
    cim = found[1]
    op = read_intent(cim.projection, cim, KeyDown(:home, ModifierKeys(ctrl = true); time = time()))
    op isa ReplacePathOperation || return nothing
    reroot_operation(op, _wt_get_cell_steps(w, k, c))
end

# A press of another button than the left, a button down, a button up or a dwell
# goes to the cell under it, a header, a row header or the corner as well as a
# body cell, in the coordinates of the cell, and its answer is rooted under the
# cell. For a dwell and a right click the table then reads its own stretch
# (`read_container_gesture`).
function _read_table_point_event(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableListIoMap, event)
    found = _read_table_point_cell(p, iomap, event)
    found === nothing && return read_container_gesture(nothing, event, iomap.input)
    read_container_gesture(found[1], event, iomap.input; steps = found[2])
end

# The answer of the cell under `event`, rooted under the cell, and the steps to the
# cell; `nothing` when the event reaches no cell.
function _read_table_point_cell(p::WidgetTableToGraphicsCanvas,
                                iomap::WidgetTableListIoMap, event)
    st = iomap.state
    found = _find_table_part_at(p, iomap, Int(event.x), Int(event.y))
    found === nothing && return nothing
    part, x, y = found
    if part === :corner
        st.corner === nothing && return nothing
        local_event = _wt_translate_event(event, x, y)
        local_event === nothing && return nothing
        steps = (FieldReferenceStep("corner"),)
        return (reroot_operation(_wt_read_cell_event(st.corner, event, local_event), steps), steps)
    end
    if part === :row_header
        k = _find_table_row_at(st, y)
        k === nothing && return nothing
        cell = _find_table_row_header(st, k)
        cell === nothing && return nothing
        cim, left, top = cell
        local_event = _wt_translate_event(event, x - left, y - top)
        local_event === nothing && return nothing
        steps = (FieldReferenceStep("row_headers"), RangeReferenceStep(k - 1, k))
        return (reroot_operation(_wt_read_cell_event(cim, event, local_event), steps), steps)
    end
    c = _find_table_column_at(st, x)
    c === nothing && return nothing
    cell, steps = if part === :header
        (_find_table_header_cell(st, c), (FieldReferenceStep("column_headers"), RangeReferenceStep(c - 1, c)))
    else
        k = _find_table_row_at(st, y)
        k === nothing && return nothing
        (_find_table_cell(st, k, c), _wt_get_cell_steps(iomap.input, k, c))
    end
    cell === nothing && return nothing
    cim, left, top = cell
    local_event = _wt_translate_event(event, x - left, y - top)
    local_event === nothing && return nothing
    (reroot_operation(_wt_read_cell_event(cim, event, local_event), steps), steps)
end

# An event that is not a gesture of the table goes to the cell or the header
# that the selection is in, or to the corner, and its answer is rooted under it.
# A selected header is not in the header: only a path into it is.
function _read_selected_table_cell(st::WidgetTablePartsState, w::WidgetTable, event)
    selection = w.selection
    (selection isa ConcreteReference && selection.head isa FieldReferenceStep &&
     selection.head.name == "corner") && return _read_table_corner(st, event)
    header = _find_header_in_selection(selection)
    if header !== nothing
        field, k = header
        found = field == "column_headers" ? _find_table_header_cell(st, k) : _find_table_row_header(st, k)
        found === nothing && return nothing
        return reroot_operation(read_intent(found[1].projection, found[1], event),
                                (FieldReferenceStep(field), RangeReferenceStep(k - 1, k)))
    end
    prefix = _wt_cell_prefix(w, selection)
    prefix === nothing && return nothing
    k, c = prefix
    found = _find_table_cell(st, k, c)
    found === nothing && return nothing
    cim = found[1]
    reroot_operation(read_intent(cim.projection, cim, event), _wt_get_cell_steps(w, k, c))
end

# The header that `selection` goes into, `column_headers[c]` or `row_headers[k]`
# followed by a path inside the header, as `(field, index)`, or `nothing`.
function _find_header_in_selection(selection)
    selection = selection isa Reference ? strip_reference_types(selection) : selection
    (selection isa ConcreteReference && selection.head isa FieldReferenceStep &&
     selection.head.name in ("column_headers", "row_headers")) || return nothing
    tail = selection.tail
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep && tail.tail isa ConcreteReference) ||
        return nothing
    (selection.head.name, tail.head.stop)
end

# An event for the corner, in its coordinates, read by the corner and rooted
# under `corner`; `nothing` with no corner or when it has nothing to say.
function _read_table_corner(st::WidgetTablePartsState, event)
    cim = st.corner
    cim === nothing && return nothing
    reroot_operation(read_intent(cim.projection, cim, event), (FieldReferenceStep("corner"),))
end

# A left press within `_COLUMN_EDGE_REACH` of the right edge of a header starts
# the drag of the width of its column: the column, the point and the width at
# the press are the state of the drag, and the moves come by the path of the
# table, wherever the pointer is. `nothing` for a press anywhere else.
function _read_table_column_edge_press(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableListIoMap,
                                       g::MouseDown)
    w = iomap.input
    w.column_drag === nothing || return nothing
    found = _find_table_part_at(p, iomap, g.x, g.y)
    (found === nothing || found[1] !== :header) && return nothing
    edge = _find_table_column_edge_at(iomap.state, found[2])
    edge === nothing && return nothing
    c, width = edge
    CompoundOperation(Any[
        ReplaceViewStateOperation(ReplaceReferencedValueOperation(w, "column_drag",
                                                                  (column = c, x = g.x, width = width))),
        StartDragOperation(EmptyReference(), nothing),
        make_screen_pointer_shape_operation(:double_arrow_horizontal)])
end

# A rest of the pointer on the right edge of a header says what a drag there
# does, as a tooltip of the edge; `nothing` anywhere else.
function _read_table_column_edge_dwell(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableListIoMap,
                                       g::MouseDwell)
    found = _find_table_part_at(p, iomap, g.x, g.y)
    (found === nothing || found[1] !== :header) && return nothing
    edge = _find_table_column_edge_at(iomap.state, found[2])
    edge === nothing && return nothing
    tooltip = make_tooltip_operation(iomap.input, PrimitiveString("Drag to set the width"), g)
    reroot_operation(tooltip, (FieldReferenceStep("columns"), RangeReferenceStep(first(edge) - 1, first(edge)),
                              FieldReferenceStep("policy")))
end

# A rest of the pointer on an open cell whose last commit failed shows the reason
# of its mark; `nothing` anywhere else.
function _read_table_mark_dwell(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableListIoMap, g::MouseDwell)
    isempty(something(iomap.input.open_cells, ())) && return nothing
    found = _find_table_part_at(p, iomap, g.x, g.y)
    (found === nothing || found[1] !== :cells) && return nothing
    st = iomap.state
    k = _find_table_row_at(st, found[3])
    c = _find_table_column_at(st, found[2])
    (k === nothing || c === nothing) && return nothing
    _read_cell_mark_dwell(iomap.input, k, c, g)
end

"""
    read_table_column_drag(table, gesture) -> Operation or nothing

The answer of `table` to a part of the drag of the width of a column that is on
(`column_drag`): a `DragMove` gives the column the width at the press plus the
move along x, and at least a narrowest width; a `DragEnd` ends the drag; a
`DragCancel` puts back the width at the press and ends the drag. Each is view
state, so a history records no part of a drag. `nothing` when no drag is on.

The table reads its drag itself. An owner that the parts of a drag reach by its
own path, because the table is a part that it made, gives them on with this
function, with the x of the point in the frame of the table.
"""
function read_table_column_drag(w::WidgetTable, g)
    drag = w.column_drag
    drag === nothing && return nothing
    ending = ReplaceViewStateOperation(ReplaceReferencedValueOperation(w, "column_drag", nothing))
    width(value) = ReplaceViewStateOperation(SetTableColumnWidthOperation(w, drag.column, value))
    g isa DragMove && return width(max(_MIN_COLUMN_WIDTH, drag.width + g.x - drag.x))
    shape = make_screen_pointer_shape_operation(nothing)
    g isa DragEnd && return CompoundOperation(Any[ending, shape])
    CompoundOperation(Any[width(drag.width), ending, shape])
end

function read_intent(p::WidgetTableToGraphicsCanvas, recursion, change::Intent,
                     iomap::WidgetTableListIoMap)
    g = change.gesture
    g isa Union{DragMove,DragEnd,DragCancel} && return Intent(g, read_table_column_drag(iomap.input, g))
    if change.operation === nothing
        if g isa MouseDown && g.button === :left
            op = _read_table_column_edge_press(p, iomap, g)
            op === nothing || return Intent(g, op)
        end
        if g isa MouseDwell
            op = _read_table_column_edge_dwell(p, iomap, g)
            op === nothing || return Intent(g, op)
            op = _read_table_mark_dwell(p, iomap, g)
            op === nothing || return Intent(g, op)
        end
        g isa MouseClick && g.button === :left && return Intent(g, _read_table_parts_press(p, iomap, g))
        # A pointer motion does not go into the cells: the part under the pointer
        # is the backward map of the point. A dwell goes to the cell under it.
        g isa MouseMove && return Intent(g, nothing)
        g isa MouseScroll && return Intent(g, _read_table_parts_wheel(p, iomap, g))
        if g isa KeyDown
            op = _read_open_cell_key(iomap.input, g)
            op === nothing || return Intent(g, op)
            op = _read_table_parts_key(iomap, g)
            op === nothing || return Intent(g, op)
        end
    end
    change.operation === nothing && _positioned_event(g) &&
        return Intent(g, _read_table_point_event(p, iomap, g))
    payload = change.operation === nothing ? g : change.operation
    op = _read_selected_table_cell(iomap.state, iomap.input, payload)
    (op isa Operation || change.operation !== nothing) && return Intent(g, op)
    Intent(g, something(_read_whole_cell_key(iomap.input, g), Some(op)))
end

function read_intent(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableListIoMap, event)
    # The parts of the drag of the width of a column come by the path of the
    # table, wherever the pointer is.
    event isa Union{DragMove,DragEnd,DragCancel} && return read_table_column_drag(iomap.input, event)
    _outside_widget(iomap, event) && return nothing
    if event isa MouseDown && event.button === :left
        op = _read_table_column_edge_press(p, iomap, event)
        op === nothing || return op
    end
    if event isa MouseDwell
        op = _read_table_column_edge_dwell(p, iomap, event)
        op === nothing || return op
        op = _read_table_mark_dwell(p, iomap, event)
        op === nothing || return op
    end
    if event isa MouseClick || event isa KeyDown || event isa MouseScroll ||
       event isa MouseMove
        return read_intent(p, nothing, Intent(event, nothing), iomap).operation
    end
    _positioned_event(event) && return _read_table_point_event(p, iomap, event)
    _read_selected_table_cell(iomap.state, iomap.input, event)
end
