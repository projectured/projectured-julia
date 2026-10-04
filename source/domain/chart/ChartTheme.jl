# Fragment of `ChartModule` — the theme of the chart renderer: the frame's
# colors, the three fonts a chart draws with, the lengths of its layout, and
# the dash and the opacity of what it draws.

"""
    ChartTheme

The colors, the fonts and the spacing of a chart: its background, its axes,
its gridlines, its series and its legend.

The theme of the Chart projections. `@theme` declares it, so `ScaledChartTheme`
holds each value times its scale, and `ChartTheme()` is the default theme.

The fields are in groups: the colors, the three fonts, the lengths of the
layout and the look of a drawn line: its dash and its opacity. Each field has
a docstring that says what it draws, which the appearance tab shows under its
name.

A chart projection holds the values of the theme, and no theme, in the `style`
field of `ChartPlotToGraphicsCanvas`: one `NamedTuple` that its builder reads
from a theme, scaled or not; with no theme it holds the plain values of the
default theme. A value that a chart's own
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
    "The label of a strip segment whose own color is too dark for the normal text color."
    strip_contrast_text::StyleColor = StyleColor(1.0, 1.0, 1.0, 1.0)
    "The readout lines of the pointer."
    crosshair::StyleColor       = StyleColor(0xdc / 255, 0x32 / 255, 0x2f / 255, 0.7)
    "The rubber band of a zoom drag."
    band_fill::StyleColor       = StyleColor(0x88 / 255, 0xbb / 255, 0xee / 255, 0x30 / 255)
    "The font of the chart's own title."
    title_font::FontRole       = FontRole(base = :axis_font, weight = 700, relative_size = 16 / 14)
    "The font of an axis title, a tick label and a strip's segment name."
    axis_font::StyleFont        = StyleFont("Ubuntu", 12)
    "The font of a legend item's label."
    legend_font::FontRole      = FontRole(base = :axis_font)
    "The space around the whole chart."
    padding::Spacing            = Spacing(8)
    "The length a tick mark reaches outside the plot frame."
    tick_length::ControlSize    = ControlSize(4)
    "The space between a tick mark and its label, and between a legend swatch and its label."
    label_gap::Spacing          = Spacing(3)
    "The space below an axis title, above the axis it sits over."
    axis_title_gap::Spacing     = Spacing(2)
    "The target space between two ticks."
    tick_spacing::Spacing       = Spacing(70)
    "The width of the color sample of a legend item."
    swatch::ControlSize         = ControlSize(14)
    "The space between a legend swatch and its label, and between the columns of a legend."
    legend_gap::Spacing         = Spacing(6)
    "The space inside the legend box, from its edge to its items."
    legend_padding::Spacing     = Spacing(6)
    "The space added to the height of a legend row, above its text."
    legend_line_gap::Spacing    = Spacing(4)
    "How far a highlight reaches past what it highlights: a legend item, the chart title, or the legend box."
    highlight_inset::Spacing    = Spacing(3)
    "The margin above and below the chart title inside its selection highlight."
    title_highlight_margin::Spacing = Spacing(2)
    "The rounded corner of a box the chart draws: the legend, a selection or hover highlight, and the pointer readout."
    radius::Radius               = Radius(3)
    "The rounded corner of a legend's color swatch."
    swatch_radius::Radius        = Radius(2)
    "The rounded corner of the box an empty chart draws in place of its plot."
    placeholder_radius::Radius   = Radius(4)
    "The border drawn around a filled shape: a histogram bar, a strip segment, a marker, the pointer readout and the empty-chart placeholder."
    border_width::LineWidth      = LineWidth(1)
    "The outline of a selected part: the whole chart's frame, the legend box, or a selected sample."
    selected_width::LineWidth    = LineWidth(2)
    "The line of a histogram series drawn in outline mode."
    histogram_outline_width::LineWidth = LineWidth(2)
    "The dash of a gridline."
    grid_dash::Tuple{Int,Int}    = (2, 3)
    "The dash of the crosshair's readout lines."
    crosshair_dash::Tuple{Int,Int} = (3, 3)
    "The dash of a line series drawn dotted."
    dotted_line_dash::Tuple{Int,Int} = (1, 3)
    "The dash of a line series drawn dashed."
    dashed_line_dash::Tuple{Int,Int} = (6, 4)
    "The opacity of a series that is not the one the pointer is on, while another is lit."
    veil_alpha::Float64          = 0.25
    "The opacity of the cell of a histogram that holds the values below or above its range, relative to the color of its series."
    overflow_alpha::Float64      = 0.5
end
