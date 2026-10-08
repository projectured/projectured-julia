# The text stage draws a `HighlightedText` with a swatch behind every match of
# its pattern, and passes a plain block through; the graphics stage draws the
# block that comes back.
function make_text_highlighting_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(
            HighlightedText => HighlightedTextToText(),
            TextBlock       => IdentityProjection())),
        TextToGraphics(measure=measure),
    )
end
