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

A data frame projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme. The table
and the scroll bar beside it draw with the widget theme of the appearance, not
with this one.
"""
@theme struct DataFrameTheme
    "The width of a field of the filter row, so an empty field has room for a press."
    query_field_width::ControlSize = ControlSize(80)
    "The width of the field of the expression bar."
    expression_field_width::ControlSize = ControlSize(480)
    "The gap between the name of a column and the glyph of its sort, in its header."
    filter_gap::Spacing = Spacing(4)
    "The gap between the parts of the expression bar: the words, the field and the glyph."
    expression_gap::Spacing = Spacing(8)
    "A field of the filter row or of the expression bar whose text does not parse."
    invalid_query::StyleColor = color_lighten(color_red, 0.75)
    "The glyph of the header of a column that does not sort."
    unsorted_glyph::StyleColor = color_gray159
    "The width of a column of the table when a wide frame draws its columns as a list."
    list_column_width::ControlSize = ControlSize(160)
end

# The style field `name` of `theme`, of the kind `T`: a `DataFrameTheme`, a scaled
# one, or `nothing` for the default values.
_get_data_frame_style(theme, name::Symbol, ::Type{T}) where {T} =
    make_style_field(DataFrameTheme, scale_theme(theme), T; name)
