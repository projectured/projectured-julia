# Fragment of `DataFramesModule`.
#
# The list of the values of a column: "Filter by values…" of the menu of a header
# opens a dialog with a box for each distinct value of the column and the count of
# its rows, and "Apply" writes the ticked values into the filter of the column,
# `= a, b`. So the filter row stays the one place that holds a filter. The values
# are counted when the dialog opens, and a column of more than
# `_VALUE_LIST_LIMIT` distinct values has no list. A `missing` is not in the list,
# because the filter row has its own words for it, `missing` and `!missing`.

const _VALUE_LIST_LIMIT = 1000

# The distinct values of `column` that are not `missing`, sorted, each with the
# count of its rows; `nothing` when there are more than `limit` of them.
function _count_column_values(column::AbstractVector; limit::Int = _VALUE_LIST_LIMIT)
    counts = Dict{nonmissingtype(eltype(column)),Int}()
    for value in column
        ismissing(value) && continue
        count = get(counts, value, 0)
        count == 0 && length(counts) == limit && return nothing
        counts[value] = count + 1
    end
    counted = collect(counts)
    # Values of types that have no order between them keep the order of the dict.
    try
        sort!(counted; by = first)
    catch exception
        exception isa MethodError || rethrow()
    end
    counted
end

# The text of `value` in a list of the filter row: in double quotes when it holds
# a comma or starts or ends with a space, so the list reads it back as one value.
function _get_listed_value_text(value)
    text = _get_filter_text(value)
    (occursin(',', text) || text != strip(text)) ? "\"" * text * "\"" : text
end

# The filter text that keeps the values `ticked` of `values`: none when every
# value is ticked, else the list of the ticked ones; `nothing` when none is.
function _make_value_list_text(values::Vector, ticked::Vector{Bool})
    any(ticked) || return nothing
    all(ticked) && return ""
    "= " * join((_get_listed_value_text(value) for (value, on) in zip(values, ticked) if on), ", ")
end

# Whether the filter of `column` in `view` keeps `value`, read at the open of
# the list: a list filter keeps its values, and any other filter keeps all.
function _is_value_listed(view, column::String, value)
    filter = _find_column_filter(view.query, column)
    filter === nothing && return true
    condition = _parse_column_filter(filter.text, eltype(view.frame[!, column]))
    condition isa _EqualCondition ? condition(value) : true
end

# The dialog of the values of `column` in `view`, and `take()`, which gives the
# operation that "Apply" posts, or `nothing` when no value is ticked. A column
# with more than `_VALUE_LIST_LIMIT` distinct values gives a dialog that says so,
# and a `take` that gives `nothing`. `widget` and `frame` are the widget and the
# data frame themes of the editor that opens the dialog, scaled or not, or
# `nothing` for the default themes.
function _make_value_list_dialog(view, column::String; widget = nothing, frame = nothing)
    counted = _count_column_values(view.frame[!, column])
    if counted === nothing
        text = "The column $(column) has more than $(_VALUE_LIST_LIMIT) distinct values. " *
               "Type a filter in the filter row instead."
        return (WidgetDialog("Filter by values", text, Any[WidgetButton("Close")];
                             popup_id = :data_frame_values), () -> nothing)
    end
    values = Any[first(entry) for entry in counted]
    boxes = WidgetCheckbox[WidgetCheckbox(_is_value_listed(view, column, value);
                                          label = _get_filter_text(value) * "  (" * string(count) * ")")
                           for (value, count) in counted]
    size = unwrap_cell(get_data_frame_style(frame, :value_list_size))
    list = WidgetScrollPane(VerticalLayout(Any[boxes...]; gap = unwrap_cell(get_widget_style(widget, :item_gap)));
                            size = Point2D(Int(size.x[]), Int(size.y[])))
    function take()
        text = _make_value_list_text(values, Bool[box.content for box in boxes])
        text === nothing ? nothing : _make_filter_write_operation(view, column, text)
    end
    dialog = WidgetDialog("Filter by values", list, Any[WidgetButton("Cancel"), WidgetButton("Apply")];
                          popup_id = :data_frame_values)
    (dialog, take)
end

# Open the dialog of the values of `column` in `view` in `editor`. "Apply" posts
# the write of the filter.
function _open_value_list!(editor, view, column::String)
    appearance = something(find_editor_appearance(; editor), Appearance())
    frame = get_scaled_theme!(appearance, DataFrameTheme)
    dialog, take = _make_value_list_dialog(view, column; frame,
                                           widget = get_scaled_theme!(appearance, WidgetTheme))
    window = frame.value_list_window_size
    apply = last(collect(dialog.buttons))
    apply.action = Action(apply.action.label;
                          callback = _ -> (operation = take();
                                           operation === nothing || post_operation!(editor, operation);
                                           nothing))
    evaluate_operation(editor, OpenWindowOperation(id = :data_frame_values, title = "Filter by values",
                                                   x = -1, y = -1, width = Int(window.x[]),
                                                   height = Int(window.y[]),
                                                   style = :floating, content = dialog))
    nothing
end
