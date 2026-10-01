# Fragment of `DataFramesModule`.
#
# The view of one data frame: a document that holds the native frame and the
# state of the view. The frame is not copied. The rows of the view are a list
# anchored at any row of the frame, and a node of the list is built from its
# index alone, so a jump to any row costs the rows that the table shows.

"""
    DataFrameView(frame; anchor = 1, column_anchor = 1)

The view of `frame`, an `AbstractDataFrame`. `query`, a [`DataFrameQuery`](@ref),
says what the view keeps of the frame: the columns that it shows, and the rows
that pass its filters. `expression_result` holds the rows that the expression of
the query passes, or the reason why it does not run, and `kept_rows` the rows
that pass every filter, by their number in the frame and in its order; both
follow the frame and the query. A column of the view
is named by its name, with a `DataFrameColumnReferenceStep`.

`anchor` is the place, among the kept rows, of the row at the head of the list
of rows, and `scroll_position` is the offset of the table from that row, in
pixels. A frame with many columns draws its columns as a list too, and
`column_anchor` is the place, among the shown columns, of the column at the head
of that list. `top_row` is the row at the top of the table, counted from the
anchor, which the table writes as it scrolls; the scroll bar shows it. They are
the state of the view: a jump writes them together, and a history does not
record them.

A frame that a program changes in place stays the same object, so the view
does not see the change until [`refresh_document!`](@ref) of it, or the key F5,
reads the frame again: `frame_snapshot` is what the last read saw, or
`nothing` before the first, and `frame_version` moves when a read finds a
change; the first read moves it in any case, so a new view reads no cell for a
refresh. Every computation that reads
the data of the frame reads `frame_version` too.
"""
@document struct DataFrameView <: Document
    frame::Any
    query::DataFrameQuery
    expression_result::Any
    kept_rows::Vector{Int}
    anchor::Int
    column_anchor::Int
    scroll_position::Point2D
    top_row::Int
    frame_version::Int
    frame_snapshot::Any
end

function DataFrameView(frame::AbstractDataFrame; anchor::Integer = 1, column_anchor::Integer = 1)
    view = DataFrameView(Cell(frame), Cell(_make_frame_query(frame)), Cell((nothing, nothing)), Cell(Int[]),
                         Cell(Int(anchor)), Cell(Int(column_anchor)), Cell(Point2D(0, 0)), Cell(1),
                         Cell(0), Cell(nothing), Cell(nothing))
    _set_kept_row_computations!(view)
end

# The result of the expression of `view`, computed again when the frame or the
# text of the expression changes, and the rows that pass, computed again when
# the frame, the query or that result changes. A value of a type that a package
# loaded later prints in the newest world.
function _set_kept_row_computations!(view::DataFrameView)
    set_cell_computation!(getfield(view, :expression_result),
                          () -> (view.frame_version; _evaluate_expression(view.frame, view.query.expression)))
    set_cell_computation!(getfield(view, :kept_rows),
                          () -> (view.frame_version;
                                 Base.invokelatest(_compute_kept_rows, view.frame, view.query,
                                                   first(view.expression_result))))
    view
end

# ── The duplicate ────────────────────────────────────────────────────────────
#
# The duplicate of a view is a second view of the same frame: it shares the
# frame, which it reads, and owns a copy of the query and of the place in the
# rows and the columns, so a filter, a sort or a scroll in one does not move the
# other. Its rows are computed again from its own query, and its first refresh
# reads the frame again.
has_document_duplicate(::Union{DataFrameView,DataFrameQuery,DataFrameColumnFilter,DataFrameSortKey}) = true

copy_document(policy::DuplicatePolicy, view::DataFrameView) =
    _set_kept_row_computations!(copy_document_fields(policy, view; frame = view.frame,
                                                     expression_result = (nothing, nothing),
                                                     kept_rows = Int[], frame_version = 0,
                                                     frame_snapshot = nothing))

"""
    jump_to_row(view::DataFrameView, row::Integer) -> Operation or nothing

The operation that shows the kept row at place `row` at the top of the table: a
new anchor, and the table at the anchor. The table stops at the last kept row,
so a jump near the end shows the last row at the bottom. A place out of range is
the first or the last row. `nothing` for a view that keeps no row.
"""
function jump_to_row(view::DataFrameView, row::Integer)
    count = length(view.kept_rows)
    count == 0 && return nothing
    x = Int(view.scroll_position.x[])
    CompoundOperation(Any[
        ReplaceViewStateOperation(ReplaceReferencedValueOperation(view, "anchor", clamp(Int(row), 1, count))),
        ReplaceViewStateOperation(ReplaceReferencedValueOperation(view, "scroll_position", Point2D(x, 0))),
        ReplaceViewStateOperation(ReplaceReferencedValueOperation(view, "top_row", 1))])
end

# A right click on the corner of the table opens the menu of the view
# (`compute_context_menu`), which shows the hidden columns again.
const _DATA_FRAME_VIEW_MENU =
    GestureBinding[make_context_menu_binding(compute_context_menu;
                                             description = "Show the menu of the view")]

@gestures DataFrameView begin
    KeyDown(:home; ctrl) => "Jump to the first row" => jump_to_row(doc, 1)
    KeyDown(:end; ctrl) => "Jump to the last row" => jump_to_row(doc, length(doc.kept_rows))
    KeyDown(:f5) => "Read the frame again" => RefreshDataFrameViewOperation(doc)
    splice(_DATA_FRAME_VIEW_MENU)
end

# ── The cells ────────────────────────────────────────────────────────────────

# The longest text that a cell shows. A value that prints longer is cut, and
# the cell of the table clips what is left to its column.
const _CELL_TEXT_LIMIT = 200

"""
    make_data_frame_cell(value) -> WidgetDocument

The widget that shows one value of a frame. A value prints in the compact form
that a data frame prints in the REPL, cut at 200 characters.
"""
make_data_frame_cell(::Missing) = WidgetLabel("missing")
make_data_frame_cell(value) = WidgetLabel(_get_cell_text(value))

# The loop of an editor keeps the world of its start, and a value can have a type
# of a package that was loaded later, so the print runs in the newest world.
function _get_cell_text(value)
    text = Base.invokelatest(sprint, print, value; context = (:compact => true, :limit => true))
    length(text) <= _CELL_TEXT_LIMIT ? text : first(text, _CELL_TEXT_LIMIT - 1) * "…"
end

# ── The list of rows ─────────────────────────────────────────────────────────

# The list of the `kept` rows of `frame` with its head at the place `anchor`, or
# an empty vector when it keeps no row: a table draws an empty vector as no rows.
# A row is a vector of its cells in the `columns` that the view shows, or, when
# `column_anchor` is given, a list of them with its head at that column.
function _make_row_list(frame::AbstractDataFrame, columns::Vector{String}, kept::Vector{Int},
                        anchor::Int, column_anchor = nothing)
    isempty(kept) && return CellVector()
    row_of(i) = column_anchor === nothing ?
        make_widget_table_row(Any[make_data_frame_cell(frame[i, name]) for name in columns]) :
        _make_index_list(length(columns), column_anchor, c -> make_data_frame_cell(frame[i, columns[c]]))
    _make_index_list(length(kept), anchor, k -> row_of(kept[k]))
end

# The list of the values of the indices `1:count`, with its head at the index
# `at`, clamped to the range: `value_of(i)` makes the value of index `i` when a
# walk first reaches it.
_make_index_list(count::Int, at::Int, value_of) =
    _make_index_node(count, clamp(at, 1, count), value_of, nothing, nothing)

# The node of index `i`. A neighbour that is given is linked as a value; the
# other link builds its neighbour when it is first read, and the neighbour links
# back to this node, so a walk down and back up meets the same nodes. The first
# index has no `prev` and the last has no `next`, so a pane stops at both.
function _make_index_node(count::Int, i::Int, value_of, before, after)
    node = ListNode(value_of(i))
    if after === nothing
        set_cell_computation!(getfield(node, :next),
            () -> i < count ? _make_index_node(count, i + 1, value_of, node, nothing) : nothing)
    else
        set_cell_value!(getfield(node, :next), after)
    end
    if before === nothing
        set_cell_computation!(getfield(node, :prev),
            () -> i > 1 ? _make_index_node(count, i - 1, value_of, nothing, node) : nothing)
    else
        set_cell_value!(getfield(node, :prev), before)
    end
    node
end
