# The text stage prints the lines of a `MarkedText`, split at its marks, and the
# graphics stage draws them.
function make_text_marking_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        MarkedTextToText(),
        TextToGraphics(measure=measure),
    )
end
