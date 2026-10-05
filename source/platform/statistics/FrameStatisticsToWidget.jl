# Fragment of `FrameStatisticsModule` — the projection of a
# [`FrameStatistics`](FrameStatisticsDocument.jl) onto widgets: a head line with
# the frame counts and a Pause toggle, a table of the summary of each
# measurement, and a table of the recent frames, newest first.

"""
    FrameStatisticsToWidget(; header_text, row_text, empty_text, slow_text, gap, row_height = 0)

Draw a [`FrameStatistics`](@ref) as widgets, from top to bottom:

- a head line with the number of frames since the start and the number that the
  tables cover, and a Pause toggle that holds the cell of `paused`;
- "Summary": one row for each measurement, with its unit, the number of frames
  that it covers, its minimum, maximum, mean, standard deviation and total;
- "Frames, newest first": one row for each recent frame, with the frame number
  as the row header and one column for each measurement.

A time shows in milliseconds with two decimals, and the total of a time with
none. A count shows as a whole number, and its mean and deviation with one
decimal. A value that a frame did not measure shows a dash. A frame whose
`frame_time` is more than two times the median of the frames of the table is
slow: its frame number and its cells draw in `slow_text`.

The table of the frames builds only the rows that it shows: its rows are a list
whose head is the row `anchor`, counted from the newest frame, and it shares the
cells of `top_row` and `scroll_position` of the document. When the table moves
the head of its list, the reader writes `anchor` instead, and the list starts
again from there. A press on Pause writes `paused` as view state, so the undo
does not record it. Every row of that table is `row_height` tall, a line of the
font of `row_text`, which `make_frame_statistics_projection` measures.

Read only: no caret goes into a table.
"""
@projection UntrackedCell struct FrameStatisticsToWidget <: Projection
    header_text::StyleText = get_frame_statistics_style(nothing, :header_text)
    row_text::StyleText = get_frame_statistics_style(nothing, :row_text)
    empty_text::StyleText = get_frame_statistics_style(nothing, :empty_text)
    slow_text::StyleText = get_frame_statistics_style(nothing, :slow_text)
    gap::Int = get_frame_statistics_style(nothing, :gap)
    row_height::Int = 0
end

"""
    make_frame_statistics_projection(; theme = nothing, measure = nothing) -> FrameStatisticsToWidget

The projection of the statistics, with the styles of `theme`: a
`FrameStatisticsTheme`, scaled or not, or the default styles for `nothing`.
With a `measure`, the rows of the table of the frames are a line of the font of
the rows tall, and they follow the scale of the theme.
"""
function make_frame_statistics_projection(; theme = nothing, measure = nothing)
    get_style(name) = get_frame_statistics_style(theme, name)
    row_text = get_style(:row_text)
    row_height = measure === nothing ? 0 :
        UntrackedCell{Int}(@computation ceil(Int, compute_line_box(measure, "M",
                                                                   _read_style(row_text).font).height))
    FrameStatisticsToWidget(; header_text = get_style(:header_text), row_text,
                            empty_text = get_style(:empty_text), slow_text = get_style(:slow_text),
                            gap = get_style(:gap), row_height)
end

# A style that a builder gave: a cell that reads the theme, or a plain value.
_read_style(style::AbstractCell) = style[]
_read_style(style) = style

# The columns of the summary, and how each aligns.
const _SUMMARY_HEADERS = ("measurement", "unit", "frames", "minimum", "maximum", "mean",
                          "deviation", "total")
const _SUMMARY_ALIGN = [:left, :left, :right, :right, :right, :right, :right, :right]

# Every column of the table of the frames takes an equal share of the width.
const _FRAME_COLUMN_POLICY = SizePolicy(nothing, nothing, nothing, 1.0)

function print_document(p::FrameStatisticsToWidget, recursion, statistics::FrameStatistics, ctx)
    head = HorizontalLayout(Any[
            WidgetLabel(() -> _format_head_line(statistics); text_style = p.header_text),
            _make_pause_toggle(statistics)];
        vertical_align = :center, gap = 4 * p.gap)
    root = VerticalLayout(Any[]; horizontal_align = :left, gap = p.gap)
    # The parts are built again only when a measurement appears, because only
    # the count of the rows is read here: a flush changes the labels of the
    # numbers and the rows of the table of the frames, which read their own
    # cells.
    set_cell_computation!(getfield(root.children, :elements), () -> begin
        rows = statistics.rows
        isempty(rows) && return Cell[Cell(head), Cell(WidgetLabel("no frame yet"; text_style = p.empty_text))]
        summary = [rows[index] for index in 1:length(rows)]
        Cell[Cell(head),
             Cell(WidgetLabel("Summary"; text_style = p.header_text)),
             Cell(_make_summary_table(p, summary)),
             Cell(WidgetLabel("Frames, newest first"; text_style = p.header_text)),
             Cell(LayoutConstraint(_make_frame_table(p, statistics, summary);
                                   width = Fill, height = Fill))]
    end)
    SimpleIoMap(p, statistics, root)
end

# "1234 frames, the tables cover the last 1000": the frames since the start, and
# how many of them the tables cover when that is fewer.
function _format_head_line(statistics::FrameStatistics)
    frame_count = statistics.frame_count
    rows = statistics.rows
    covered = isempty(rows) ? 0 : maximum(rows[index].count for index in 1:length(rows))
    covered < frame_count ? "$(frame_count) frames, the tables cover the last $(covered)" :
                            "$(frame_count) frames"
end

# The Pause toggle holds the cell of `paused`, so a press writes the document.
_make_pause_toggle(statistics::FrameStatistics) =
    WidgetToggle(Cell(Point2D(0, 0)), Cell("Pause"), getfield(statistics, :paused), Cell(true),
                 Cell(true), Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing),
                 Cell(nothing), Cell(nothing))

_make_cell_label(p::FrameStatisticsToWidget, content; slow::Bool = false) =
    WidgetLabel(content; text_style = slow ? p.slow_text : p.row_text)

# A frame is slow when its frame time is more than this many times the median.
const _SLOW_FRAME_FACTOR = 2

# The frame time above which a frame is slow: two times the median of the
# column `column` of `columns`, without the frames that did not measure it.
# `Inf` when the table has no such column, so no frame is slow.
function _compute_slow_frame_limit(columns::Vector, column::Union{Int,Nothing})
    (column === nothing || column > length(columns)) && return Inf
    values = sort!(filter(!isnan, columns[column]))
    isempty(values) && return Inf
    count = length(values)
    median = isodd(count) ? values[(count + 1) ÷ 2] : (values[count ÷ 2] + values[count ÷ 2 + 1]) / 2
    _SLOW_FRAME_FACTOR * median
end

# Whether the frame at the place `i` of `columns` is slow.
_is_slow_frame(columns::Vector, column::Union{Int,Nothing}, limit::Float64, i::Int) =
    column !== nothing && column <= length(columns) && columns[column][i] > limit

# The unit of a row as its column shows it.
_format_unit(row::FrameStatisticsRow) = row.unit === :second ? "ms" : ""

# One number of a summary row. A time shows in milliseconds with two decimals,
# and its total with none. A count shows as a whole number, and its mean and
# deviation with one decimal. A row that no recent frame measured shows a dash.
function _format_summary_value(row::FrameStatisticsRow, field::Symbol)
    row.count == 0 && return "-"
    value = getproperty(row, field)
    if row.unit === :second
        return field === :total ? @sprintf("%.0f", value * 1000) : @sprintf("%.2f", value * 1000)
    end
    field in (:mean, :standard_deviation) ? @sprintf("%.1f", value) : @sprintf("%.0f", value)
end

# One value of a frame: a time in milliseconds with two decimals, a count as a
# whole number, and a dash where the frame did not measure the name.
function _format_frame_value(unit::Symbol, value::Float64)
    isnan(value) && return "-"
    unit === :second ? @sprintf("%.2f", value * 1000) : @sprintf("%.0f", value)
end

# The summary: one row for each measurement. Each number is a label of its own
# that reads its field, so a flush changes only the labels whose numbers changed.
function _make_summary_table(p::FrameStatisticsToWidget, summary::Vector)
    rows = Any[Any[_make_cell_label(p, row.name), _make_cell_label(p, _format_unit(row)),
                   _make_cell_label(p, () -> string(row.count)),
                   (_make_cell_label(p, () -> _format_summary_value(row, field))
                    for field in (:minimum, :maximum, :mean, :standard_deviation, :total))...]
               for row in summary]
    WidgetTable(Any[WidgetLabel(text; text_style = p.header_text) for text in _SUMMARY_HEADERS], rows;
                column_align = _SUMMARY_ALIGN)
end

# The header of a column of the frames: its name, and `(ms)` for a time.
_format_frame_header(row::FrameStatisticsRow) =
    row.unit === :second ? string(row.name, " (ms)") : row.name

# The table of the frames. Its rows and its row headers are lists from `anchor`,
# counted from the newest frame, and every flush builds them again from the
# frames of the document; the table builds only the rows that it shows. A list
# keeps the frames and the columns that it was built from, so a row that a walk
# builds later shows the same flush. The columns are those of `summary`, so the
# headers and the cells agree while a new measurement reaches the parts.
function _make_frame_table(p::FrameStatisticsToWidget, statistics::FrameStatistics, summary::Vector)
    units = [row.unit for row in summary]
    slow_column = findfirst(row -> row.name == "frame_time", summary)
    headers = CellVector(Cell[Cell(WidgetLabel(_format_frame_header(row); text_style = p.header_text))
                              for row in summary])
    rows = Cell(@computation begin
        columns = statistics.columns
        limit = _compute_slow_frame_limit(columns, slow_column)
        _make_frame_list(statistics, i -> begin
            slow = _is_slow_frame(columns, slow_column, limit, i)
            make_widget_table_row(Any[
                _make_cell_label(p, _format_frame_value(units[c], c <= length(columns) ? columns[c][i] : NaN);
                                 slow)
                for c in eachindex(units)])
        end)
    end)
    row_headers = Cell(@computation begin
        frames, columns = statistics.frames, statistics.columns
        limit = _compute_slow_frame_limit(columns, slow_column)
        _make_frame_list(statistics, i -> _make_cell_label(p, string(frames[i]);
                                                           slow = _is_slow_frame(columns, slow_column, limit, i)))
    end)
    # Positional, so every declared field is named here in order: position,
    # column_headers, row_headers, corner, rows, columns, column_count,
    # border_width, column_policy, row_policy, column_policies, row_policies,
    # cell_policy, column_cell_policies, column_align, visible, margin, border,
    # padding, style, scroll_position, top_row, column_drag, open_cells, tooltip.
    WidgetTable(Cell(Point2D(0, 0)), headers, row_headers,
                Cell(WidgetLabel("frame"; text_style = p.header_text)), rows,
                Cell(WidgetTableColumns()), Cell(length(units)), Cell(1),
                Cell(_FRAME_COLUMN_POLICY), Cell(Fixed(p.row_height)), Cell(Any[]), Cell(Any[]),
                Cell(:clip), Cell(Symbol[]), Cell(fill(:right, length(units))),
                Cell(true), Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing),
                getfield(statistics, :scroll_position), getfield(statistics, :top_row),
                Cell(nothing), Cell(nothing), Cell(nothing))
end

# The list of the recent frames, newest first, with its head at `anchor`:
# `value_of(i)` makes the value of the frame at the place `i` of `frames`. A
# table with no frame has an empty vector of rows.
function _make_frame_list(statistics::FrameStatistics, value_of)
    count = length(statistics.frames)
    count == 0 && return CellVector()
    make_index_list(count, statistics.anchor, k -> value_of(count - k + 1))
end

# No caret goes into a table. The default backward mapping names a part of a
# table by an introduced reference, so a point names the cell under it, and only
# such a reference maps forward again.
map_reference_forward(p::FrameStatisticsToWidget, iomap, reference) = find_introduced_path(p, reference)

# A write of the widgets passes on through the default reader, but three. A
# table that moves the head of its list of frames writes its `rows`, which
# becomes a write of `anchor`, so the list starts again from there, and its
# `row_headers`, which the same anchor builds again, so that write does nothing.
# A press on Pause becomes view state, so the undo does not record it.
function read_intent(p::FrameStatisticsToWidget, iomap::SimpleIoMap, operation::Operation)
    converted = _convert_widget_write(iomap.input, operation)
    converted === nothing || return converted
    invoke(read_intent, Tuple{Projection, Any, Any}, p, iomap, operation)
end

# The widget and the name of the field that `write` writes, or `nothing`.
function _find_written_widget_field(write)
    (write isa ReplaceReferencedValueOperation && write.reference isa ConcreteReference &&
     write.reference.head isa FieldReferenceStep) || return nothing
    (write.document, write.reference.head.name)
end

# The answer of this projection to one write, or `nothing` for a write that the
# default reader maps.
function _convert_widget_write(statistics::FrameStatistics, operation)
    if operation isa ReplaceViewStateOperation
        write = get_wrapped_operation(operation)
        written = _find_written_widget_field(write)
        written === nothing && return nothing
        document, field = written
        document isa WidgetTable || return nothing
        field == "row_headers" && return DoNothingOperation()
        (field == "rows" && write.value isa ListNode) || return nothing
        k = find_list_index(document.rows, write.value)
        k === nothing && return DoNothingOperation()
        return ReplaceViewStateOperation(
            ReplaceReferencedValueOperation(statistics, "anchor", statistics.anchor + k - 1))
    end
    written = _find_written_widget_field(operation)
    written === nothing && return nothing
    document, field = written
    (document isa WidgetToggle && field == "pressed") || return nothing
    ReplaceViewStateOperation(operation)
end
