# Fragment of `WidgetModule`.
#
# Headers with levels, in a table that scrolls its own parts and whose columns
# are a vector. A header that is a `CellVector` holds one label for each level,
# the outer level first. Two neighbours whose labels agree on the first levels
# share those levels: the table draws such a run as one header. The last level
# never merges, so it has one header for each column and each row.
#
# **The header row** is a grid of one row for each level. A level puts one
# child in the grid for each run, and a run of more than one column spans its
# columns (`column_span` of a `LayoutConstraint`). So the label of a run is
# drawn once, across the width of its columns. The rule between two columns
# starts under the levels that they share, and a rule runs above each level.
#
# **The header column** is a grid of one column for each level, over the rows
# of the list. A row shows the label of a level where its run starts, and the
# row at the top of the cells shows every label, so the label of a run that
# starts above the visible rows is on the screen too. The rule above a row
# starts at the first level that it does not share with the row above it.
#
# **The corner** is a `CellVector` of one label for each level of the row
# headers, the names of the levels. It is drawn as a grid of one row whose
# columns are the columns of the header column.
#
# **A part.** `column_headers[c][l]` names the label of level `l` of column `c`,
# and the run that holds it; `row_headers[k][l]` the same for row `k`. A press
# on a run of an outer level selects the label of the first column or row of the
# run, and the table lights the whole run.

# The levels of the headers of a table: the count of the levels of the column
# headers, the runs of each level, the index of the first child of each level in
# the grid of the header row, and the count of the levels that two neighbour
# columns share; and the count of the levels of the row headers. A table with no
# levels has 0 levels.
struct _TableHeaderLevels
    column_levels::Int
    column_runs::Vector{Vector{UnitRange{Int}}}
    first_children::Vector{Int}
    column_shared::Vector{Int}
    row_levels::Int
end

const _NO_TABLE_HEADER_LEVELS = _TableHeaderLevels(0, Vector{UnitRange{Int}}[], Int[], Int[], 0)

# The count of the levels of `headers`, the column headers or the row headers of
# a table: the length of each header when every header is a `CellVector`, 0 when
# none is.
function _get_header_level_count(headers)
    found = Any[header for header in headers if header !== nothing]
    isempty(found) && return 0
    first(found) isa CellVector || return 0
    count = length(first(found))
    all(header -> header isa CellVector && length(header) == count, found) ||
        error("WidgetTable: a header with levels needs every header to be a CellVector ",
              "with the same count of levels")
    count
end

# The count of the levels of the row headers of a list, read from its head.
_get_row_header_level_count(headers::ListNode) =
    (header = headers.value; header isa CellVector ? length(header) : 0)
_get_row_header_level_count(headers) = _get_header_level_count(headers)

# What two labels are compared by: the text of a label, and any other value as
# it is.
_get_header_label_key(label::WidgetLabel) = label.content
_get_header_label_key(label) = label

_is_same_header_label(a, b) = isequal(_get_header_label_key(a), _get_header_label_key(b))

# The count of the outer levels that two headers share, at most one less than
# `levels`, because the last level never merges.
function _count_shared_header_levels(a, b, levels::Int)
    (a isa CellVector && b isa CellVector) || return 0
    shared = 0
    while shared < levels - 1 && _is_same_header_label(a[shared + 1], b[shared + 1])
        shared += 1
    end
    shared
end

# The document that draws a label: the label itself when it is a document, and
# a `WidgetLabel` of its text otherwise; an empty cell for `nothing`.
_make_header_label_document(label::Document) = label
_make_header_label_document(::Nothing) = _wt_empty_cell()
_make_header_label_document(label) = WidgetLabel(string(label))

# The levels of the column headers of `w`, which has `n` columns.
function _compute_table_header_levels(w::WidgetTable, n::Int)
    headers = Any[c <= length(w.column_headers) ? w.column_headers[c] : nothing for c in 1:n]
    levels = _get_header_level_count(headers)
    row_levels = _get_row_header_level_count(w.row_headers)
    levels == 0 && return _TableHeaderLevels(0, Vector{UnitRange{Int}}[], Int[], Int[], row_levels)
    shared = Int[_count_shared_header_levels(headers[c - 1], headers[c], levels) for c in 2:n]
    runs = [UnitRange{Int}[] for _ in 1:levels]
    for l in 1:levels
        start = 1
        for c in 2:(n + 1)
            if c == n + 1 || shared[c - 1] < l
                push!(runs[l], start:(c - 1))
                start = c
            end
        end
    end
    first_children = Int[]
    next_child = 1
    for l in 1:levels
        push!(first_children, next_child)
        next_child += length(runs[l])
    end
    _TableHeaderLevels(levels, runs, first_children, shared, row_levels)
end

# The children of the grid of the header row: for each level, one child for each
# run, which spans the columns of a run of more than one.
function _make_level_header_children(w::WidgetTable, levels::_TableHeaderLevels)
    children = Cell[]
    for l in 1:levels.column_levels, run in levels.column_runs[l]
        label = _make_header_label_document(w.column_headers[first(run)][l])
        child = length(run) > 1 ? LayoutConstraint(label; column_span = length(run)) : label
        push!(children, Cell(child))
    end
    CellVector(children)
end

# The run of level `l` that holds column `c`, and the index of its child in the
# grid of the header row; `nothing` past an end.
function _find_column_header_run(levels::_TableHeaderLevels, l::Int, c::Int)
    1 <= l <= levels.column_levels || return nothing
    for (i, run) in enumerate(levels.column_runs[l])
        c in run && return (run, levels.first_children[l] + i - 1)
    end
    nothing
end

# The index of the child of the last level of column `c` in the grid of the header
# row.
_get_column_header_leaf_child(levels::_TableHeaderLevels, c::Int) =
    levels.first_children[levels.column_levels] + c - 1

# The labels of the runs that span columns, each printed once more at the size
# that it measures, by the index of its child in the grid of the header row. The
# grid offers a spanning child the width of its columns, so the child in the
# grid can not say how wide the columns must be. A label that is not a text has
# no measure here.
function _measure_level_header_runs(recursion, w::WidgetTable, levels::_TableHeaderLevels, inner)
    measured = Dict{Int,Any}()
    for l in 1:(levels.column_levels - 1), (i, run) in enumerate(levels.column_runs[l])
        length(run) > 1 || continue
        label = w.column_headers[first(run)][l]
        text = label isa WidgetLabel ? label.content : label isa Document ? nothing : label
        (text === nothing || !(text isa Union{AbstractString,Number,Symbol})) && continue
        context = make_child_context(inner, FieldReferenceStep("column_headers"))
        measured[levels.first_children[l] + i - 1] =
            print_child(recursion, WidgetLabel(string(text)),
                        context === nothing ? nothing : with_free_axis(with_free_axis(context, :x), :y))
    end
    measured
end

# The width that the headers of column `c` need: its own header at the last
# level, and its share of each run that spans it, less the gaps inside the run.
function _get_level_header_width(levels::_TableHeaderLevels, header_grid, measured::Dict{Int,Any},
                                 c::Int, hgap::Int)
    entries = header_grid.child_iomaps
    width = _get_part_child_width(entries[_get_column_header_leaf_child(levels, c)][3])
    for l in 1:(levels.column_levels - 1)
        found = _find_column_header_run(levels, l, c)
        found === nothing && continue
        run, child = found
        length(run) > 1 || (width = max(width, _get_part_child_width(entries[child][3])); continue)
        haskey(measured, child) || continue
        total = _get_part_child_width(measured[child]) - (length(run) - 1) * hgap
        width = max(width, cld(max(0, total), length(run)))
    end
    width
end

# A width that a part already knows, as the IO map of a header gives one.
_get_part_child_width(width::Int) = width

# The level of the header row at `y`, in the coordinates of its rules: the rule
# above level `l` is at the top of row `l` of its grid.
function _find_column_header_level_at(st, y::Int)
    levels = st.levels.column_levels
    grid = st.column_header_pane.content_iomap
    found = 1
    for l in 2:levels
        y >= Int(grid.row_y[l][]) && (found = l)
    end
    found
end

# The steps from the table to the header of column `c`, and of row `k`, at its
# last level when the headers have levels.
_get_column_header_steps(st, c::Int) =
    st.levels.column_levels == 0 ?
        (FieldReferenceStep("column_headers"), RangeReferenceStep(c - 1, c)) :
        (FieldReferenceStep("column_headers"), RangeReferenceStep(c - 1, c),
         RangeReferenceStep(st.levels.column_levels - 1, st.levels.column_levels))

_get_row_header_steps(st, k::Int) =
    st.levels.row_levels == 0 ?
        (FieldReferenceStep("row_headers"), RangeReferenceStep(k - 1, k)) :
        (FieldReferenceStep("row_headers"), RangeReferenceStep(k - 1, k),
         RangeReferenceStep(st.levels.row_levels - 1, st.levels.row_levels))

# The path of the label of level `l` of column `c`, and of row `k`.
_make_level_header_reference(field::String, index::Int, l::Int) =
    ConcreteReference(FieldReferenceStep(field), ConcreteReference(RangeReferenceStep(index - 1, index),
        ConcreteReference(RangeReferenceStep(l - 1, l), EmptyReference())))

# What a path names of a header with levels: `(field, index, l)` for
# `column_headers[c][l]…` or `row_headers[k][l]…`, else `nothing`.
function _find_level_header_part(reference)
    reference = reference isa Reference ? strip_reference_types(reference) : reference
    (reference isa ConcreteReference && reference.head isa FieldReferenceStep) || return nothing
    field = reference.head.name
    field in ("column_headers", "row_headers") || return nothing
    tail = reference.tail
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep) || return nothing
    rest = tail.tail
    (rest isa ConcreteReference && rest.head isa RangeReferenceStep) || return nothing
    (field, tail.head.stop, rest.head.stop)
end

# ── The header row ───────────────────────────────────────────────────────────

# The rules of a header row with levels, in the coordinates of its rules: the
# rule left of each column, which starts under the levels that the column shares
# with the column before it, and the rule above each level but the first.
function _push_level_header_rules!(out, st, edges::Vector{Int}, h::Int, divider)
    levels = st.levels
    grid = st.column_header_pane.content_iomap
    bw = st.bw
    for (k, edge) in enumerate(edges)
        shared = 2 <= k <= length(levels.column_shared) + 1 ? levels.column_shared[k - 1] : 0
        top = shared == 0 ? 0 : Int(grid.row_y[shared + 1][])
        push!(out, GraphicsRect(edge, top, bw, h - top; color = divider))
    end
    width = last(edges) + bw
    for l in 2:levels.column_levels
        push!(out, GraphicsRect(0, Int(grid.row_y[l][]), width, bw; color = divider))
    end
    out
end

# The band of the light or of the selection, `kind`, over a run of the header
# row that `column_headers[c][l]` names: across the columns of the run, from
# the rule above its level to the bottom of the header row.
function _make_level_header_band(p::WidgetTableToGraphicsCanvas, w::WidgetTable, st, height::Cell,
                                 kind::Symbol)
    reference() = kind === :light ? get_mouse_target(w) : w.selection
    box = Cell(@computation begin
        found = _find_level_header_part(reference())
        (found === nothing || found[1] != "column_headers") && return (0, 0, 0, 0)
        _, c, l = found
        run = _find_column_header_run(st.levels, l, c)
        run === nothing && return (0, 0, 0, 0)
        edges = st.edges[]
        (first(run[1]) >= 1 && last(run[1]) + 1 <= length(edges)) || return (0, 0, 0, 0)
        top = Int(st.column_header_pane.content_iomap.row_y[l][]) + st.bw
        left = edges[first(run[1])]
        (left, top, edges[last(run[1]) + 1] - left, max(0, Int(height[]) - top))
    end)
    color = kind === :light ? p.layer_hovered_color : _get_state_color(p, w, :row; state = :selected)
    rect = GraphicsRect(0, 0, 0, 0; color, radius = p.row_radius)
    set_cell_computation!(getfield(rect, :x), () -> Int32(box[][1]))
    set_cell_computation!(getfield(rect, :y), () -> Int32(box[][2]))
    set_cell_computation!(getfield(rect, :w), () -> Int32(box[][3]))
    set_cell_computation!(getfield(rect, :h), () -> Int32(box[][4]))
    rect
end

# ── The header column ────────────────────────────────────────────────────────

# Whether the header of `node`, a node of the list of row headers, goes on the
# run of level `l` of the row before it.
function _is_row_header_run_continued(node::ListNode, l::Int, levels::Int)
    previous = node.prev
    previous === nothing && return false
    _count_shared_header_levels(previous.value, node.value, levels) >= l
end

# The node of a list that mirrors the headers of `header_node`, row `k` from the
# head, as rows of one cell for each level. A cell shows the label of its level
# where its run starts, at the last level, and in the row at the top of the
# cells; else it is empty.
function _make_level_header_row_node(w::WidgetTable, header_node::ListNode, k::Int, levels::Int)
    cells = Cell[]
    for l in 1:levels
        push!(cells, Cell(@computation begin
            labels = header_node.value
            shown = l == levels || k == w.top_row || !_is_row_header_run_continued(header_node, l, levels)
            shown ? _make_header_label_document(labels isa CellVector ? labels[l] : nothing) : _wt_empty_cell()
        end))
    end
    node = ListNode(CellVector(cells))
    set_cell_computation!(getfield(node, :next), () -> begin
        following = header_node.next
        following === nothing && return nothing
        next_node = _make_level_header_row_node(w, following, k + 1, levels)
        set_cell_value!(getfield(next_node, :prev), node)
        next_node
    end)
    set_cell_computation!(getfield(node, :prev), () -> begin
        preceding = header_node.prev
        preceding === nothing && return nothing
        prev_node = _make_level_header_row_node(w, preceding, k - 1, levels)
        set_cell_value!(getfield(prev_node, :next), node)
        prev_node
    end)
    node
end

# How many rows from the head the header column measures to find the width of
# each level. A label further down that is wider is cut at the edge of its level.
const _ROW_HEADER_MEASURED_ROWS = 64

# The widths of the levels of a header column, which its grid and the corner
# share: level `l` is as wide as the label of level `l` of the corner and as the
# widest label of that level among the first rows from the head. The two IO maps
# are set once the grids print.
struct _LevelColumnSizes
    levels::Int
    widths::Vector{Cell}
    policies::Cell
    offers::Cell
    grid::Cell
    corner::Cell
end

function _make_level_column_sizes(levels::Int)
    grid_iomap = Cell(nothing)
    corner_iomap = Cell(nothing)
    widths = Cell[]
    for l in 1:levels
        push!(widths, Cell(@computation begin
            grid = grid_iomap[]
            corner = corner_iomap[]
            width = corner === nothing ? 0 : _get_part_child_width(corner.child_iomaps[l][3])
            if grid !== nothing
                for k in 1:_ROW_HEADER_MEASURED_ROWS
                    cell = find_grid_list_cell(grid, k, l)
                    cell === nothing && break
                    width = max(width, _get_part_child_width(cell[3]))
                end
            end
            width
        end))
    end
    _LevelColumnSizes(levels, widths, Cell(@computation Any[Fixed(widths[l][]) for l in 1:levels]),
                      Cell(Bool[false for _ in 1:levels]), grid_iomap, corner_iomap)
end

# The corner of a header column with levels: the labels of `corner`, one for each
# level, in a grid of one row whose columns are the levels; any other corner as
# a table prints it.
function _print_level_corner(recursion, w::WidgetTable, inner, sizes::_LevelColumnSizes, hgap::Int)
    labels = w.corner
    labels isa CellVector || return _print_table_corner(recursion, w, inner)
    children = CellVector(Cell[Cell(_make_header_label_document(l <= length(labels) ? labels[l] : nothing))
                               for l in 1:sizes.levels])
    grid = GridLayout(children, Cell(sizes.levels), Cell(:left), Cell(:top), Cell(hgap), Cell(0),
                      Cell(Symbol[]), Cell(Content), Cell(Content), sizes.policies, Cell(Any[]), sizes.offers,
                      Cell(Bool[]), Cell(nothing))
    corner = print_child(recursion, grid,
                         with_free_axis(with_free_axis(make_child_context(inner, FieldReferenceStep("corner")),
                                                       :x), :y))
    sizes.corner[] = get_content_iomap(corner)
    corner
end

# The pane of a header column with levels, `height` tall: a grid of one column
# for each level over the row headers, which scrolls with the `y` of the offset.
function _print_level_header_column(recursion, w::WidgetTable, inner, sizes::_LevelColumnSizes,
                                    height::Cell, pad_x::Int, pad_y::Int, bw::Int)
    hgap = 2 * pad_x + bw
    vgap = 2 * pad_y + bw
    rows = Cell(@computation (headers = w.row_headers;
                              headers isa ListNode ? _make_level_header_row_node(w, headers, 1, sizes.levels) :
                                                     nothing))
    grid = GridLayout(rows, Cell(sizes.levels), Cell(:left), Cell(:top), Cell(hgap), Cell(vgap),
                      Cell(Symbol[]), Cell(Content), getfield(w, :row_policy), sizes.policies, Cell(Any[]),
                      sizes.offers, Cell(Bool[]), Cell(nothing))
    offset = getfield(w, :scroll_position)
    pane = _make_part_pane(grid, Cell(@computation Point2D(0, Int((offset[]::Point2D).y[]))),
                           Inset(bw + pad_y, bw + pad_y, bw + pad_x, pad_x))
    iomap = print_child(recursion, pane, with_exact_size(with_free_axis(inner, :x); height))
    sizes.grid[] = iomap.content_iomap
    iomap
end

# The level of the header column at `x`, in the coordinates of its rules.
function _find_row_header_level_at(st, x::Int)
    grid = st.row_header_pane.content_iomap
    found = 1
    for l in 2:st.levels.row_levels
        x >= Int(grid.col_x[l][]) && (found = l)
    end
    found
end

# The row where the run of level `l` that holds row `k` starts, counted from the
# head.
function _find_row_header_run_start(w::WidgetTable, k::Int, l::Int, levels::Int)
    node = find_list_node(w.row_headers, k)
    node === nothing && return k
    while _is_row_header_run_continued(node, l, levels)
        node = node.prev
        k -= 1
    end
    k
end

# Whether row `k` is in the run of level `l` that starts at row `start`.
function _is_row_in_header_run(w::WidgetTable, start::Int, k::Int, l::Int, levels::Int)
    k < start && return false
    first_node = find_list_node(w.row_headers, start)
    node = find_list_node(w.row_headers, k)
    (first_node === nothing || node === nothing) && return false
    _count_shared_header_levels(first_node.value, node.value, levels) >= l
end

# The span `(left, width)` of the band of row `k` of a header column with
# levels: the whole column for the table, for the row or for its header; from
# level `l` on for a run of level `l` that holds the row; `(0, 0)` otherwise.
function _get_level_header_column_band_span(w::WidgetTable, reference, k::Int, st)
    named = _find_named_part(w, reference)
    if named !== nothing
        shape, row, _ = named
        (shape === :table || (shape in (:row, :row_header) && row == k)) &&
            return (0, Int(st.header_width[]))
        return (0, 0)
    end
    found = _find_level_header_part(reference)
    (found === nothing || found[1] != "row_headers") && return (0, 0)
    _, start, l = found
    levels = st.levels.row_levels
    _is_row_in_header_run(w, start, k, l, levels) || return (0, 0)
    left = Int(st.row_header_pane.content_iomap.col_x[l][])
    (left, Int(st.header_width[]) - left)
end

# The rules of row `k` of a header column with levels, in the coordinates of its
# rules: the rule above the row, from the first level that it does not share with
# the row before it, and the rule left of each level but the first.
function _push_level_header_column_rules!(out, w::WidgetTable, st, k::Int, h::Int, divider)
    levels = st.levels.row_levels
    grid = st.row_header_pane.content_iomap
    width = Int(st.header_width[])
    node = find_list_node(w.row_headers, k)
    shared = node === nothing ? 0 :
        (node.prev === nothing ? 0 : _count_shared_header_levels(node.prev.value, node.value, levels))
    left = shared == 0 ? 0 : Int(grid.col_x[shared + 1][])
    push!(out, GraphicsRect(left, 0, width - left, st.bw; color = divider))
    for l in 2:levels
        push!(out, GraphicsRect(Int(grid.col_x[l][]), 0, st.bw, h; color = divider))
    end
    out
end

# The band of the light or of the selection, `kind`, in row `k` of a header
# column with levels: what `_get_level_header_column_band_span` gives for a run
# of an outer level, and the band of the row or of the table otherwise.
function _make_level_header_column_band(p::WidgetTableToGraphicsCanvas, w::WidgetTable, st, k::Int,
                                        band_height::Cell, kind::Symbol)
    span = Cell(@computation begin
        raw = kind === :light ? get_mouse_target(w) : w.selection
        found = _find_level_header_part(raw)
        reference = (found !== nothing && found[1] == "row_headers") ? raw :
                    (kind === :light ? _find_wt_lit_reference(w, raw) : raw)
        _get_level_header_column_band_span(w, reference, k, st)
    end)
    color = kind === :light ? p.layer_hovered_color : _get_state_color(p, w, :row; state = :selected)
    rect = GraphicsRect(0, 0, 0, 0; color, radius = p.row_radius)
    set_cell_computation!(getfield(rect, :x), () -> Int32(span[][1]))
    set_cell_computation!(getfield(rect, :y), () -> Int32(st.bw))
    set_cell_computation!(getfield(rect, :w), () -> Int32(span[][2]))
    set_cell_computation!(getfield(rect, :h), () -> Int32(span[][2] == 0 ? 0 : Int(band_height[])))
    rect
end

# ── The paths of the parts ───────────────────────────────────────────────────

# The path in the grid of the header row of `tail`, the rest of a path
# `column_headers[c]…` of the table: `[c][l]…` goes to the child of the run of
# level `l` that holds column `c`, through `child` when the run spans columns, and
# `[c]…` with no level goes to the child of the last level. `nothing` past an end.
function _make_level_header_grid_path(levels::_TableHeaderLevels, tail)
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep) || return nothing
    c = tail.head.stop
    rest = tail.tail
    if rest isa ConcreteReference && rest.head isa RangeReferenceStep
        found = _find_column_header_run(levels, rest.head.stop, c)
        found === nothing && return nothing
        run, child = found
        inner = length(run) > 1 ? ConcreteReference(FieldReferenceStep("child"), rest.tail) : rest.tail
        return ConcreteReference(RangeReferenceStep(child - 1, child), inner)
    end
    1 <= c <= length(levels.column_shared) + 1 || return nothing
    child = _get_column_header_leaf_child(levels, c)
    ConcreteReference(RangeReferenceStep(child - 1, child), rest)
end

# The path in the grid of the header column of `tail`, the rest of a path
# `row_headers[k]…` of the table: `[k][l]…` is the cell of level `l` of row `k`,
# and `[k]…` with no level the cell of the last level.
function _make_level_header_column_path(levels::_TableHeaderLevels, tail)
    rest = tail.tail
    (rest isa ConcreteReference && rest.head isa RangeReferenceStep) &&
        return ConcreteReference(tail.head, rest)
    last_level = levels.row_levels
    ConcreteReference(tail.head, ConcreteReference(RangeReferenceStep(last_level - 1, last_level), rest))
end

# The label of the run of an outer level under the point at `x` in row `k` of the
# header column, in the coordinates of its rules: `row_headers[s][l]`, where the
# run starts at row `s`. `nothing` at the last level and with no levels.
function _find_level_row_header_reference(w::WidgetTable, st, k::Int, x::Int)
    levels = st.levels.row_levels
    levels > 1 || return nothing
    l = _find_row_header_level_at(st, x)
    l < levels || return nothing
    _make_level_header_reference("row_headers", _find_row_header_run_start(w, k, l, levels), l)
end

# The label of the run of an outer level under the point at `y` in column `c` of
# the header row: `column_headers[s][l]`, where the run starts at column `s`.
# `nothing` at the last level and with no levels.
function _find_level_column_header_reference(st, c::Int, y::Int)
    levels = st.levels.column_levels
    levels > 1 || return nothing
    l = _find_column_header_level_at(st, y)
    l < levels || return nothing
    found = _find_column_header_run(st.levels, l, c)
    found === nothing && return nothing
    _make_level_header_reference("column_headers", first(found[1]), l)
end
