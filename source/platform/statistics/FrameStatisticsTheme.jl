# Fragment of `FrameStatisticsModule` — the theme of the statistics table: the
# text of its header, its rows, and its empty line.

"""
    FrameStatisticsTheme

The theme of the statistics table. `@theme` declares it, so
`ScaledFrameStatisticsTheme` holds each value times its scale, and
`FrameStatisticsTheme()` is the default theme.

The fields are the text styles of the table's header, its rows and its empty
line. Each field has a docstring that says what it draws, which the
appearance tab shows as its tooltip.

The statistics table reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct FrameStatisticsTheme
    "The head line and the column header."
    header_text::StyleText = StyleText(font_dejavu_monospace_bold_16, color_solarized_cyan)
    "One measurement."
    row_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_700)
    "The line the table shows while it holds no frame."
    empty_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
end

# The style field of a statistics projection that holds the text `name` of the
# theme `theme`: a `FrameStatisticsTheme`, a scaled one, or `nothing` for the
# default values.
_get_frame_statistics_style(theme, name::Symbol) =
    make_style_field(FrameStatisticsTheme, scale_theme(theme), StyleText, name)
