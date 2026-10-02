# Fragment of `SequenceChartModule` — the theme of a sequence chart: the colors
# of its frame, its lanes, its arrows and its events, the fonts of its title and
# its labels, and the lengths of its padding, its gaps and its lane spacing.

"""
    SequenceChartTheme

The theme of the SequenceChart projections. `@theme` declares it, so
`ScaledSequenceChartTheme` holds each value times its scale, and
`SequenceChartTheme()` is the default theme.

Colors:
- `background` — the whole canvas, behind the body.
- `body_background` — the body, where the lanes and their events draw.
- `axis` — a lane's line, when the lane names no color of its own.
- `text_color` — a tick, a lane name, a title, a readout, and a label.
- `gutter` — the time-scale strip, when the chart names no color of its own.
- `gutter_border` — the border of the gutter strip.
- `hairline` — the dotted line a tick draws down through the body.
- `zero_time` — the wash over a stretch where the clock stands still.
- `arrow` — an arrow, when its kind names no color of its own.
- `event` — an occurrence, when its kind names no color of its own.
- `selected` — the ring, the highlight and the cursor line of a selection.
- `hover` — the ring and the highlight of what the pointer is over.

Fonts:
- `title_font` — the chart's title.
- `axis_font` — a tick, a lane name, a readout and the empty-chart placeholder.
- `label_font` — the label of an event, an arrow or a band.

Lengths:
- `padding` — the breathing room around the whole chart.
- `gutter_padding` — inside a gutter, above and below its text.
- `label_gap` — between a lane and its label.
- `tick_spacing` — about how many pixels one tick should span.
- `lane_spacing` — the least a lane gives the one next to it.
- `lane_offset` — from the body edge to the first lane.
- `band_height` — a state strip's thickness.

A SequenceChart projection reads the scaled theme through its `style` field,
one `NamedTuple` built by `make_theme_values_field`; with no theme it holds the
plain values of the default theme.
"""
@theme struct SequenceChartTheme
    background::StyleColor = color_solarized_background_lighter
    body_background::StyleColor = StyleColor(1.0, 1.0, 1.0, 1.0)
    axis::StyleColor = color_solarized_content_dark
    text_color::StyleColor = color_solarized_content_darker
    gutter::StyleColor = StyleColor(1.0, 1.0, 0.94, 1.0)
    gutter_border::StyleColor = StyleColor(0.0, 0.0, 0.0, 0.25)
    hairline::StyleColor = StyleColor(0.0, 0.0, 0.0, 0.14)
    zero_time::StyleColor = StyleColor(0.0, 0.0, 0.0, 0.055)
    arrow::StyleColor = color_solarized_blue
    event::StyleColor = StyleColor(0xd3 / 255, 0x36 / 255, 0x82 / 255, 1.0)
    selected::StyleColor = StyleColor(0x26 / 255, 0x8b / 255, 0xd2 / 255, 0.9)
    hover::StyleColor = StyleColor(0x26 / 255, 0x8b / 255, 0xd2 / 255, 0.45)
    title_font::StyleFont = font_ubuntu_bold_16
    axis_font::StyleFont = font_ubuntu_regular_14
    label_font::StyleFont = font_ubuntu_regular_14
    padding::Spacing = Spacing(8)
    gutter_padding::Spacing = Spacing(3)
    label_gap::Spacing = Spacing(4)
    tick_spacing::Spacing = Spacing(100)
    lane_spacing::Spacing = Spacing(16)
    lane_offset::Spacing = Spacing(14)
    band_height::ControlSize = ControlSize(12)
end
