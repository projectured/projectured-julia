# Fragment of `SequenceChartModule` — the theme of a sequence chart: the colors
# of its frame, its lanes, its arrows and its events, the fonts of its title and
# its labels, and the lengths of its padding, its gaps and its lane spacing.

"""
    SequenceChartTheme

The colors, the fonts and the spacing of a sequence chart: its lanes, its
arrows, its events and the selection and hover rings.

The theme of the SequenceChart projections. `@theme` declares it, so
`ScaledSequenceChartTheme` holds each value times its scale, and
`SequenceChartTheme()` is the default theme.

The fields are in groups: the colors of the frame, the lanes, the arrows and
the events; the fonts of the title and the labels; and the lengths of the
padding, the gaps and the lane spacing. Each field has a docstring that says
what it draws, which the appearance tab shows under its name.

A SequenceChart projection reads the scaled theme through its `style` field,
one `NamedTuple` built by `make_theme_values_field`; with no theme it holds the
plain values of the default theme.
"""
@theme struct SequenceChartTheme
    "The whole canvas, behind the body."
    background::StyleColor = color_solarized_background_lighter
    "The body, where the lanes and their events draw."
    body_background::StyleColor = StyleColor(1.0, 1.0, 1.0, 1.0)
    "A lane's line, when the lane names no color of its own."
    axis::StyleColor = color_solarized_content_dark
    "A tick, a lane name, a title, a readout, and a label."
    text_color::StyleColor = color_solarized_content_darker
    "The time-scale strip, when the chart names no color of its own."
    gutter::StyleColor = StyleColor(1.0, 1.0, 0.94, 1.0)
    "The border of the gutter strip."
    gutter_border::StyleColor = StyleColor(0.0, 0.0, 0.0, 0.25)
    "The dotted line a tick draws down through the body."
    hairline::StyleColor = StyleColor(0.0, 0.0, 0.0, 0.14)
    "The wash over a stretch where the clock stands still."
    zero_time::StyleColor = StyleColor(0.0, 0.0, 0.0, 0.055)
    "An arrow, when its kind names no color of its own."
    arrow::StyleColor = color_solarized_blue
    "An occurrence, when its kind names no color of its own."
    event::StyleColor = StyleColor(0xd3 / 255, 0x36 / 255, 0x82 / 255, 1.0)
    "The ring, the highlight and the cursor line of a selection."
    selected::StyleColor = StyleColor(0x26 / 255, 0x8b / 255, 0xd2 / 255, 0.9)
    "The ring and the highlight of what the pointer is over."
    hover::StyleColor = StyleColor(0x26 / 255, 0x8b / 255, 0xd2 / 255, 0.45)
    "The font of the chart's title."
    title_font::StyleFont = font_ubuntu_bold_16
    "The font of a tick, a lane name, a readout and the empty-chart placeholder."
    axis_font::StyleFont = font_ubuntu_regular_14
    "The font of the label of an event, an arrow or a band."
    label_font::StyleFont = font_ubuntu_regular_14
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
    "The thickness of a state strip."
    band_height::ControlSize = ControlSize(12)
end
