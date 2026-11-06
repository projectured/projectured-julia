# Fragment of `FrameStatisticsModule` — the theme of the statistics: the text of
# its head line and titles, of the cells of its tables, and of its empty line.

"""
    FrameStatisticsTheme

The fonts and the colors of the Statistics panel: its head line and
the titles of its tables, the cells of its tables, and the line it shows when
empty.

The theme of the statistics. `@theme` declares it, so
`ScaledFrameStatisticsTheme` holds each value times its scale, and
`FrameStatisticsTheme()` is the default theme.

The fields are the text styles of the head line and the titles, of the cells,
of the cells of a slow frame and of the empty line. The gap between the parts, the borders, the header rows and the scroll of the tables come from the
widget theme. Each field has a docstring that says what it draws, which the
appearance tab shows under its name.

`make_frame_statistics_projection` gives the projection of the statistics table
its styles with `get_frame_statistics_style`, from a theme scaled or not; a
projection built with no styles holds the plain values of the default theme.
"""
@theme struct FrameStatisticsTheme
    "The head line, the titles of the tables and the headers of their columns."
    header_text::ThemeText = TextRole(:text_muted; font_role = :column)
    "A cell of a table: a measurement, a number or a frame number."
    row_text::ThemeText = TextRole(:text; font_role = :text)
    "The line the panel shows while it holds no frame."
    empty_text::ThemeText = TextRole(:text_faint; font_role = :quiet)
    "A cell of a slow frame: its frame time is more than two times the median of the frames of the table."
    slow_text::ThemeText = TextRole(:warning_text; font_role = :text)
end
