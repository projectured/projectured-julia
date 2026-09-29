# Fragment of `DataFramesModule`.
#
# A `DataFrameView` drawn as a table that scrolls its own parts. The table reads
# the rows of the view, a list anchored at `anchor`, so it builds only the rows
# it shows. The table shares the `scroll_position` cell of the view, so a scroll
# of the table and a jump of the view write the same state.

"""
    DataFrameViewToWidget()

Projects a `DataFrameView` to a `WidgetTable`, which scrolls its own parts.
The header of a column shows its name and its element type, as a data frame
prints them in the REPL: `price :: Float64`, and `discount :: Float64?` for a
column that allows `missing`. Every column takes an equal share of the width
and is at least as wide as its header. A number aligns right.

The reader gives the view a key that the table does not take, so the gestures
of `DataFrameView` answer Ctrl+Home and Ctrl+End. A scroll of the table passes
on. The view has no selection yet, so a selection in the table goes nowhere.
"""
struct DataFrameViewToWidget <: Projection end

@iomap struct DataFrameViewToWidgetIoMap
    projection::Any
    input::Any
    output::Any
end

# A weight and no minimum: the table gives the column an equal share of the
# width, and the width of its header at least.
const _COLUMN_POLICY = SizePolicy(nothing, nothing, nothing, 1.0)

function print_document(p::DataFrameViewToWidget, recursion, view::DataFrameView, ctx)
    headers = CellVector(@computation Any[WidgetLabel(_get_header_text(name, eltype(column)))
                                          for (name, column) in pairs(eachcol(view.frame))])
    align = Cell(@computation Symbol[_get_column_align(eltype(column))
                                     for column in eachcol(view.frame)])
    rows = Cell(@computation _make_row_list(view.frame, view.anchor))
    # Positional, so every declared field is named here in order: position,
    # column_headers, row_headers, rows, column_count, border_width,
    # column_policy, row_policy, column_policies, row_policies, cell_policy,
    # column_cell_policies, column_align, visible, margin, border, padding,
    # style, hovered, scroll_position, top_row, tooltip. The table scrolls its
    # own parts, and its offset is the cell of the view.
    table = WidgetTable(Cell(Point2D(0, 0)), headers, CellVector(), rows,
                        Cell(@computation ncol(view.frame)), Cell(1),
                        Cell(_COLUMN_POLICY), Cell(Content), Cell(Any[]), Cell(Any[]),
                        Cell(:clip), Cell(Symbol[]), align,
                        Cell(true), Cell(nothing), Cell(nothing), Cell(nothing),
                        Cell(nothing), Cell(nothing), getfield(view, :scroll_position),
                        Cell(1), Cell(nothing))
    DataFrameViewToWidgetIoMap(p, view, table)
end

print_document(p::DataFrameViewToWidget, view::DataFrameView) =
    print_document(p, nothing, view, nothing)

"""
    make_data_frame_view_projection(; measure, font) -> Projection

The row of the natural renderer for a `DataFrameView`: `DataFrameViewToWidget`,
then the printer of a table, which prints its parts through the recursion. A
row of the natural renderer ends in graphics, because a type dispatch does not
print an output again.
"""
function make_data_frame_view_projection(; measure::TextMeasure,
                                         font = font_ubuntu_monospace_regular_20)
    widgets = WidgetToGraphics(font; measure)
    table = last(only(p for p in widgets.dispatch if first(p) === WidgetTable))
    ChainingProjection(DataFrameViewToWidget(), table)
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

# The view has no selection yet, so a selection in the table goes nowhere.
read_intent(::DataFrameViewToWidget, ::DataFrameViewToWidgetIoMap, ::ReplaceSelectionOperation) =
    nothing

# A scroll of the table writes the cell that the view shares with it, and
# every other operation of the widgets carries its own subject: both pass on.
# A table that moves the head of its rows far from the anchor writes its
# `rows`; the view moves its anchor instead, and builds a new list from it.
read_intent(::DataFrameViewToWidget, iomap::DataFrameViewToWidgetIoMap, operation::Operation) =
    _convert_rows_write(iomap, operation)

# `operation` with a write of the rows of the table turned into a write of the
# anchor of the view.
function _convert_rows_write(iomap::DataFrameViewToWidgetIoMap, operation)
    operation isa CompoundOperation &&
        return CompoundOperation(Any[_convert_rows_write(iomap, o) for o in operation.operations])
    write = operation isa ReplaceViewStateOperation ? get_wrapped_operation(operation) : operation
    (write isa ReplaceReferencedValueOperation && write.document === iomap.output &&
     write.reference isa ConcreteReference && write.reference.head isa FieldReferenceStep &&
     write.reference.head.name == "rows") || return operation
    k = _find_row_index(iomap.output.rows, write.value)
    k === nothing && return operation
    view = iomap.input
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
