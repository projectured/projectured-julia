# The text stage keeps the lines of a `FilteredText` that match its pattern, and
# passes a plain block through; the graphics stage draws the block that comes
# back.
function make_text_filtering_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(
            FilteredText => FilteredTextToText(),
            TextBlock    => IdentityProjection())),
        TextToGraphics(measure=measure),
    )
end
