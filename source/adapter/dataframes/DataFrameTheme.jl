# Fragment of `DataFramesModule` — the theme of the data frame view: the width of
# a field of the filter row and of the expression bar, the gaps between their
# parts, the color of a query that does not parse, the color of the sort glyph of
# a column that does not sort, and the width of a column when a wide frame draws
# its columns as a list.

"""
    DataFrameTheme

The colors and the sizes of the filter row and the expression bar of a data
frame view: the width of their fields, the gaps between their parts, the color of
a query that does not parse, the color of the sort glyph of a column that does
not sort, and the width of a column in the list form of a wide frame.

The theme of the `DataFrameViewToWidget` projection. `@theme` declares it, so
`ScaledDataFrameTheme` holds each value times its scale, and `DataFrameTheme()`
is the default theme.

A data frame projection holds its styles and no theme;
`make_data_frame_view_projection` gives them with `get_data_frame_style`, and a
projection built with no styles holds the plain values of the default theme. The table
and the scroll bar beside it draw with the widget theme of the appearance, not
with this one.
"""
@theme struct DataFrameTheme
    "The width of a field of the filter row, so an empty field has room for a press."
    query_field_width::ControlSize = ControlSize(80)
    "The width of the field of the expression bar."
    expression_field_width::ControlSize = ControlSize(480)
    "The width of the find field of the expression bar."
    find_field_width::ControlSize = ControlSize(160)
    "The gap between the name of a column and the glyph of its sort, in its header."
    filter_gap::Spacing = Spacing(4)
    "The gap between the parts of the expression bar: the words, the fields and the glyph."
    expression_gap::Spacing = Spacing(8)
    "A field of the filter row or of the expression bar whose text does not parse."
    invalid_query::StyleColor = ColorRole(:error_tint)
    "The glyph of the header of a column that does not sort."
    unsorted_glyph::StyleColor = ColorRole(:text_faint)
    "The width of a column of the table when a wide frame draws its columns as a list."
    list_column_width::ControlSize = ControlSize(160)
    "The width and the height of the list in the dialog of the values of a column."
    value_list_size::ControlSize = ControlSize(Point2D(320, 320))
    "The width and the height of the window of the dialog of the values of a column."
    value_list_window_size::ControlSize = ControlSize(Point2D(400, 460))
end
