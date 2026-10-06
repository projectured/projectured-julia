# Fragment of `DataFramesModule`.
#
# A `DataFrameView` drawn as a table that scrolls its own parts, with the scroll
# bar of the view beside its rows. The table reads the rows of the view, a list
# anchored at `anchor`, so it builds only the rows it shows. The table shares
# the `scroll_position` and the `top_row` cells of the view, so a scroll of the
# table and a jump of the view write the same state, and the scroll bar shows
# where the top row is in the frame.

"""
    DataFrameViewToWidget(; row_height = 0, row_step = 0, query_field_width, …)

Projects a `DataFrameView` to a `WidgetTable`, which scrolls its own parts and
draws the vertical `WidgetScrollBar` of the view over the right edge of its rows,
under the expression bar, in a `GridLayout` of two rows. The expression bar is a field of the expression of
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
shows: each column is `list_column_width` pixels wide and at least as wide as
its header, and each row is `row_height` tall, the height of a line of the font
of the table, because a row as tall as its cells would change as the table
scrolls to the side. When the table moves its head column, the view moves
`column_anchor`.

The scroll bar shows the row at the top of the table, `anchor + top_row - 1`,
among the rows of the frame. Its thumb is as long as the share of the rows that
the table shows, which the projection counts from the height it is offered and
`row_step`, the height of a row with its padding and its rule. A write of the
value of the bar, by a click on its track or a drag of its thumb, is a jump to
the row at that place. The drag of the thumb comes back to the table by an
introduced reference, so the table gives it to the bar wherever the pointer
goes.

The table shows the columns that the query of the view does not hide. A path
of the view names a row and a column of the frame by their numbers, and the
view maps it to the table and back: `columns[c]` is the column that the table
shows, `rows[r]` the row among the kept rows counted from the head of the list,
and `rows[r][c]` their cell; a header maps to its column or its row. So a press
on a header selects its column, a press on a row header its row, and the table
shows the selection; a press on the corner selects the view. The backward map
names the column of a point on a header and the view of a point on the corner,
so a right click there opens the menu of the column or of the view.
The reader gives the view a key that the table does not take, so the gestures
of `DataFrameView` answer Ctrl+Home and Ctrl+End. A scroll of the table passes
on.

The projection holds its styles and no theme; `make_data_frame_view_projection`
fills them from the `DataFrameTheme` of its appearance, and with none it holds
the default styles: the width of a field of the filter row and of the expression bar, the
gaps of their parts, the color of a query that does not parse and of the
glyph of a column that does not sort, and `list_column_width`. The table
draws the bar at the thickness of its widget theme.
"""
@projection UntrackedCell struct DataFrameViewToWidget
    row_height::Int = 0
    row_step::Int = 0
    query_field_width::Int = get_data_frame_style(nothing, :query_field_width)
    expression_field_width::Int = get_data_frame_style(nothing, :expression_field_width)
    find_field_width::Int = get_data_frame_style(nothing, :find_field_width)
    filter_gap::Int = get_data_frame_style(nothing, :filter_gap)
    expression_gap::Int = get_data_frame_style(nothing, :expression_gap)
    invalid_query::StyleColor = get_data_frame_style(nothing, :invalid_query)
    unsorted_glyph::StyleColor = get_data_frame_style(nothing, :unsorted_glyph)
    list_column_width::Int = get_data_frame_style(nothing, :list_column_width)
end

@iomap struct DataFrameViewToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    table::Any               # the WidgetTable of the rows
    bar::Any                 # the WidgetScrollBar of the view, which the table draws
    visible::Cell            # Int: how many rows the table shows
end

# A weight and no minimum: the table gives the column an equal share of the
# width, and the width of its header at least.
const _COLUMN_POLICY = SizePolicy(nothing, nothing, nothing, 1.0)

# A frame with more columns than this draws them as a list, each column
# `p.list_column_width` wide and at least as wide as its header.
const _LIST_COLUMN_COUNT = 64

function print_document(p::DataFrameViewToWidget, recursion, view::DataFrameView, ctx)
    height = ctx === nothing ? nothing : get_exact_height(ctx)
    # The rows that the table shows: the height less the expression bar and the
    # header row, which holds the filter row too, about four rows.
    visible = Cell(@computation (height === nothing || p.row_step <= 0) ? 1 :
                                max(1, Int(height[]) ÷ p.row_step - 4))
    count = Cell(@computation length(view.kept_rows))
    # Positional: orientation, value, thumb_size, thumb_drag, position, size,
    # visible, margin, border, padding, style, tooltip, selection.
    bar = WidgetScrollBar(Cell(:vertical),
                          Cell(@computation compute_scroll_bar_value(view.anchor + view.top_row - 1,
                                                                     count[], visible[])),
                          Cell(@computation count[] == 0 ? 1.0 : min(1.0, visible[] / count[])),
                          Cell(nothing), Cell(nothing), Cell(nothing), Cell(true), Cell(nothing),
                          Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    # The view is the one that the pointer reaches, so the bar lights from the
    # mouse target of the view, as the table does.
    set_cell_computation!(getfield(bar, :mouse_target), () -> _get_bar_mouse_target(view))
    # The cells of the table follow the view, so a hidden column leaves the
    # table that is drawn, and the table builds its parts again.
    table = ncol(view.frame) > _LIST_COLUMN_COUNT ? _make_column_list_table(p, view, bar) :
                                                    _make_view_table(p, view, bar)
    # The expression bar over the table.
    expression = _make_expression_bar(p, view)
    grid = GridLayout(Any[expression, table], 1; column_policies = Any[Fill], row_policies = Any[Content, Fill])
    # The grid gives a key to the expression bar or to the table, by their
    # selection.
    set_cell_computation!(getfield(grid, :selection), () -> begin
        inner = expression.selection
        inner === nothing || return _make_grid_child_reference(1, inner)
        selection = table.selection
        selection === nothing ? nothing : _make_grid_child_reference(2, selection)
    end)
    DataFrameViewToWidgetIoMap(p, view, grid, table, bar, visible)
end

# The table of a frame whose columns share its width: every column a weight,
# and at least as wide as its header.
function _make_view_table(p::DataFrameViewToWidget, view::DataFrameView, bar::WidgetScrollBar)
    headers = CellVector(@computation Any[_make_filter_header(p, view, name)
                                          for name in _get_shown_columns(view)])
    rows = Cell(@computation _make_row_list(view, _get_shown_columns(view), view.kept_rows, view.anchor))
    row_headers, corner = _make_row_numbers(p, view)
    # The data of the shown columns. A column that a person gave a width has it,
    # and the others share the rest.
    column_of = _make_column_documents(view, _COLUMN_POLICY)
    columns = Cell(@computation Any[column_of(name) for name in _get_shown_columns(view)])
    # Positional, so every declared field is named here in order: position,
    # column_headers, row_headers, corner, cells, cell_order, rows, columns, border_width,
    # column_policy, row_policy, cell_policy, visible, margin, border, padding,
    # style, scroll_position, top_row, column_drag, vertical_scroll_bar,
    # horizontal_scroll_bar, open_cells, tooltip. The
    # table scrolls its own parts, and its offset is the cell of the view.
    table = WidgetTable(Cell(Point2D(0, 0)), headers, row_headers, corner, rows,
                        Cell(:row_major), Cell(WidgetTableRows(nothing)), columns, Cell(1),
                        Cell(_COLUMN_POLICY), Cell(Fixed(p.row_height)), Cell(:clip),
                        Cell(true), Cell(nothing), Cell(nothing), Cell(nothing),
                        Cell(nothing), getfield(view, :scroll_position),
                        getfield(view, :top_row), Cell(nothing), Cell(bar), Cell(:auto),
                        Cell(@computation _get_table_open_cells(view, false)), Cell(nothing),
                        Cell(@computation _get_table_selection(view, false)))
    set_cell_computation!(getfield(table, :mouse_target), () -> _get_table_mouse_target(view))
    table
end

# The part of the table under the pointer: the mouse target of the view names a
# part of the output of the view, and the part of the table is that path from the
# table on. So the table lights the row, the column or the edge of a column under
# the pointer, as it lights its selection from the selection of the view.
function _get_table_mouse_target(view::DataFrameView)
    target = view.mouse_target
    target isa Reference ? _find_table_path(target) : nothing
end

# The mouse target of the bar: the empty path while the part of the table under
# the pointer is the bar.
function _get_bar_mouse_target(view::DataFrameView)
    target = _get_table_mouse_target(view)
    target isa ConcreteReference && target.head == FieldReferenceStep("vertical_scroll_bar") ?
        EmptyReference() : nothing
end

# The data of the column `name` of the table, one document for each name, made
# when the table first shows the column: its width, `Fixed` at the width that a
# person gave it, else `default`, and its alignment, both computations over the
# view. So a new width writes no column, and only what reads the width computes
# again.
function _make_column_documents(view::DataFrameView, default)
    made = Dict{String,WidgetTableColumn}()
    name -> get!(made, name) do
        column = WidgetTableColumn()
        set_cell_computation!(getfield(column, :policy), () -> _get_column_width_policy(view, name, default))
        set_cell_computation!(getfield(column, :align), () -> _get_column_align(eltype(view.frame[!, name])))
        column
    end
end

# The policy of the width of column `name`: `Fixed` at the width that a person
# gave it, else `default`.
function _get_column_width_policy(view::DataFrameView, name::AbstractString, default)
    width = get(view.column_widths, name, nothing)
    width === nothing ? default : Fixed(width)
end

print_document(p::DataFrameViewToWidget, view::DataFrameView) =
    print_document(p, nothing, view, nothing)

# The header of each kept row, its row number in the frame, as a list that moves
# in step with the rows, and the corner of the filter row. A frame with no rows
# has neither. `p` carries the style of the data frame theme.
function _make_row_numbers(p, view::DataFrameView)
    headers = Cell(@computation (kept = view.kept_rows;
                                 isempty(kept) ? CellVector() :
                                     make_index_list(length(kept), view.anchor,
                                                      k -> WidgetLabel(string(kept[k])))))
    corner = Cell(@computation nrow(view.frame) == 0 ? nothing : _make_query_corner(p, view))
    (headers, corner)
end

# The table of a frame whose columns are a list: the headers, the data of the
# columns and the cells of every row are lists with their heads at
# `column_anchor`.
function _make_column_list_table(p::DataFrameViewToWidget, view::DataFrameView, bar::WidgetScrollBar)
    # The headers are built when a walk reaches them, so the list reads the sort
    # keys itself, and a new sort builds the list again.
    headers = Cell(@computation (view.query.sort_keys; columns = _get_shown_columns(view);
        make_index_list(length(columns), view.column_anchor, c -> _make_filter_header(p, view, columns[c]))))
    rows = Cell(@computation _make_row_list(view, _get_shown_columns(view), view.kept_rows, view.anchor,
                                            view.column_anchor))
    # The width that a person gave a column, else none, which leaves the
    # column at the width of the list and at least as wide as its header.
    column_of = _make_column_documents(view, nothing)
    columns = Cell(@computation (names = _get_shown_columns(view);
        make_index_list(length(names), view.column_anchor, c -> column_of(names[c]))))
    row_headers, corner = _make_row_numbers(p, view)
    # Positional, as in `_make_view_table` above.
    table = WidgetTable(Cell(Point2D(0, 0)), headers, row_headers, corner, rows,
                        Cell(:row_major), Cell(WidgetTableRows(nothing)), columns, Cell(1),
                        Cell(Fixed(p.list_column_width)), Cell(Fixed(p.row_height)), Cell(:clip),
                        Cell(true), Cell(nothing), Cell(nothing), Cell(nothing),
                        Cell(nothing), getfield(view, :scroll_position),
                        getfield(view, :top_row), Cell(nothing), Cell(bar), Cell(:auto),
                        Cell(@computation _get_table_open_cells(view, true)), Cell(nothing),
                        Cell(@computation _get_table_selection(view, true)))
    set_cell_computation!(getfield(table, :mouse_target), () -> _get_table_mouse_target(view))
    table
end

# The selection of the table that shows the selection of `view`: the column,
# the row or the cell of the frame that it names, where the table shows it; the
# field of a filter or of the pattern, with its caret; and the whole table for
# the whole view.
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
    (selection isa ConcreteReference && selection.head isa FieldReferenceStep) || return nothing
    _find_table_part_path(view, selection, column_list)
end

# The open cells of the table, `(row, column, reason)` in the numbers of the
# paths of the table, for the entries of `view` whose cells it shows.
function _get_table_open_cells(view::DataFrameView, column_list::Bool)
    cells = Any[]
    frame_names = names(view.frame)
    for edit in view.edits
        k = _find_table_row(view, edit.row)
        c = findfirst(==(edit.column), frame_names)
        j = c === nothing ? nothing : _find_table_column(view, c, column_list)
        (k === nothing || j === nothing) && continue
        push!(cells, (row = k, column = j, reason = edit.reason))
    end
    cells
end

# The path in the table of the header of column `name`, followed by `tail`;
# `nothing` when the view does not show the column.
function _make_header_reference(view::DataFrameView, name::String, tail, column_list::Bool)
    c = findfirst(==(name), _get_shown_columns(view))
    c === nothing && return nothing
    column_list && (c -= view.column_anchor - 1)
    _make_element_reference("column_headers", c, tail)
end

# The path in the table of `path`, a path of the view to a column, a row or a
# cell of the frame, with the rest of the path as it is: `columns[c]…` is the
# column that the table shows, `rows[r]…` the row among the kept rows counted
# from the head of the list, and `cells[r][c]…` of the table the cell where they
# meet.
# `nothing` for a column that the view hides, and for a row that a filter drops
# or that is too far from the head for the table to show it.
function _find_table_part_path(view::DataFrameView, path::ConcreteReference, column_list::Bool)
    tail = path.tail
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep) || return nothing
    if path.head.name == "columns"
        j = _find_table_column(view, tail.head.stop, column_list)
        return j === nothing ? nothing : _make_element_reference("columns", j, tail.tail)
    end
    path.head.name == "rows" || return nothing
    k = _find_table_row(view, tail.head.stop)
    k === nothing && return nothing
    rest = tail.tail
    (rest isa ConcreteReference && rest.head isa RangeReferenceStep) ||
        return _make_element_reference("rows", k, rest)
    j = _find_table_column(view, rest.head.stop, column_list)
    j === nothing && return nothing
    _make_element_reference("cells", k, ConcreteReference(RangeReferenceStep(j - 1, j), rest.tail))
end

# The place in the table of column `c` of the frame, counted from the head column
# when the columns are a list, or `nothing` when the view hides it.
function _find_table_column(view::DataFrameView, c::Int, column_list::Bool)
    frame_names = names(view.frame)
    1 <= c <= length(frame_names) || return nothing
    j = findfirst(==(frame_names[c]), _get_shown_columns(view))
    j === nothing && return nothing
    column_list ? j - (view.column_anchor - 1) : j
end

# How far from the head of the list of rows the view looks for a row of the frame.
# The table shows the rows near its head, because it moves the head to the row at
# the top as it scrolls, and a sort can put a row anywhere among the kept rows.
const _ROW_SEARCH_REACH = 10_000

# The place of the kept row at the head of the list of rows.
_get_head_place(view::DataFrameView) = clamp(view.anchor, 1, max(1, length(view.kept_rows)))

# The place in the table of row `r` of the frame, counted from the head of the
# list, or `nothing` when no kept row near the head is `r`.
function _find_table_row(view::DataFrameView, r::Int)
    kept = view.kept_rows
    isempty(kept) && return nothing
    head = _get_head_place(view)
    for p in max(1, head - _ROW_SEARCH_REACH):min(length(kept), head + _ROW_SEARCH_REACH)
        kept[p] == r && return p - head + 1
    end
    nothing
end

# The row of the frame of row `k` of the table, counted from the head of the
# list, or `nothing` past the kept rows.
function _find_frame_row(view::DataFrameView, k::Int)
    p = _get_head_place(view) + k - 1
    1 <= p <= length(view.kept_rows) ? view.kept_rows[p] : nothing
end

"""
    make_data_frame_view_projection(; measure, appearance = Appearance()) -> Projection

The row of the natural renderer for a `DataFrameView`: `DataFrameViewToWidget`,
then the printer of a grid, which prints the table, and the table its scroll
bar, through the recursion. A row of the natural renderer ends in graphics, because a type
dispatch does not print an output again. The table draws with the widget theme
of `appearance`. The height of a row is a line of the font of that theme, and
its step adds the padding of a cell of the theme and a rule, and the scroll bar
of the table takes the thickness of that theme; all three read the scaled
theme at each print, with no edge, as a style field of a widget does. The filter
row and the expression bar draw with the scaled `DataFrameTheme` of `appearance`.
"""
function make_data_frame_view_projection(; measure::TextMeasure,
                                         appearance::Appearance = Appearance())
    theme = get_scaled_theme!(appearance, WidgetTheme)
    frame_theme = get_scaled_theme!(appearance, DataFrameTheme)
    widgets = WidgetToGraphics(; measure, theme, graphics_theme = get_scaled_theme!(appearance, GraphicsTheme))
    table = last(only(p for p in widgets.dispatch if first(p) === WidgetTable))
    grid = last(only(p for p in LayoutToGraphics().dispatch if first(p) === GridLayout))
    row_height = UntrackedCell{Int}(@computation ceil(Int, compute_line_box(measure, "M", theme.font).height))
    row_step = UntrackedCell{Int}(@computation row_height[] + 2 * Int(table.cell_padding.top[]) + 1)
    get_style(name) = get_data_frame_style(frame_theme, name)
    view = DataFrameViewToWidget(; row_height, row_step,
                                 query_field_width = get_style(:query_field_width),
                                 expression_field_width = get_style(:expression_field_width),
                                 find_field_width = get_style(:find_field_width),
                                 filter_gap = get_style(:filter_gap), expression_gap = get_style(:expression_gap),
                                 invalid_query = get_style(:invalid_query),
                                 unsorted_glyph = get_style(:unsorted_glyph),
                                 list_column_width = get_style(:list_column_width))
    ChainingProjection(view, grid)
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

# An insert, a delete or a move of a row or a column of the view, which comes
# with a route into the view from the menu of a row or of a column, becomes the
# step that it makes in the view: the selection, the entries and the place of
# the view with it.
#
# A double click that selects a row whole, on its header, opens the row as a page
# too, as a double click on a file of the Files pane opens the file: the navigator
# around the view shows it, or a new tab does when there is none.
function read_intent(p::DataFrameViewToWidget, recursion, change::Intent, iomap::DataFrameViewToWidgetIoMap)
    operation = change.operation
    step = (change.route === nothing || !(operation isa _DataFrameShapeOperation) ||
            operation.view !== iomap.input) ? nothing : _make_shape_step(operation)
    step === nothing || return Intent(change.gesture, step, change.description, change.domain)
    answer = invoke(read_intent, Tuple{Projection,Any,Intent,Any}, p, recursion, change, iomap)
    # The view keeps the drag of the thumb of its bar, so it keeps the press in
    # its own frame, the frame of the parts of the drag that come to it.
    change.gesture isa MouseDown &&
        (answer = Intent(answer.gesture, make_owned_scroll_bar_drag(answer.operation, iomap.bar, change.gesture),
                         answer.description, answer.domain))
    _is_double_click(change.gesture) && _is_whole_row_selection(answer.operation) || return answer
    Intent(answer.gesture, CompoundOperation(Any[answer.operation,
                                                 OpenPageOperation(nothing, answer.operation.path)]),
           answer.description, answer.domain)
end

_is_double_click(gesture) =
    gesture isa MouseClick && gesture.button === :left && gesture.count == 2 &&
    gesture.modifiers == ModifierKeys()

function _is_whole_row_selection(operation)
    operation isa ReplaceSelectionOperation || return false
    steps = get_reference_steps(operation.path)
    length(steps) == 2 && steps[1] == FieldReferenceStep("rows") && steps[2] isa RangeReferenceStep
end

const _DataFrameShapeOperation =
    Union{InsertDataFrameRowOperation,DeleteDataFrameRowOperation,_DataFrameColumnOperation}

_make_shape_step(operation::InsertDataFrameRowOperation) = _make_row_insert_step(operation)
_make_shape_step(operation::DeleteDataFrameRowOperation) = _make_row_delete_step(operation)
_make_shape_step(operation::_DataFrameColumnOperation) = _make_column_step(operation)

# A key that the table does not take: the gestures of the view answer it.
read_intent(::DataFrameViewToWidget, iomap::DataFrameViewToWidgetIoMap, event::KeyDown) =
    read_gesture(iomap.input, event)

# A selection in the table selects in the view: a header selects its column, a
# field of the filter row or of the expression bar its text, a row, a column and
# a cell their place in the frame, and the corner or the whole table the view. A
# caret in a cell that is not open opens it first: the selection goes into the
# document of its new entry, so its path is typed when the entry is there.
function read_intent(::DataFrameViewToWidget, iomap::DataFrameViewToWidgetIoMap,
                     operation::ReplaceSelectionOperation)
    expression = _find_expression_path(operation.path)
    expression === nothing ||
        return ReplaceSelectionOperation(annotate_reference_types(iomap.input, expression))
    path = _find_table_path(operation.path)
    path === nothing && return nothing
    target = _find_view_path(iomap, path)
    target === nothing && return nothing
    view = iomap.input
    target = _find_whole_read_only_cell(view, target)
    open = _make_open_cell_operation(view, target)
    selection = ReplaceSelectionOperation(open === nothing && _find_cell_tail(target) === nothing ?
                                          annotate_reference_types(view, target) : target)
    # A move out of an open cell commits it; a value that does not convert keeps
    # it open with its mark, and the selection moves on. The commit comes after
    # the selection, so the undo opens the cell again before it selects in it.
    # The row of the new selection keeps its place on the screen.
    left = _find_selected_open_cell(view)
    commit = (left === nothing || _find_frame_cell(view, target) == left) ? nothing :
             _make_cell_commit(view, left[1], left[2])
    (open === nothing && commit === nothing) && return selection
    operations = open === nothing ? Any[selection] : Any[open, selection]
    commit === nothing && return _make_cell_step(operations, false)
    append!(operations, commit.members)
    row = _find_path_row(target)
    (commit.edits && row !== nothing) &&
        _push_anchor_write!(operations, view, row, _compute_kept_rows_after_write(view, left[1], left[2], commit.value))
    _make_cell_step(operations, commit.edits)
end

# The row of the frame that `path`, a path of the view, goes into, `rows[r]…`, or
# `nothing`.
function _find_path_row(path)
    (path isa ConcreteReference && path.head == FieldReferenceStep("rows")) || return nothing
    tail = path.tail
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep) ? tail.head.stop : nothing
end

# The row of the frame, the column of the frame and the rest of `path`, a path of
# the view that goes on into a cell, `rows[r][c]…` with a rest that is not empty;
# `nothing` for any other path.
function _find_cell_tail(path)
    (path isa ConcreteReference && path.head == FieldReferenceStep("rows")) || return nothing
    tail = path.tail
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep) || return nothing
    rest = tail.tail
    (rest isa ConcreteReference && rest.head isa RangeReferenceStep && !(rest.tail isa EmptyReference)) ||
        return nothing
    (tail.head.stop, rest.head.stop, rest.tail)
end

# The opening of the cell that `path`, a path of the view, goes on into: a new
# entry, whose document is a new primitive document of the value, when the cell
# is not open, takes keys and is in a column that takes a write; `nothing`
# otherwise. It is view state.
function _make_open_cell_operation(view::DataFrameView, path)
    found = _find_cell_tail(path)
    found === nothing && return nothing
    r, c, _ = found
    frame = view.frame
    (1 <= r <= nrow(frame) && 1 <= c <= ncol(frame)) || return nothing
    _is_writable_column(frame[!, c]) || return nothing
    name = names(frame)[c]
    _find_cell_edit(view, r, name) === nothing || return nothing
    document = make_data_frame_cell(frame[r, c], eltype(frame[!, c]))
    document isa PrimitiveDocument || return nothing
    ReplaceViewStateOperation(OpenDataFrameCellOperation(view, DataFrameCellEdit(r, name, document, nothing)))
end

# `path`, a path of the view, or the whole cell when it goes into a cell of a
# column that takes no write: such a cell shows its value as any other does, and
# takes no caret and no key.
function _find_whole_read_only_cell(view::DataFrameView, path)
    found = _find_cell_tail(path)
    found === nothing && return path
    r, c, _ = found
    frame = view.frame
    (1 <= c <= ncol(frame) && !_is_writable_column(frame[!, c])) || return path
    _make_element_reference("rows", r, ConcreteReference(RangeReferenceStep(c - 1, c), EmptyReference()))
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

# The path inside the table from a path in the grid of the view, whose second
# child is the table; `nothing` for a path that does not go into the table.
function _find_table_path(path)
    path = strip_reference_types(path)
    (path isa ConcreteReference && path.head isa FieldReferenceStep && path.head.name == "children") ||
        return nothing
    tail = path.tail
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep && tail.head.start == 1 &&
     tail.head.stop == 2) || return nothing
    tail.tail
end

# The path in the view of `path`, a path in the table: the text of the query and
# its range for a field of the filter row, the view for the table and for the
# rest of its corner, `columns[c]` of the frame for a column and for its header,
# `rows[r]` for a row and for its header, which hold no state of their own in the
# view, `rows[r][c]` for a cell with the rest of the path in it, and `nothing`
# for any other place.
function _find_view_path(iomap::DataFrameViewToWidgetIoMap, path)
    path isa EmptyReference && return EmptyReference()
    (path isa ConcreteReference && path.head isa FieldReferenceStep) || return nothing
    view = iomap.input
    text = _find_query_text_path(view, path, c -> _find_shown_column(iomap, c))
    text === nothing || return text
    path.head.name == "corner" && return EmptyReference()
    tail = path.tail
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep) || return nothing
    name = path.head.name
    if name in ("columns", "column_headers")
        tail.tail isa EmptyReference || return nothing
        return _find_frame_column_path(iomap, tail.head.stop, EmptyReference())
    end
    name in ("rows", "cells", "row_headers") || return nothing
    r = _find_frame_row(view, tail.head.stop)
    r === nothing && return nothing
    rest = tail.tail
    rest isa EmptyReference && name != "cells" && return _make_element_reference("rows", r, rest)
    name == "cells" || return nothing
    (rest isa ConcreteReference && rest.head isa RangeReferenceStep) || return nothing
    column = _find_frame_column_path(iomap, rest.head.stop, rest.tail)
    column === nothing && return nothing
    _make_element_reference("rows", r, column.tail)
end

# `columns[c]` of the view, followed by `tail`, for column `j` of the table,
# counted from the head column when the columns are a list; `nothing` past them.
function _find_frame_column_path(iomap::DataFrameViewToWidgetIoMap, j::Int, tail)
    name = _find_shown_column(iomap, j)
    name === nothing && return nothing
    path = _make_column_reference(iomap.input, name)
    path === nothing ? nothing : ConcreteReference(path.head, ConcreteReference(path.tail.head, tail))
end

# The name of the column of header `c` of the table, counted from the head
# column when the columns are a list, or `nothing`.
function _find_shown_column(iomap::DataFrameViewToWidgetIoMap, c::Int)
    view = iomap.input
    iomap.table.column_headers isa ListNode && (c += view.column_anchor - 1)
    columns = _get_shown_columns(view)
    1 <= c <= length(columns) ? columns[c] : nothing
end

# The width that the drag of the edge of a header gives a column of the table is
# the width of that column in the view, by its name, as view state: a filter, a
# sort and a scroll keep it. A width operation of another table goes on.
function _convert_column_width(iomap::DataFrameViewToWidgetIoMap, operation::SetTableColumnWidthOperation)
    operation.table === iomap.table || return operation
    name = _find_shown_column(iomap, operation.column)
    name === nothing && return nothing
    view = iomap.input
    get(view.column_widths, name, nothing) == operation.width && return nothing
    widths = copy(view.column_widths)
    widths[name] = operation.width
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(view, "column_widths", widths))
end

# An edit of a field of the filter row or of the expression bar is an edit of
# the text of the query, and the view shows the result of the new query from
# its start.
function read_intent(::DataFrameViewToWidget, iomap::DataFrameViewToWidgetIoMap,
                     operation::ReplaceStringRangeOperation)
    cell = _convert_cell_operation(iomap, operation)
    cell === nothing || return cell
    target = _find_expression_path(operation.reference)
    if target === nothing
        path = _find_table_path(operation.reference)
        path === nothing && return nothing
        target = _find_view_path(iomap, path)
    end
    view = iomap.input
    # An edit of the find text is an edit of its field only.
    target isa ConcreteReference && target.head == FieldReferenceStep("find_text") &&
        return ReplaceStringRangeOperation(annotate_reference_types(view, target), operation.replacement)
    (target isa ConcreteReference && target.head == FieldReferenceStep("query")) || return nothing
    _make_query_edit_operation(view, ReplaceStringRangeOperation(annotate_reference_types(view, target),
                                                                 operation.replacement))
end

# A scroll of the table writes the cell that the view shares with it, and
# every other operation of the widgets carries its own subject: both pass on.
# A table that moves the head of its rows far from the anchor writes its
# `cells`; the view moves its anchor instead, and builds a new list from it. A
# table that moves its head column writes its `column_headers`, its `columns`
# and its `cells`; the view moves its column anchor instead, and builds the
# three lists again from it. A write of the value of the scroll bar
# is a jump to the row at that value, also in the compound of a move with the
# button held, which sets the mouse target too.
read_intent(::DataFrameViewToWidget, iomap::DataFrameViewToWidgetIoMap, operation::Operation) =
    _convert_table_writes(iomap, operation)

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

# One write of a compound: the value of the scroll bar to a jump, `cells` to an
# anchor, `column_headers` to a column anchor, and, when the compound moves the
# columns, no write of `cells` or of `columns`, which the view builds again from
# its anchors. The width of a
# column goes to the view. The table starts the drag of the edge of a column
# from the view, which the table is a part of: the parts of the drag come back
# to the view by its path, and the view gives them to the table. The drag of the
# thumb of the bar of the view comes back to the view the same way.
function _convert_table_write(iomap::DataFrameViewToWidgetIoMap, operation, columns::Bool)
    bar = _find_written_field(iomap.bar, operation)
    if bar !== nothing && bar[1] == "value"
        count = length(iomap.input.kept_rows)
        return jump_to_row(iomap.input, compute_scroll_bar_top_row(bar[2], count, Int(iomap.visible)))
    end
    cell = _convert_cell_operation(iomap, operation)
    cell === nothing || return cell
    operation isa DropTableCellOperation && operation.table === iomap.table &&
        return _convert_cell_drop(iomap, operation)
    operation isa CommitTableCellOperation && operation.table === iomap.table &&
        return _convert_cell_commit(iomap, operation)
    operation isa EditTableCellOperation && operation.table === iomap.table &&
        return _convert_cell_edit(iomap, operation)
    operation isa StartDragOperation && _find_table_path(get_operation_path(operation)) isa EmptyReference &&
        return StartDragOperation(annotate_reference_types(iomap.input, EmptyReference()), operation.dragged)
    width = operation isa ReplaceViewStateOperation ? get_wrapped_operation(operation) : operation
    width isa SetTableColumnWidthOperation && return _convert_column_width(iomap, width)
    written = _find_written_field(iomap.table, operation)
    written === nothing && return operation
    field, value = written
    view = iomap.input
    if field == "column_headers"
        c = find_list_index(iomap.table.column_headers, value)
        c === nothing && return nothing
        return ReplaceViewStateOperation(ReplaceReferencedValueOperation(
            view, "column_anchor", view.column_anchor + c - 1))
    end
    columns && field in ("cells", "columns") && return nothing
    # The row headers move in step with the rows, and the view builds both
    # again from its anchor.
    field == "row_headers" && return nothing
    field == "cells" || return operation
    k = find_list_index(iomap.table.cells, value)
    k === nothing && return nothing
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(view, "anchor", view.anchor + k - 1))
end

# An operation of the document in an open cell, in the paths of the view: a key
# that edits its text, the write of the whole cell that replaces its document,
# such as a number that becomes a type-in, and the selection that goes with it.
# The paths go from `cells[k][j]…` of the table to `rows[r][c]…` of the view,
# which reach the document of the entry. `nothing` for any other operation.
function _convert_cell_operation(iomap::DataFrameViewToWidgetIoMap, operation)
    if operation isa ReplaceRangeOperation
        target = _find_cell_view_path(iomap, operation_reference(operation))
        return target === nothing ? nothing : retarget_operation(operation, target)
    elseif operation isa ReplaceReferencedValueOperation && operation.document === nothing
        # A key of a whole cell that is not open, such as Space on a Bool, opens
        # the cell first, so the write goes into the document of its entry.
        target = _find_cell_view_path(iomap, operation.reference)
        target === nothing && return nothing
        _find_whole_read_only_cell(iomap.input, target) === target || return nothing
        write = ReplaceReferencedValueOperation(nothing, target, operation.value)
        open = _make_open_cell_operation(iomap.input, target)
        return open === nothing ? write : _make_cell_step(Any[open, write], true)
    elseif operation isa ReplaceSelectionOperation
        target = _find_cell_view_path(iomap, operation.path)
        return target === nothing ? nothing : ReplaceSelectionOperation(target)
    end
    nothing
end

# Escape in an open cell drops its entry, so the cell shows its value again, and
# selects the whole cell.
function _convert_cell_drop(iomap::DataFrameViewToWidgetIoMap, operation::DropTableCellOperation)
    found = _find_frame_cell_of_table(iomap, operation.row, operation.column)
    found === nothing ? nothing : _make_cell_drop_operation(iomap.input, found[1], found[2])
end

# Enter, Tab and Shift+Tab in an open cell commit it, and select the whole cell
# that the key goes to.
function _convert_cell_commit(iomap::DataFrameViewToWidgetIoMap, operation::CommitTableCellOperation)
    found = _find_frame_cell_of_table(iomap, operation.row, operation.column)
    found === nothing ? nothing : _make_cell_commit_operation(iomap.input, found[1], found[2], operation.key)
end

# F2 and a typed character on a whole cell open it.
function _convert_cell_edit(iomap::DataFrameViewToWidgetIoMap, operation::EditTableCellOperation)
    found = _find_frame_cell_of_table(iomap, operation.row, operation.column)
    found === nothing ? nothing : _make_cell_edit_operation(iomap.input, found[1], found[2], operation.text)
end

# The row of the frame and the name of the column of the cell in row `row` and
# column `column` of the table, in the numbers of its paths, or `nothing`.
function _find_frame_cell_of_table(iomap::DataFrameViewToWidgetIoMap, row::Int, column::Int)
    path = _find_view_path(iomap, ConcreteReference(FieldReferenceStep("cells"),
        ConcreteReference(RangeReferenceStep(row - 1, row),
                          ConcreteReference(RangeReferenceStep(column - 1, column), EmptyReference()))))
    path === nothing ? nothing : _find_frame_cell(iomap.input, path)
end

# The row of the frame and the name of the column of `path`, the path of the view
# of a whole cell, `rows[r][c]`, or `nothing`.
function _find_frame_cell(view::DataFrameView, path)
    (path isa ConcreteReference && path.head == FieldReferenceStep("rows")) || return nothing
    tail = path.tail
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep) || return nothing
    rest = tail.tail
    (rest isa ConcreteReference && rest.head isa RangeReferenceStep) || return nothing
    c = rest.head.stop
    frame_names = names(view.frame)
    1 <= c <= length(frame_names) ? (tail.head.stop, frame_names[c]) : nothing
end

# The path of the view of `path`, a path of the output of the view, when it
# reaches a cell of the table, `cells[k][j]` with or without a rest; `nothing`
# for any other path.
function _find_cell_view_path(iomap::DataFrameViewToWidgetIoMap, path)
    path isa Reference || return nothing
    table_path = _find_table_path(path)
    (table_path isa ConcreteReference && table_path.head == FieldReferenceStep("cells")) || return nothing
    tail = table_path.tail
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep &&
     tail.tail isa ConcreteReference && tail.tail.head isa RangeReferenceStep) || return nothing
    _find_view_path(iomap, table_path)
end

# The parts of the drag of the edge of a column come to the view by its path, and
# the view gives them to its table, which keeps the drag. The table is the first
# column of the grid of the view, at its left edge, so a point has the same x in
# the view and in the table, which is all that the width reads. The parts of the
# drag of the thumb of the bar come the same way, and the bar reads them in the
# frame of the view, where the view kept the press.
function read_intent(::DataFrameViewToWidget, iomap::DataFrameViewToWidgetIoMap,
                     event::Union{DragMove,DragEnd,DragCancel})
    thumb = read_scroll_bar_drag(iomap.bar, event)
    _convert_table_writes(iomap, thumb === nothing ? read_table_column_drag(iomap.table, event) : thumb)
end

read_intent(::DataFrameViewToWidget, ::DataFrameViewToWidgetIoMap, event) = nothing
