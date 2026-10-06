# Fragment of `PivotModule`.
#
# A part of a table drawn as a read-only table: a header for each column, and a
# label for each value. The rows are a list, so the table builds only the rows
# that it shows, and a part of a million rows costs the rows on the screen.

"""
    PivotPartTableToWidget(; row_height)

Projects a [`PivotPartTable`](@ref) to a `WidgetTable`: a column for each of its
columns, and a row for each row of its part, each `row_height` tall. A row header
shows the number of the row in the part, and the corner the count of the rows.
"""
@projection UntrackedCell struct PivotPartTableToWidget
    row_height::Int = 0
end

function print_document(p::PivotPartTableToWidget, recursion, table::PivotPartTable, ctx)
    part = table.part
    columns = table.columns
    count = get_table_row_count(part)
    cells = count == 0 ? CellVector() :
        make_index_list(count, 1, r -> CellVector(Cell[Cell(WidgetLabel(format_pivot_value(
            get_table_value(part, r, column)))) for column in columns]))
    row_headers = count == 0 ? CellVector() : make_index_list(count, 1, r -> WidgetLabel(string(r)))
    policy = SizePolicy(nothing, nothing, nothing, 1.0)
    widget = WidgetTable(Cell(Point2D(0, 0)), CellVector(Any[WidgetLabel(column) for column in columns]), Cell(row_headers),
                         Cell(WidgetLabel(string(count))), Cell(cells), Cell(:row_major),
                         Cell(WidgetTableRows(nothing)),
                         Cell(Any[WidgetTableColumn(; policy) for _ in columns]), Cell(1), Cell(policy),
                         Cell(Fixed(p.row_height)), Cell(:clip), Cell(true), Cell(nothing), Cell(nothing),
                         Cell(nothing), Cell(nothing), Cell(Point2D(0, 0)), Cell(1), Cell(nothing),
                         Cell(:auto), Cell(:auto), Cell(nothing), Cell(nothing), Cell(nothing))
    SimpleIoMap(p, table, widget)
end

"""
    make_pivot_part_table_projection(; measure, appearance = Appearance()) -> Projection

The projection that draws a [`PivotPartTable`](@ref): [`PivotPartTableToWidget`](@ref)
with the row height of the font of the widget theme of `appearance`, and the
printer of the table.
"""
function make_pivot_part_table_projection(; measure::TextMeasure, appearance::Appearance = Appearance())
    theme = get_scaled_theme!(appearance, WidgetTheme)
    widgets = WidgetToGraphics(; measure, theme, graphics_theme = get_scaled_theme!(appearance, GraphicsTheme))
    table = last(only(p for p in widgets.dispatch if first(p) === WidgetTable))
    row_height = UntrackedCell{Int}(@computation ceil(Int, compute_line_box(measure, "M", theme.font).height))
    ChainingProjection(PivotPartTableToWidget(; row_height), table)
end
