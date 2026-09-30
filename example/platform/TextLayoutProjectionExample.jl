# The projection of the text layout examples: prose wrapped at 700 pixels at
# most, and laid out line by line with `spacing`.
function make_text_layout_projection_example(; measure::TextMeasure = FontFileMeasure(),
                                             spacing::LineSpacing = SingleSpacing())
    ChainingProjection(
        WordWrapping(measure = measure, max_width = 700),
        TextToGraphics(measure = measure, line_spacing = spacing),
    )
end
