# Fragment of `FrameStatisticsModule` — the theme of the statistics table: the
# text of its header, its rows, and its empty line.

"""
    FrameStatisticsTheme

The fonts and the colors of the Statistics panel: its header, its rows of
measurements and the line it shows when empty.

The theme of the statistics table. `@theme` declares it, so
`ScaledFrameStatisticsTheme` holds each value times its scale, and
`FrameStatisticsTheme()` is the default theme.

The fields are the text styles of the table's header, its rows and its empty
line. Each field has a docstring that says what it draws, which the
appearance tab shows under its name.

`make_frame_statistics_projection` gives the projection of the statistics table
its styles with `get_frame_statistics_style`, from a theme scaled or not; a
projection built with no styles holds the plain values of the default theme.
"""
@theme struct FrameStatisticsTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("DejaVu Sans Mono", 13)
    "The head line and the column header."
    header_text::TextRole = TextRole(color_solarized_cyan; weight = 700)
    "One measurement."
    row_text::TextRole = TextRole(color_slate_700)
    "The line the table shows while it holds no frame."
    empty_text::TextRole = TextRole(color_slate_500)
end
