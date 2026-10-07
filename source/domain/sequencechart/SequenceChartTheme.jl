# Fragment of `SequenceChartModule` — the theme of a sequence chart: the colors
# of its frame, its lanes, its arrows and its events, the fonts of its title and
# its labels, the lengths of its padding, its gaps and its lane spacing, and
# the dash and the width of what it draws.

"""
    SequenceChartTheme

The colors, the fonts and the spacing of a sequence chart: its lanes, its
arrows, its events and the selection and hover rings.

The theme of the SequenceChart projections. `@theme` declares it, so
`ScaledSequenceChartTheme` holds each value times its scale, and
`SequenceChartTheme()` is the default theme.

The fields are in groups: the colors of the frame, the lanes, the arrows and
the events; the fonts of the title and the labels; the lengths of the
padding, the gaps and the lane spacing; and the radius, the width, the dash
and the opacity of what it draws. Each field has a docstring that says what it
draws, which the appearance tab shows under its name.

A SequenceChart projection holds the values of the theme, and no theme, in its
`style` field: one `NamedTuple` that its builder reads with
`make_theme_values_field` from a theme, scaled or not; with no theme it holds the
plain values of the default theme.
"""
@theme struct SequenceChartTheme
    "The colors of the kinds of arrows and events that name no color of their own, in order, when the style names no cycle."
    series_colors::Vector{ThemeColor} = ThemeColor[ColorRole(Symbol("series_", i)) for i in 1:8]
    "The whole canvas, behind the body."
    background::ThemeColor = ColorRole(:background)
    "The body, where the lanes and their events draw."
    body_background::ThemeColor = ColorRole(:surface)
    "A lane's line, when the lane names no color of its own."
    axis::ThemeColor = ColorRole(:border_strong)
    "A tick, a lane name, a title, a readout, and a label."
    text_color::ThemeColor = ColorRole(:text_muted)
    "The time-scale strip, when the chart names no color of its own."
    gutter::ThemeColor = ColorRole(:surface_sunken)
    "The border of the gutter strip."
    gutter_border::ThemeColor = ColorRole(:border)
    "The dotted line a tick draws down through the body."
    hairline::ThemeColor = ColorRole(:grid)
    "The wash over a stretch where the clock stands still."
    zero_time::ThemeColor = ColorRole(:hover)
    "An arrow, when its kind names no color of its own."
    arrow::ThemeColor = ColorRole(:series_1)
    "An occurrence, when its kind names no color of its own."
    event::ThemeColor = ColorRole(:series_4)
    "The ring, the highlight and the cursor line of a selection."
    selected::ThemeColor = ColorRole(:selection_ring)
    "The ring and the highlight of what the pointer is over."
    hover::ThemeColor = ColorRole(:selection_ring; alpha = 0.5)
    "The opacity of a state band's generated color, when it names none of its own."
    band_overlay_alpha::Float64 = 0.45
    "The font of the chart's title."
    title_font::ThemeFont = FontRole(base = :axis_font, weight = 700, relative_size = 16 / 14)
    "The font of a tick, a lane name, a readout and the empty-chart placeholder."
    axis_font::StyleFont = StyleFont("Ubuntu", 12)
    "The font of the label of an event, an arrow or a band."
    label_font::ThemeFont = FontRole(base = :axis_font)
    "The space around the whole chart."
    padding::Spacing = Spacing(8)
    "The space inside a gutter, above and below its text."
    gutter_padding::Spacing = Spacing(3)
    "The space between a lane and its label."
    label_gap::Spacing = Spacing(4)
    "The target space one tick spans."
    tick_spacing::Spacing = Spacing(100)
    "The least space a lane gives the one next to it."
    lane_spacing::Spacing = Spacing(16)
    "The space from the body edge to the first lane."
    lane_offset::Spacing = Spacing(14)
    "How far the ring around a selected or hovered occurrence reaches past its mark."
    ring_margin::Spacing = Spacing(4)
    "The thickness of a state strip."
    band_height::ControlSize = ControlSize(12)
    "The rounded corner of the box an empty sequence chart draws in place of its body."
    radius::Radius = Radius(4)
    "The width of a thin line: a hairline, a lane, the elided-arrow marker, and the cursor line."
    line_width::LineWidth = LineWidth(1)
    "The border drawn around a filled shape: a gutter strip and the empty-chart placeholder."
    border_width::LineWidth = LineWidth(1)
    "The ring around a selected or hovered occurrence."
    ring_width::LineWidth = LineWidth(2)
    "The line of a selected or hovered arrow."
    selected_width::LineWidth = LineWidth(3)
    "The dash of the tick hairline through the body."
    hairline_dash::Tuple{Int,Int} = (2, 3)
    "The dash of the pointer's cursor line."
    cursor_dash::Tuple{Int,Int} = (3, 3)
    "The dash of an arrow kind drawn dashed."
    dashed_arrow_dash::Tuple{Int,Int} = (5, 3)
    "The dash of an arrow kind drawn dotted."
    dotted_arrow_dash::Tuple{Int,Int} = (2, 2)
    "The dash of the stub where a split arrow continues past the edge of the window."
    continuation_dash::Tuple{Int,Int} = (2, 3)
end
