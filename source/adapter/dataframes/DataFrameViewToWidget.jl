# Fragment of `DataFramesModule`.
#
# A `DataFrameView` drawn as a table that scrolls its own parts, and a scroll bar
# beside it. The table reads the rows of the view, a list anchored at `anchor`,
# so it builds only the rows it shows. The table shares the `scroll_position`
# and the `top_row` cells of the view, so a scroll of the table and a jump of
# the view write the same state, and the scroll bar shows where the top row is
# in the frame.

"""
    DataFrameViewToWidget(; row_height = 0, row_step = 0)

Projects a `DataFrameView` to a `WidgetTable`, which scrolls its own parts, and
a vertical `WidgetScrollBar` beside it, under the expression bar, in a
`GridLayout` of two rows. The expression bar is a field of the expression of
the query, and the header row holds a field of the filter of each column, so a
person filters the rows by typing there.
The header of a column shows its name and its element type, as a data frame
prints them in the REPL: `price :: Float64`, and `discount :: Float64?` for a
column that allows `missing`. Every column takes an equal share of the width
and is at least as wide as its header. A number aligns right. Each row shows
its row number in the frame in a header column, and the corner over it shows
the count of the rows, so the header column is as wide as the widest row
number. Every row is `row_height` tall, as a header column of a list needs.

A frame of more than 64 columns draws its columns as a list, from the column
`column_anchor` of the view, so it builds only the columns that the table
shows: each column is 160 pixels wide and at least as wide as its header, and
each row is `row_height` tall, the height of a line of the font of the table,
because a row as tall as its cells would change as the table scrolls to the
side. When the table moves its head column, the view moves `column_anchor`.

The scroll bar shows the row at the top of the table, `anchor + top_row - 1`,
among the rows of the frame. Its thumb is as long as the share of the rows that
the table shows, which the projection counts from the height it is offered and
`row_step`, the height of a row with its padding and its rule. A press on the
bar, or a move with the left button held, is a jump to the row at that place.

The table shows the columns that the query of the view does not hide. A press
on a header selects its column, as a `DataFrameColumnReferenceStep`, and the
header shows the selection; a press on the corner selects the view. A
selection of a row or of a cell has no place in the view yet, and goes nowhere.
The backward map names the column of a point on a header and the view of a
point on the corner, so a right click there opens the menu of the column or of
the view.
The reader gives the view a key that the table does not take, so the gestures
of `DataFrameView` answer Ctrl+Home and Ctrl+End. A scroll of the table passes
on.
"""
@projection UntrackedCell struct DataFrameViewToWidget
    row_height::Int
    row_step::Int
end

DataFrameViewToWidget(; row_height = 0, row_step = 0) = DataFrameViewToWidget(row_height, row_step)

@iomap struct DataFrameViewToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    table::Any               # the WidgetTable of the rows
    bar::Any                 # the WidgetScrollBar beside it
    visible::Cell            # Int: how many rows the table shows
end

# The width of the scroll bar beside the table.
const _SCROLL_BAR_WIDTH = 12

# A weight and no minimum: the table gives the column an equal share of the
# width, and the width of its header at least.
const _COLUMN_POLICY = SizePolicy(nothing, nothing, nothing, 1.0)

# A frame with more columns than this draws them as a list, each column this
# wide and at least as wide as its header.
const _LIST_COLUMN_COUNT = 64
const _LIST_COLUMN_WIDTH = 160

function print_document(p::DataFrameViewToWidget, recursion, view::DataFrameView, ctx)
    # The cells of the table follow the view, so a hidden column leaves the
    # table that is drawn, and the table builds its parts again.
    table = ncol(view.frame) > _LIST_COLUMN_COUNT ? _make_column_list_table(p, view) :
                                                    _make_view_table(p, view)
    height = ctx === nothing ? nothing : get_exact_height(ctx)
    # The rows that the table shows: the height less the expression bar and the
    # header row, which holds the filter row too, about four rows.
    visible = Cell(@computation (height === nothing || p.row_step <= 0) ? 1 :
                                max(1, Int(height[]) ÷ p.row_step - 4))
    count = Cell(@computation length(view.kept_rows))
    # Positional: orientation, value, thumb_size, position, size, visible,
    # margin, border, padding, style, tooltip, selection.
    bar = WidgetScrollBar(Cell(:vertical),
                          Cell(@computation _get_scroll_bar_value(view, count[], visible[])),
                          Cell(@computation count[] == 0 ? 1.0 : min(1.0, visible[] / count[])),
                          Cell(nothing), Cell(nothing), Cell(true), Cell(nothing), Cell(nothing),
                          Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    # The expression bar over the table, and the table and the scroll bar under
    # it; the cell beside the expression bar is empty.
    expression = _make_expression_bar(view)
    grid = GridLayout(Any[expression, WidgetLabel(""), table, bar], 2;
                      column_policies = Any[Fill, Fixed(_SCROLL_BAR_WIDTH)], row_policies = Any[Content, Fill])
    # The grid gives a key to the expression bar or to the table, by their
    # selection.
    set_cell_computation!(getfield(grid, :selection), () -> begin
        inner = expression.selection
        inner === nothing || return _make_grid_child_reference(1, inner)
        selection = table.selection
        selection === nothing ? nothing : _make_grid_child_reference(3, selection)
    end)
    DataFrameViewToWidgetIoMap(p, view, grid, table, bar, visible)
end

# Where the row at the top of the table is among the rows of the frame, from 0
# at the first row to 1 where the last row shows at the bottom.
function _get_scroll_bar_value(view::DataFrameView, count::Int, visible::Int)
    room = count - visible
    room <= 0 && return 0.0
    clamp((view.anchor + view.top_row - 2) / room, 0.0, 1.0)
end

# The row that a value of the scroll bar puts at the top of the table.
_get_scroll_bar_row(value::Real, count::Int, visible::Int) =
    1 + round(Int, clamp(Float64(value), 0.0, 1.0) * max(0, count - visible))

# The table of a frame whose columns share its width: every column a weight,
# and at least as wide as its header.
function _make_view_table(p::DataFrameViewToWidget, view::DataFrameView)
    headers = CellVector(@computation Any[_make_filter_header(view, name)
                                          for name in _get_shown_columns(view)])
    align = Cell(@computation Symbol[_get_column_align(eltype(view.frame[!, name]))
                                     for name in _get_shown_columns(view)])
    rows = Cell(@computation _make_row_list(view.frame, _get_shown_columns(view), view.kept_rows,
                                            view.anchor))
    row_headers, corner = _make_row_numbers(view)
    # Positional, so every declared field is named here in order: position,
    # column_headers, row_headers, corner, rows, column_count, border_width,
    # column_policy, row_policy, column_policies, row_policies, cell_policy,
    # column_cell_policies, column_align, visible, margin, border, padding,
    # style, scroll_position, top_row, tooltip. The table scrolls its
    # own parts, and its offset is the cell of the view.
    table = WidgetTable(Cell(Point2D(0, 0)), headers, row_headers, corner, rows,
                        Cell(@computation length(_get_shown_columns(view))), Cell(1),
                        Cell(_COLUMN_POLICY), Cell(Fixed(p.row_height)), Cell(Any[]), Cell(Any[]),
                        Cell(:clip), Cell(Symbol[]), align,
                        Cell(true), Cell(nothing), Cell(nothing), Cell(nothing),
                        Cell(nothing), getfield(view, :scroll_position),
                        getfield(view, :top_row), Cell(nothing),
                        Cell(@computation _get_table_selection(view, false)))
end

print_document(p::DataFrameViewToWidget, view::DataFrameView) =
    print_document(p, nothing, view, nothing)

# The header of each kept row, its row number in the frame, as a list that moves
# in step with the rows, and the corner of the filter row. A frame with no rows
# has neither.
function _make_row_numbers(view::DataFrameView)
    headers = Cell(@computation (kept = view.kept_rows;
                                 isempty(kept) ? CellVector() :
                                     _make_index_list(length(kept), view.anchor,
                                                      k -> WidgetLabel(string(kept[k])))))
    corner = Cell(@computation nrow(view.frame) == 0 ? nothing : _make_query_corner(view))
    (headers, corner)
end

# The table of a frame whose columns are a list: the headers, the alignments
# and the cells of every row are lists with their heads at `column_anchor`.
function _make_column_list_table(p::DataFrameViewToWidget, view::DataFrameView)
    type_of(name) = eltype(view.frame[!, name])
    # The headers are built when a walk reaches them, so the list reads the sort
    # keys itself, and a new sort builds the list again.
    headers = Cell(@computation (view.query.sort_keys; columns = _get_shown_columns(view);
        _make_index_list(length(columns), view.column_anchor, c -> _make_filter_header(view, columns[c]))))
    align = Cell(@computation (columns = _get_shown_columns(view);
        _make_index_list(length(columns), view.column_anchor, c -> _get_column_align(type_of(columns[c])))))
    rows = Cell(@computation _make_row_list(view.frame, _get_shown_columns(view), view.kept_rows,
                                            view.anchor, view.column_anchor))
    row_headers, corner = _make_row_numbers(view)
    # Positional, as in `_make_view_table` above.
    table = WidgetTable(Cell(Point2D(0, 0)), headers, row_headers, corner, rows, Cell(0), Cell(1),
                        Cell(Fixed(_LIST_COLUMN_WIDTH)), Cell(Fixed(p.row_height)),
                        Cell(Any[]), Cell(Any[]), Cell(:clip), Cell(Symbol[]), align,
                        Cell(true), Cell(nothing), Cell(nothing), Cell(nothing),
                        Cell(nothing), getfield(view, :scroll_position),
                        getfield(view, :top_row), Cell(nothing),
                        Cell(@computation _get_table_selection(view, true)))
end

# The selection of the table that shows the selection of `view`: the header of
# the selected column, counted from the head column when the columns are a
# list; the field of a filter or of the pattern, with its caret; and the whole
# table for the whole view.
function _get_table_selection(view::DataFrameView, column_list::Bool)
    selection = view.selection
    selection === nothing && return nothing
    selection = strip_reference_types(selection)
    selection isa EmptyReference && return EmptyReference()
    found = _find_query_text_selection(view)
    if found !== nothing
        found[1] === :expression && return nothing
        field = _make_field_child_reference(_make_content_range_reference(found[2]))
        found[1] === :pattern && return ConcreteReference(FieldReferenceStep("corner"), field)
        return _make_header_reference(view, view.query.column_filters[found[1]].column, field, column_list)
    end
    (selection isa ConcreteReference && selection.head isa DataFrameColumnReferenceStep) || return nothing
    _make_header_reference(view, selection.head.name, EmptyReference(), column_list)
end

# The path in the table of the header of column `name`, followed by `tail`, or
# `nothing` when the view does not show the column.
function _make_header_reference(view::DataFrameView, name::String, tail, column_list::Bool)
    c = findfirst(==(name), _get_shown_columns(view))
    c === nothing && return nothing
    column_list && (c -= view.column_anchor - 1)
    ConcreteReference(FieldReferenceStep("column_headers"),
                      ConcreteReference(RangeReferenceStep(c - 1, c), tail))
end

"""
    make_data_frame_view_projection(; measure, appearance = Appearance()) -> Projection

The row of the natural renderer for a `DataFrameView`: `DataFrameViewToWidget`,
then the printer of a grid, which prints the table and the scroll bar through
the recursion. A row of the natural renderer ends in graphics, because a type
dispatch does not print an output again. The table draws with the widget theme
of `appearance`. The height of a row is a line of the font of that theme, and
its step adds the padding of a cell of the theme and a rule; both read the
scaled theme at each print, with no edge, as a style field of a widget does.
"""
function make_data_frame_view_projection(; measure::TextMeasure,
                                         appearance::Appearance = Appearance())
    theme = get_scaled_theme!(appearance, WidgetTheme)
    widgets = WidgetToGraphics(; measure, theme)
    table = last(only(p for p in widgets.dispatch if first(p) === WidgetTable))
    grid = last(only(p for p in LayoutToGraphics().dispatch if first(p) === GridLayout))
    row_height = UntrackedCell{Int}(@computation ceil(Int, compute_line_box(measure, "M", theme.font).height))
    row_step = UntrackedCell{Int}(@computation row_height[] + 2 * Int(table.cell_padding.top[]) + 1)
    ChainingProjection(DataFrameViewToWidget(; row_height, row_step), grid)
end

# The name of a column and its element type. A type that allows `missing`
# prints as the type without it and a `?`, as a data frame prints it.
function _get_header_text(name, type::Type)
    shown = nonmissingtype(type)
    suffix = (type !== shown && shown !== Union{}) ? "?" : ""
    string(name, " :: ", shown === Union{} ? type : shown, suffix)
end

_get_column_align(type::Type) =
    (nonmissingtype(type) <: Real && !(nonmissingtype(type) <: Bool)) ? :right : :left

# ── read_intent ───────────────────────────────────────────────────────────────

# A key that the table does not take: the gestures of the view answer it.
read_intent(::DataFrameViewToWidget, iomap::DataFrameViewToWidgetIoMap, event::KeyDown) =
    read_gesture(iomap.input, event)

# A selection in the table selects in the view: a header selects its column, a
# field of the filter row or of the expression bar its text, and the corner or
# the whole table the view. Any other place in the table has no place in the
# view yet.
function read_intent(::DataFrameViewToWidget, iomap::DataFrameViewToWidgetIoMap,
                     operation::ReplaceSelectionOperation)
    expression = _find_expression_path(operation.path)
    expression === nothing ||
        return ReplaceSelectionOperation(annotate_reference_types(iomap.input, expression))
    path = _find_table_path(operation.path)
    path === nothing && return nothing
    target = _find_view_path(iomap, path)
    target === nothing ? nothing : ReplaceSelectionOperation(annotate_reference_types(iomap.input, target))
end

# A place in the table that has a place in the view maps back to it, as a
# selection there does (`_find_view_path`): the header of a column to the column,
# a field of the query to its text, and the corner to the view. So a right click on
# the header of a column reads the gesture table of the column. Any other place is
# a part that the view introduced, as the default map of the kernel says.
function map_reference_backward(p::DataFrameViewToWidget,
                                iomap::DataFrameViewToWidgetIoMap, reference)
    path = reference isa Reference ? _find_table_path(reference) : nothing
    target = path === nothing ? nothing : _find_view_path(iomap, path)
    target === nothing || return annotate_reference_types(iomap.input, target)
    invoke(map_reference_backward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

# The path in the grid of the view of its child `k`, followed by `tail`.
_make_grid_child_reference(k::Int, tail) =
    ConcreteReference(FieldReferenceStep("children"), ConcreteReference(RangeReferenceStep(k - 1, k), tail))

# The path inside the table from a path in the grid of the view, whose third
# child is the table; `nothing` for a path that does not go into the table.
function _find_table_path(path)
    path = strip_reference_types(path)
    (path isa ConcreteReference && path.head isa FieldReferenceStep && path.head.name == "children") ||
        return nothing
    tail = path.tail
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep && tail.head.start == 2 &&
     tail.head.stop == 3) || return nothing
    tail.tail
end

# The path in the view of `path`, a path in the table: the text of the query and
# its range for a field of the filter row, the view for the table and for the
# rest of its corner, a column for the header of the column, and `nothing` for
# any other place.
function _find_view_path(iomap::DataFrameViewToWidgetIoMap, path)
    path isa EmptyReference && return EmptyReference()
    (path isa ConcreteReference && path.head isa FieldReferenceStep) || return nothing
    view = iomap.input
    text = _find_query_text_path(view, path, c -> _find_shown_column(iomap, c))
    text === nothing || return text
    path.head.name == "corner" && return EmptyReference()
    path.head.name == "column_headers" || return nothing
    tail = path.tail
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep && tail.tail isa EmptyReference) ||
        return nothing
    name = _find_shown_column(iomap, tail.head.stop)
    name === nothing ? nothing : _make_column_reference(name)
end

# The name of the column of header `c` of the table, counted from the head
# column when the columns are a list, or `nothing`.
function _find_shown_column(iomap::DataFrameViewToWidgetIoMap, c::Int)
    view = iomap.input
    iomap.table.column_headers isa ListNode && (c += view.column_anchor - 1)
    columns = _get_shown_columns(view)
    1 <= c <= length(columns) ? columns[c] : nothing
end

# An edit of a field of the filter row or of the expression bar is an edit of
# the text of the query, and the view shows the result of the new query from
# its start.
function read_intent(::DataFrameViewToWidget, iomap::DataFrameViewToWidgetIoMap,
                     operation::ReplaceStringRangeOperation)
    target = _find_expression_path(operation.reference)
    if target === nothing
        path = _find_table_path(operation.reference)
        path === nothing && return nothing
        target = _find_view_path(iomap, path)
    end
    (target isa ConcreteReference && target.head == FieldReferenceStep("query")) || return nothing
    view = iomap.input
    _make_query_edit_operation(view, ReplaceStringRangeOperation(annotate_reference_types(view, target),
                                                                 operation.replacement))
end

# A scroll of the table writes the cell that the view shares with it, and
# every other operation of the widgets carries its own subject: both pass on.
# A table that moves the head of its rows far from the anchor writes its
# `rows`; the view moves its anchor instead, and builds a new list from it. A
# table that moves its head column writes its `column_headers`, its
# `column_align` and its `rows`; the view moves its column anchor instead, and
# builds the three lists again from it. A write of the value of the scroll bar
# is a jump to the row at that value.
function read_intent(::DataFrameViewToWidget, iomap::DataFrameViewToWidgetIoMap, operation::Operation)
    bar = _find_written_field(iomap.bar, operation)
    if bar !== nothing && bar[1] == "value"
        count = length(iomap.input.kept_rows)
        return jump_to_row(iomap.input, _get_scroll_bar_row(bar[2], count, Int(iomap.visible)))
    end
    _convert_table_writes(iomap, operation)
end

# The field of `document` that `operation` writes, and the value it writes, or
# `nothing`.
function _find_written_field(document, operation)
    write = operation isa ReplaceViewStateOperation ? get_wrapped_operation(operation) : operation
    (write isa ReplaceReferencedValueOperation && write.document === document &&
     write.reference isa ConcreteReference && write.reference.head isa FieldReferenceStep) ||
        return nothing
    (write.reference.head.name, write.value)
end

# `operation` with the writes of the lists of the table turned into writes of
# the anchors of the view.
function _convert_table_writes(iomap::DataFrameViewToWidgetIoMap, operation)
    operation isa CompoundOperation || return _convert_table_write(iomap, operation, false)
    columns = any(o -> something(_find_written_field(iomap.table, o), ("",))[1] == "column_headers",
                  operation.operations)
    CompoundOperation(Any[o for o in (_convert_table_write(iomap, o, columns) for o in operation.operations)
                          if o !== nothing])
end

# One write of a compound: `rows` to an anchor, `column_headers` to a column
# anchor, and, when the compound moves the columns, no write of `rows` or of
# `column_align`, which the view builds again from its anchors.
function _convert_table_write(iomap::DataFrameViewToWidgetIoMap, operation, columns::Bool)
    written = _find_written_field(iomap.table, operation)
    written === nothing && return operation
    field, value = written
    view = iomap.input
    if field == "column_headers"
        c = _find_row_index(iomap.table.column_headers, value)
        c === nothing && return nothing
        return ReplaceViewStateOperation(ReplaceReferencedValueOperation(
            view, "column_anchor", view.column_anchor + c - 1))
    end
    columns && field in ("rows", "column_align") && return nothing
    # The row headers move in step with the rows, and the view builds both
    # again from its anchor.
    field == "row_headers" && return nothing
    field == "rows" || return operation
    k = _find_row_index(iomap.table.rows, value)
    k === nothing && return nothing
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(view, "anchor", view.anchor + k - 1))
end

# The index of `node` in the list of `head`, counted from the head, or
# `nothing` when it is not within the walk of a relocation.
function _find_row_index(head, node; limit::Int = 10_000)
    head isa ListNode || return nothing
    forward, backward = head, head
    for k in 0:limit
        forward === node && return 1 + k
        backward === node && return 1 - k
        forward = forward === nothing ? nothing : forward.next
        backward = backward === nothing ? nothing : backward.prev
        forward === nothing && backward === nothing && return nothing
    end
    nothing
end

read_intent(::DataFrameViewToWidget, ::DataFrameViewToWidgetIoMap, event) = nothing
