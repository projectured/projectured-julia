# Fragment of `DataFramesModule`.
#
# The view of one data frame: a document that holds the native frame and the
# state of the view. The frame is not copied. The rows of the view are a list
# anchored at any row of the frame, and a node of the list is built from its
# index alone, so a jump to any row costs the rows that the pane shows.

"""
    DataFrameView(frame; anchor = 1, column_anchor = 1)

The view of `frame`, an `AbstractDataFrame`. `anchor` is the row of the frame at
the head of the list of rows, and `scroll_position` is the offset of the table
from that row, in pixels. A frame with many columns draws its columns as a list
too, and `column_anchor` is the column of the frame at the head of that list.
They are the state of the view: a jump writes them together, and a history does
not record them.
"""
@document struct DataFrameView <: Document
    frame::Any
    anchor::Int
    column_anchor::Int
    scroll_position::Point2D
end

DataFrameView(frame::AbstractDataFrame; anchor::Integer = 1, column_anchor::Integer = 1) =
    DataFrameView(Cell(frame), Cell(Int(anchor)), Cell(Int(column_anchor)), Cell(Point2D(0, 0)),
                  Cell(nothing))

"""
    jump_to_row(view::DataFrameView, row::Integer) -> Operation or nothing

The operation that shows row `row` of the frame at the top of the pane: a new
anchor, and the pane at the anchor. The pane stops at the last row, so a jump
near the end shows the last row at the bottom. A row out of range is the first
or the last row. `nothing` for a frame with no rows.
"""
function jump_to_row(view::DataFrameView, row::Integer)
    count = nrow(view.frame)
    count == 0 && return nothing
    x = Int(view.scroll_position.x[])
    CompoundOperation(Any[
        ReplaceViewStateOperation(ReplaceReferencedValueOperation(view, "anchor", clamp(Int(row), 1, count))),
        ReplaceViewStateOperation(ReplaceReferencedValueOperation(view, "scroll_position", Point2D(x, 0)))])
end

@gestures DataFrameView begin
    KeyDown(:home; ctrl) => "Jump to the first row" => jump_to_row(doc, 1)
    KeyDown(:end; ctrl) => "Jump to the last row" => jump_to_row(doc, nrow(doc.frame))
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

# The list of rows of `frame` with its head at row `anchor`, or an empty vector
# for a frame with no rows: a table draws an empty vector as no rows. A row is a
# vector of its cells, or, when `column_anchor` is given, a list of them with
# its head at that column.
function _make_row_list(frame::AbstractDataFrame, anchor::Int, column_anchor = nothing)
    nrow(frame) == 0 && return CellVector()
    row_of(i) = column_anchor === nothing ?
        make_widget_table_row(Any[make_data_frame_cell(frame[i, c]) for c in 1:ncol(frame)]) :
        _make_index_list(ncol(frame), column_anchor, c -> make_data_frame_cell(frame[i, c]))
    _make_index_list(nrow(frame), anchor, row_of)
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
