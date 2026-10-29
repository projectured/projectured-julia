# Fragment of `DataFramesModule` — the theme of the data frame view: the width of
# the fields of the expression bar, the gap between its parts, and the width of a
# column when a wide frame draws its columns as a list.

"""
    DataFrameTheme

The sizes of the expression bar of a data frame view: the width of its fields,
the gap between its parts, and the width of a column in the list form of a wide
frame. The header of a column draws with the widget theme.

The theme of the `DataFrameViewToWidget` projection. `@theme` declares it, so
`ScaledDataFrameTheme` holds each value times its scale, and `DataFrameTheme()`
is the default theme.

A data frame projection holds its styles and no theme;
`make_data_frame_view_projection` gives them with `get_data_frame_style`, and a
projection built with no styles holds the plain values of the default theme. The table
and its scroll bar draw with the widget theme of the appearance, not with this
one.
"""
@theme struct DataFrameTheme
    "The width of the field of the expression bar."
    expression_field_width::ControlSize = ControlSize(480)
    "The width of the find field of the expression bar."
    find_field_width::ControlSize = ControlSize(160)
    "The gap between the parts of the expression bar: the words, the fields and the glyph."
    expression_gap::Spacing = Spacing(8)
    "The width of a column of the table when a wide frame draws its columns as a list."
    list_column_width::ControlSize = ControlSize(160)
end
