# Fragment of `StyleModule`.
#
# The distance between the lines of a text, as a word processor sets it, and the
# box of a line that holds one text. A layout reads the metrics of a line from a
# `TextMeasure`; these functions give the distance to the next line and the place
# of the baseline in the line box. The real numbers round once, where
# `compute_line_box` makes the positions of a line.

"""
    LineSpacing

How far apart the lines of a text are. The natural distance `N` of a line is
the sum of its largest ascent, descent and line gap: the distance its fonts ask
for.

- [`SingleSpacing`](@ref): `N`;
- [`MultipleSpacing`](@ref)`(factor)`: `factor × N`;
- [`ExactSpacing`](@ref)`(distance)`: `distance`, whatever the fonts;
- [`AtLeastSpacing`](@ref)`(distance)`: `distance`, or `N` when that is larger.
"""
abstract type LineSpacing end

"""
    SingleSpacing()

Lines at their natural distance: the largest ascent, descent and line gap of
each line, added.
"""
struct SingleSpacing <: LineSpacing end

"""
    MultipleSpacing(factor)

Lines at `factor` times their natural distance, for example 1.15, 1.5 or 2.
"""
struct MultipleSpacing <: LineSpacing
    factor::Float64
end

"""
    ExactSpacing(distance)

Lines `distance` logical pixels apart, whatever their fonts. The ink of two
lines overlaps when `distance` is less than their ascent and descent.
"""
struct ExactSpacing <: LineSpacing
    distance::Float64
end

"""
    AtLeastSpacing(distance)

Lines `distance` logical pixels apart, or at their natural distance when that is
larger.
"""
struct AtLeastSpacing <: LineSpacing
    distance::Float64
end

_natural_distance(metrics::FontMetrics) = metrics.ascent + metrics.descent + metrics.line_gap

"""
    compute_line_distance(spacing::LineSpacing, metrics::FontMetrics) -> Float64

The distance from the top of a line box to the top of the next one, in logical
pixels, for a line whose largest ascent, descent and line gap are `metrics`. The
baseline of the next line is the same distance below this baseline.
"""
compute_line_distance(::SingleSpacing, metrics::FontMetrics) = _natural_distance(metrics)
compute_line_distance(spacing::MultipleSpacing, metrics::FontMetrics) =
    spacing.factor * _natural_distance(metrics)
compute_line_distance(spacing::ExactSpacing, ::FontMetrics) = spacing.distance
compute_line_distance(spacing::AtLeastSpacing, metrics::FontMetrics) =
    max(spacing.distance, _natural_distance(metrics))

"""
    compute_baseline_offset(spacing::LineSpacing, metrics::FontMetrics) -> Float64

The distance from the top of a line box down to its baseline: half of the
leading, then the ascent. The leading is the line distance less the ascent and
the descent, and its other half is below the ink.
"""
function compute_baseline_offset(spacing::LineSpacing, metrics::FontMetrics)
    leading = compute_line_distance(spacing, metrics) - (metrics.ascent + metrics.descent)
    leading / 2 + metrics.ascent
end

"""
    compute_line_metrics(boxes) -> FontMetrics

The metrics of a line that holds `boxes`, each a [`StringBox`](@ref) or a
[`FontMetrics`](@ref): the largest ascent, the largest descent and the largest
line gap of them.
"""
function compute_line_metrics(boxes)
    ascent = descent = line_gap = 0.0
    for box in boxes
        ascent = max(ascent, box.ascent)
        descent = max(descent, box.descent)
        line_gap = max(line_gap, box.line_gap)
    end
    FontMetrics(ascent, descent, line_gap)
end

"""
    compute_line_baseline(spacing::LineSpacing, metrics::FontMetrics) -> Int

The baseline of a line in whole pixels below the top of its line box: the
offset of [`compute_baseline_offset`](@ref) rounded, and never less than the
ascent rounded up, so the ink never rises above the line box.
"""
compute_line_baseline(spacing::LineSpacing, metrics::FontMetrics) =
    max(round(Int, compute_baseline_offset(spacing, metrics)), _round_up(metrics.ascent))

"""
    LineBox(width, height, baseline, text_y)

A line that holds one text, in whole logical pixels from the top of its box:

- `width`: the width of the text;
- `height`: down to the top of the next line at its spacing, or down to the
  bottom of the box of the text when that is lower;
- `baseline`: down to the baseline;
- `text_y`: down to the top of the box of the text, the `y` of its
  `GraphicsText`.
"""
struct LineBox
    width::Int
    height::Int
    baseline::Int
    text_y::Int
end

"""
    compute_line_box(measure::TextMeasure, text, font::StyleFont;
                     spacing::LineSpacing = SingleSpacing()) -> LineBox

The box of a line that holds `text` alone, as a label or a title does, with
its baseline at [`compute_line_baseline`](@ref). An empty text is a line of
`font` with no width.
"""
function compute_line_box(measure::TextMeasure, text, font::StyleFont;
                          spacing::LineSpacing = SingleSpacing())
    box = measure_string(measure, text, font)
    metrics = compute_line_metrics((box,))
    width, ascent, descent = compute_text_extent(box)
    baseline = compute_line_baseline(spacing, metrics)
    height = max(round(Int, compute_line_distance(spacing, metrics)), baseline + descent)
    LineBox(width, height, baseline, baseline - ascent)
end
