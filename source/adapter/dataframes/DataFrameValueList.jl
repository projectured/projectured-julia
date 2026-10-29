# Fragment of `DataFramesModule`.
#
# The list of the values of a column: "Filter by values…" of the menu of a header
# opens the dialog of `make_value_list_dialog`, and "Apply" writes the ticked
# values into the filter of the column, `= a, b`. So the filter row stays the one
# place that holds a filter. The values are counted when the dialog opens. A
# `missing` is not in the list, because the filter row has its own words for it,
# `missing` and `!missing`.

# The dialog of the values of `column` in `view`, and `take()`, which gives the
# operation that "Apply" posts, or `nothing` when no value is ticked. `widget` is
# the widget theme of the editor that opens the dialog, scaled or not, or
# `nothing` for the default theme.
function _make_value_list_dialog(view, column::String; widget = nothing)
    filter = _find_column_filter(view.query, column)
    make_value_list_dialog(column, view.frame[!, column], filter === nothing ? "" : filter.text,
                           text -> _make_filter_write_operation(view, column, text); widget)
end

# Open the dialog of the values of `column` in `view` in `editor`. "Apply" posts
# the write of the filter.
function _open_value_list!(editor, view, column::String)
    appearance = something(find_editor_appearance(; editor), Appearance())
    widget = get_scaled_theme!(appearance, WidgetTheme)
    dialog, take = _make_value_list_dialog(view, column; widget)
    window = widget.value_list_window_size
    apply = last(collect(dialog.buttons))
    apply.action = Action(apply.action.label;
                          callback = _ -> (operation = take();
                                           operation === nothing || post_operation!(editor, operation);
                                           nothing))
    evaluate_operation(editor, OpenWindowOperation(id = :value_list, title = "Filter by values",
                                                   x = -1, y = -1, width = Int(window.x[]),
                                                   height = Int(window.y[]),
                                                   style = :floating, content = dialog))
    nothing
end
