# Fragment of `ChartModule` — the theme of the chart renderer: the frame's
# colors, the three fonts a chart draws with, and the lengths of its layout.

"""
    ChartTheme

The theme of the Chart projections. `@theme` declares it, so `ScaledChartTheme`
holds each value times its scale, and `ChartTheme()` is the default theme.

Colors:
- `background` — the canvas behind the whole chart.
- `plot_background` — the plot rectangle, under the series.
- `axis` — the two axis lines, the tick marks and the grid frame's border.
- `grid` — a gridline.
- `text_color` — the title, the axis titles, the tick labels and the legend's
  "… and N more" line.
- `selected_fill`, `selected_edge` — the fill and the outline of a selected part.
- `hover_fill` — a hovered legend item.
- `strip_swatch` — a strip series' own legend swatch, neutral because the band
  it stands for draws in many colors.
- `strip_edge` — the border between adjacent strip segments, when drawn.
- `crosshair` — the pointer's readout lines.
- `band_fill` — the rubber band of a zoom drag.

Fonts:
- `title_font` — the chart's own title, the fallback of `ChartStyle.title_font`.
- `axis_font` — an axis title, a tick label and a strip's segment name, the
  fallback of `ChartStyle.axis_font`.
- `legend_font` — a legend item's label, the fallback of
  `ChartStyle.legend_font`.

Lengths:
- `padding` — the breathing room around the whole chart.
- `tick_length` — how far a tick mark reaches outside the plot frame.
- `label_gap` — between a tick mark and its label, and a legend swatch and its
  label.
- `tick_spacing` — the target pixel distance between two ticks.
- `swatch` — the width of a legend item's color sample.
- `legend_gap` — between a legend swatch and its label, and between the
  columns of a legend.

A chart projection reads the scaled theme through `ChartPlotToGraphicsCanvas`'s
`style` field, which holds every value as one `NamedTuple`; with no theme it
holds the plain values of the default theme. A value that a chart's own
`ChartStyle` sets keeps its priority over the theme.
"""
@theme struct ChartTheme
    background::StyleColor      = color_solarized_background_lighter
    plot_background::StyleColor = StyleColor(1.0, 1.0, 1.0, 1.0)
    axis::StyleColor            = color_solarized_content_dark
    grid::StyleColor            = StyleColor(0.0, 0.0, 0.0, 0.10)
    text_color::StyleColor      = color_solarized_content_darker
    selected_fill::StyleColor   = StyleColor(0x88 / 255, 0xbb / 255, 0xee / 255, 0x60 / 255)
    selected_edge::StyleColor   = StyleColor(0x26 / 255, 0x8b / 255, 0xd2 / 255, 0.9)
    hover_fill::StyleColor      = StyleColor(0x88 / 255, 0xbb / 255, 0xee / 255, 0x28 / 255)
    strip_swatch::StyleColor    = StyleColor(0.5, 0.5, 0.5, 0.55)
    strip_edge::StyleColor      = StyleColor(0.0, 0.0, 0.0, 0.10)
    crosshair::StyleColor       = StyleColor(0xdc / 255, 0x32 / 255, 0x2f / 255, 0.7)
    band_fill::StyleColor       = StyleColor(0x88 / 255, 0xbb / 255, 0xee / 255, 0x30 / 255)
    title_font::StyleFont       = font_ubuntu_bold_16
    axis_font::StyleFont        = font_ubuntu_regular_14
    legend_font::StyleFont      = font_ubuntu_regular_14
    padding::Spacing            = Spacing(8)
    tick_length::ControlSize    = ControlSize(4)
    label_gap::Spacing          = Spacing(3)
    tick_spacing::Spacing       = Spacing(70)
    swatch::ControlSize         = ControlSize(14)
    legend_gap::Spacing         = Spacing(6)
end
