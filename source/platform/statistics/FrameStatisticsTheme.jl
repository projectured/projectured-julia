# Fragment of `FrameStatisticsModule` — the theme of the statistics table: the
# text of its header, its rows, and its empty line.

"""
    FrameStatisticsTheme

The theme of the statistics table. `@theme` declares it, so
`ScaledFrameStatisticsTheme` holds each value times its scale, and
`FrameStatisticsTheme()` is the default theme.

- `header_text` — the head line and the column header.
- `row_text` — one measurement.
- `empty_text` — the line the table shows while it holds no frame.

The statistics table reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct FrameStatisticsTheme
    header_text::StyleText = StyleText(font_dejavu_monospace_bold_16, color_solarized_cyan)
    row_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_700)
    empty_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
end

# The style field of a statistics projection that holds the text `name` of the
# theme `theme`: a `FrameStatisticsTheme`, a scaled one, or `nothing` for the
# default values.
_get_frame_statistics_style(theme, name::Symbol) =
    make_style_field(FrameStatisticsTheme, scale_theme(theme), StyleText, name)
