# Fragment of `DataFramesModule` — one row of a data frame as a page: the name and
# the value of each column, in a form that scrolls. A navigator shows it when a
# person opens a row of the table.
#
#     children[1]                              the scroll pane
#     children[1].content.children[2c - 1]     the name of column c
#     children[1].content.children[2c]         the value of column c
#
# The form shows the values and takes no edit. It reads `frame_version`, so it
# follows a write of the frame, and it shows the columns that the frame has now.

"""
    DataFrameViewRowToWidget(; column_gap, row_gap)

The page of one row of a data frame: the name and the value of each column, in a
form that scrolls. A value shows as a cell of the table shows it. `column_gap` is
the space between the names and the values, and `row_gap` the space between two
columns of the frame.

A path `[c]` of the row, the cell of column `c`, maps to the value of the column.
A press on a name or a value selects that cell.
"""
@projection UntrackedCell struct DataFrameViewRowToWidget
    column_gap::Int = get_widget_style(nothing, :form_column_gap)
    row_gap::Int = get_widget_style(nothing, :form_row_gap)
end

"""
    make_data_frame_row_projection(; widget_theme = nothing) -> DataFrameViewRowToWidget

The page of a row of a data frame, with the gaps of `widget_theme`: a
`WidgetTheme`, scaled or not, or the default values for `nothing`.
"""
make_data_frame_row_projection(; widget_theme = nothing) =
    DataFrameViewRowToWidget(; column_gap = get_widget_style(widget_theme, :form_column_gap),
                             row_gap = get_widget_style(widget_theme, :form_row_gap))

function print_document(p::DataFrameViewRowToWidget, recursion, row::DataFrameViewRow, ctx)
    SimpleIoMap(p, row, Cell(@computation _make_row_page(p, row)))
end

# The form of `row`, or a line that says that the frame has no such row now.
function _make_row_page(p::DataFrameViewRowToWidget, row::DataFrameViewRow)
    view = row.view
    view.frame_version
    frame = view.frame
    cells = Any[]
    if row.row <= nrow(frame)
        for (c, name) in enumerate(names(frame))
            push!(cells, WidgetLabel(name))
            push!(cells, WidgetLabel(_get_cell_text(frame[row.row, c])))
        end
    else
        push!(cells, WidgetLabel("The frame has no row $(row.row) now."))
    end
    form = GridLayout(cells, 2; horizontal_gap = p.column_gap, vertical_gap = p.row_gap,
                      vertical_align = :center)
    GridLayout(Any[WidgetScrollPane(form)], 1; column_policy = Fill, row_policies = Any[Fill])
end

const _ROW_FORM_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(0, 1),
                         FieldReferenceStep("content"), FieldReferenceStep("children"))

# `[c].<rest>` ↔ the value of column c. The form shows no part of a value, so the
# rest has no image. Every node of an image has its type, as a tab that splices it
# needs.
function map_reference_forward(::DataFrameViewRowToWidget, iomap, reference)
    output = iomap.output
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(output))
    head = get_reference_head(reference)
    head isa RangeReferenceStep && head.stop == head.start + 1 || return nothing
    c = head.stop
    c <= ncol(iomap.input.view.frame) || return nothing
    annotate_reference_types(output, extend_reference(EmptyReference(), _ROW_FORM_STEPS...,
                                                       RangeReferenceStep(2c - 1, 2c)))
end

# A path into the name or the value of column c is the cell `[c]`; any other path
# is the row.
function map_reference_backward(::DataFrameViewRowToWidget, iomap, reference)
    steps = get_reference_steps(reference)
    n = length(_ROW_FORM_STEPS)
    (length(steps) > n && all(k -> steps[k] == _ROW_FORM_STEPS[k], 1:n) &&
     steps[n + 1] isa RangeReferenceStep) || return EmptyReference()
    k = steps[n + 1].stop
    c = (k + 1) ÷ 2
    ConcreteReference(RangeReferenceStep(c - 1, c), EmptyReference())
end
