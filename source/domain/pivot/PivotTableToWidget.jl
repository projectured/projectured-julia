# Fragment of `PivotModule`.
#
# A `PivotTable` drawn as the bar of its five zones above a table of its cross
# table. The column keys make the column headers and the row keys the row
# headers, one level for each dimension, and the table merges a run of equal
# labels into one header. The rows are a list, so the table builds only the rows
# that it shows, and a cell shows the document that the view of the pivot makes
# for its part.

"""
    PivotTableToWidget(; row_height, zone_gap, chip_gap)

Projects a [`PivotTable`](@ref) to a `GridLayout` of two rows: the bar of the
zones, and a `WidgetTable` of the cross table.

The bar has a row for each zone, in the order Fields, Columns, Rows, Cells and
Values: the name of the zone, and a badge for each dimension or measure in it.
An empty Values row shows the count, which is what a cell computes then.

The table has a column for each column key and a row for each row key. A header
of a column holds one label for each column dimension, and a header of a row one
label for each row dimension, so the table draws the levels of the headers and
merges their runs. The corner names the row dimensions. With no column
dimension, the one column is headed by the names of the measures; with no row
dimension, the one row is headed `all`. Each row is `row_height` tall.

A path of the pivot maps to the table and back: `cells[r][c]…` is the cell in
row `r` and column `c`, and `cells[r]` the row. A part of the table that the
pivot does not name, such as a run of headers, maps back as a part that the
projection introduced, and its selection shows in the table.
"""
@projection UntrackedCell struct PivotTableToWidget
    row_height::Int = 0
    zone_gap::Int = get_widget_style(nothing, :section_gap)
    chip_gap::Int = get_widget_style(nothing, :item_gap)
end

@iomap struct PivotTableToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    table::Any               # the WidgetTable of the cross table
end

# A weight and no minimum: the table gives each column an equal share of the
# width, and the width of its headers at least.
const _PIVOT_COLUMN_POLICY = SizePolicy(nothing, nothing, nothing, 1.0)

# The zones of the bar, in its order: the name that the bar shows, and the field
# of the pivot.
const _PIVOT_ZONES = (("Fields", "unused_dimensions"), ("Columns", "column_dimensions"),
                      ("Rows", "row_dimensions"), ("Cells", "cell_dimensions"), ("Values", "measures"))

function print_document(p::PivotTableToWidget, recursion, pivot::PivotTable, ctx)
    bar = _make_pivot_bar(p, pivot)
    table = _make_pivot_table_widget(p, pivot)
    grid = GridLayout(Any[bar, table], 1; vertical_gap = p.zone_gap, column_policies = Any[Fill],
                      row_policies = Any[Content, Fill])
    set_cell_computation!(getfield(grid, :selection), () -> begin
        selection = table.selection
        selection === nothing ? nothing : _make_pivot_grid_reference(2, selection)
    end)
    PivotTableToWidgetIoMap(p, pivot, grid, table)
end

print_document(p::PivotTableToWidget, pivot::PivotTable) = print_document(p, nothing, pivot, nothing)

# ── The bar ──────────────────────────────────────────────────────────────────

# The bar: a grid of the name of each zone and the badges of what it holds.
function _make_pivot_bar(p::PivotTableToWidget, pivot::PivotTable)
    children = CellVector(@computation begin
        out = Any[]
        for (name, field) in _PIVOT_ZONES
            push!(out, WidgetLabel(name))
            push!(out, _make_pivot_zone_row(p, pivot, field))
        end
        out
    end)
    GridLayout(children, Cell(2), Cell(:left), Cell(:top), Cell(p.zone_gap), Cell(p.chip_gap), Cell(Symbol[]),
               Cell(Content), Cell(Content), Cell(Any[]), Cell(Any[]), Cell(Bool[]), Cell(Bool[]), Cell(nothing))
end

# The badges of the zone in the field `field` of `pivot`.
function _make_pivot_zone_row(p::PivotTableToWidget, pivot::PivotTable, field::String)
    chips = Any[WidgetBadge(_describe_pivot_zone_item(item)) for item in getproperty(pivot, Symbol(field))]
    (isempty(chips) && field == "measures") && push!(chips, WidgetBadge("count"; variant = :outline))
    HorizontalLayout(chips; gap = p.chip_gap)
end

_describe_pivot_zone_item(dimension::PivotDimension) = dimension.column
_describe_pivot_zone_item(measure::PivotMeasure) = describe_pivot_measure(measure)
_describe_pivot_zone_item(item) = string(item)

# ── The table ────────────────────────────────────────────────────────────────

function _make_pivot_table_widget(p::PivotTableToWidget, pivot::PivotTable)
    headers = CellVector(@computation _make_pivot_column_headers(pivot))
    rows = Cell(@computation _make_pivot_row_list(pivot))
    row_headers = Cell(@computation _make_pivot_row_header_list(pivot))
    corner = Cell(@computation _make_pivot_corner(pivot))
    columns = Cell(@computation Any[WidgetTableColumn(; policy = _PIVOT_COLUMN_POLICY, align = :right)
                                    for _ in 1:get_pivot_column_count(pivot.cross_table)])
    # Positional, so every declared field is named here in order: position,
    # column_headers, row_headers, corner, cells, cell_order, rows, columns,
    # border_width, column_policy, row_policy, cell_policy, visible, margin,
    # border, padding, style, scroll_position, top_row, column_drag, open_cells,
    # tooltip.
    WidgetTable(Cell(Point2D(0, 0)), headers, row_headers, corner, rows,
                Cell(:row_major), Cell(WidgetTableRows(nothing)), columns, Cell(1),
                Cell(_PIVOT_COLUMN_POLICY), Cell(Fixed(p.row_height)), Cell(:clip),
                Cell(true), Cell(nothing), Cell(nothing), Cell(nothing),
                Cell(nothing), Cell(Point2D(0, 0)), Cell(1), Cell(nothing),
                Cell(nothing), Cell(nothing),
                Cell(@computation _get_pivot_table_selection(pivot)))
end

# The labels of a key, one for each level.
_make_pivot_key_labels(key::Tuple) = CellVector(Any[format_pivot_value(value) for value in key])

# The header of each column: the labels of its key, or the names of the measures
# for the one column of a pivot with no column dimension.
function _make_pivot_column_headers(pivot::PivotTable)
    cross = pivot.cross_table
    isempty(pivot.column_dimensions) &&
        return Any[join((describe_pivot_measure(measure) for measure in get_pivot_measures(pivot)), "  ")]
    Any[_make_pivot_key_labels(key) for key in cross.column_keys]
end

# The header of each row as a list that moves in step with the rows: the labels
# of its key, or `all` for the one row of a pivot with no row dimension. A pivot
# with no row has an empty vector.
function _make_pivot_row_header_list(pivot::PivotTable)
    cross = pivot.cross_table
    count = get_pivot_row_count(cross)
    count == 0 && return CellVector()
    leveled = !isempty(pivot.row_dimensions)
    make_index_list(count, 1, k -> leveled ? _make_pivot_key_labels(cross.row_keys[k]) : WidgetLabel("all"))
end

# The corner: the names of the row dimensions, one for each level of the row
# headers.
_make_pivot_corner(pivot::PivotTable) =
    isempty(pivot.row_dimensions) ? WidgetLabel("") :
        CellVector(Any[dimension.column for dimension in pivot.row_dimensions])

# The rows of the table as a list: row `k` holds the document of each of its
# cells. A pivot with no row has an empty vector.
function _make_pivot_row_list(pivot::PivotTable)
    cross = pivot.cross_table
    count = get_pivot_row_count(cross)
    count == 0 && return CellVector()
    width = get_pivot_column_count(cross)
    function row_of(k)
        cells = Cell[Cell(nothing) for _ in 1:width]
        for c in 1:width
            set_cell_computation!(cells[c], () -> pivot.cells[k][c])
        end
        CellVector(cells)
    end
    make_index_list(count, 1, row_of)
end

# ── The paths ────────────────────────────────────────────────────────────────

# The path in the grid of the pivot of its child `k`, followed by `tail`.
_make_pivot_grid_reference(k::Int, tail) =
    ConcreteReference(FieldReferenceStep("children"), ConcreteReference(RangeReferenceStep(k - 1, k), tail))

# The path inside child `k` of the grid from a path of the grid, or `nothing`.
function _find_pivot_grid_child_path(path, k::Int)
    path = strip_reference_types(path)
    (path isa ConcreteReference && path.head isa FieldReferenceStep && path.head.name == "children") ||
        return nothing
    tail = path.tail
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep && tail.head.stop == k &&
     tail.head.start == k - 1) || return nothing
    tail.tail
end

# The path in the table of `path`, a path of the pivot: `cells[r][c]…` is the
# cell, `cells[r]` the row, and a part that this projection introduced is its
# path in the table. `nothing` for any other path.
function _find_pivot_table_path(p, path)
    path = strip_reference_types(path)
    path isa EmptyReference && return EmptyReference()
    path isa ConcreteReference || return nothing
    head = path.head
    if head isa ProjectionReferenceStep
        (p === nothing || head.projection === p) || return nothing
        return _find_pivot_grid_child_path(head.output_path, 2)
    end
    (head isa FieldReferenceStep && head.name == "cells") || return nothing
    row = path.tail
    (row isa ConcreteReference && row.head isa RangeReferenceStep) || return nothing
    row.tail isa EmptyReference &&
        return ConcreteReference(FieldReferenceStep("rows"), ConcreteReference(row.head, EmptyReference()))
    path
end

# The selection of the table that shows the selection of `pivot`.
function _get_pivot_table_selection(pivot::PivotTable)
    selection = pivot.selection
    selection === nothing && return nothing
    _find_pivot_table_path(nothing, selection)
end

# The path of the pivot of `path`, a path in the table: `cells[r][c]…` is the
# cell, `rows[r]` the row; `nothing` for any other path.
function _find_pivot_path(path)
    path = strip_reference_types(path)
    (path isa ConcreteReference && path.head isa FieldReferenceStep) || return nothing
    row = path.tail
    (row isa ConcreteReference && row.head isa RangeReferenceStep) || return nothing
    path.head.name == "cells" && return path
    (path.head.name == "rows" && row.tail isa EmptyReference) &&
        return ConcreteReference(FieldReferenceStep("cells"), ConcreteReference(row.head, EmptyReference()))
    nothing
end

function map_reference_forward(p::PivotTableToWidget, iomap::PivotTableToWidgetIoMap, reference)
    reference isa Reference || return nothing
    path = _find_pivot_table_path(p, reference)
    path === nothing && return nothing
    path isa EmptyReference && return EmptyReference()
    _make_pivot_grid_reference(2, path)
end

function map_reference_backward(p::PivotTableToWidget, iomap::PivotTableToWidgetIoMap, reference)
    inner = reference isa Reference ? _find_pivot_grid_child_path(reference, 2) : nothing
    target = inner === nothing ? nothing : _find_pivot_path(inner)
    target === nothing || return annotate_reference_types(iomap.input, target)
    invoke(map_reference_backward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

"""
    make_pivot_table_projection(; measure, appearance = Appearance()) -> Projection

The projection that draws a [`PivotTable`](@ref): [`PivotTableToWidget`](@ref)
with the row height of the font of the widget theme of `appearance`, and the
grid that places its bar and its table. The natural renderer uses it for a pivot.
"""
function make_pivot_table_projection(; measure::TextMeasure, appearance::Appearance = Appearance())
    theme = get_scaled_theme!(appearance, WidgetTheme)
    row_height = UntrackedCell{Int}(@computation ceil(Int, compute_line_box(measure, "M", theme.font).height))
    grid = last(only(p for p in LayoutToGraphics().dispatch if first(p) === GridLayout))
    ChainingProjection(PivotTableToWidget(; row_height, zone_gap = get_widget_style(theme, :section_gap),
                                          chip_gap = get_widget_style(theme, :item_gap)), grid)
end
