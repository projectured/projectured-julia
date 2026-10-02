# Fragment of `ChartModule` — the theme of the chart renderer: the frame's
# colors, the three fonts a chart draws with, and the lengths of its layout.

"""
    ChartTheme

The colors, the fonts and the spacing of a chart: its background, its axes,
its gridlines, its series and its legend.

The theme of the Chart projections. `@theme` declares it, so `ScaledChartTheme`
holds each value times its scale, and `ChartTheme()` is the default theme.

The fields are in groups: the colors, the three fonts and the lengths of the
layout. Each field has a docstring that says what it draws, which the
appearance tab shows as its tooltip.

A chart projection reads the scaled theme through `ChartPlotToGraphicsCanvas`'s
`style` field, which holds every value as one `NamedTuple`; with no theme it
holds the plain values of the default theme. A value that a chart's own
`ChartStyle` sets keeps its priority over the theme.
"""
@theme struct ChartTheme
    "The canvas behind the whole chart."
    background::StyleColor      = color_solarized_background_lighter
    "The plot rectangle, under the series."
    plot_background::StyleColor = StyleColor(1.0, 1.0, 1.0, 1.0)
    "The two axis lines, the tick marks and the border of the grid frame."
    axis::StyleColor            = color_solarized_content_dark
    "A gridline."
    grid::StyleColor            = StyleColor(0.0, 0.0, 0.0, 0.10)
    "The title, the axis titles, the tick labels and the legend's \"and N more\" line."
    text_color::StyleColor      = color_solarized_content_darker
    "The fill of a selected part."
    selected_fill::StyleColor   = StyleColor(0x88 / 255, 0xbb / 255, 0xee / 255, 0x60 / 255)
    "The outline of a selected part."
    selected_edge::StyleColor   = StyleColor(0x26 / 255, 0x8b / 255, 0xd2 / 255, 0.9)
    "The fill of a hovered legend item."
    hover_fill::StyleColor      = StyleColor(0x88 / 255, 0xbb / 255, 0xee / 255, 0x28 / 255)
    "The legend swatch of a strip series, neutral because the band draws in many colors."
    strip_swatch::StyleColor    = StyleColor(0.5, 0.5, 0.5, 0.55)
    "The border between adjacent strip segments."
    strip_edge::StyleColor      = StyleColor(0.0, 0.0, 0.0, 0.10)
    "The readout lines of the pointer."
    crosshair::StyleColor       = StyleColor(0xdc / 255, 0x32 / 255, 0x2f / 255, 0.7)
    "The rubber band of a zoom drag."
    band_fill::StyleColor       = StyleColor(0x88 / 255, 0xbb / 255, 0xee / 255, 0x30 / 255)
    "The font of the chart's own title."
    title_font::StyleFont       = font_ubuntu_bold_16
    "The font of an axis title, a tick label and a strip's segment name."
    axis_font::StyleFont        = font_ubuntu_regular_14
    "The font of a legend item's label."
    legend_font::StyleFont      = font_ubuntu_regular_14
    "The space around the whole chart."
    padding::Spacing            = Spacing(8)
    "The length a tick mark reaches outside the plot frame."
    tick_length::ControlSize    = ControlSize(4)
    "The space between a tick mark and its label, and between a legend swatch and its label."
    label_gap::Spacing          = Spacing(3)
    "The target space between two ticks."
    tick_spacing::Spacing       = Spacing(70)
    "The width of the color sample of a legend item."
    swatch::ControlSize         = ControlSize(14)
    "The space between a legend swatch and its label, and between the columns of a legend."
    legend_gap::Spacing         = Spacing(6)
end
