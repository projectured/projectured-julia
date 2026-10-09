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

# The text stage holds a row for each wrapper, so a filter prints the highlighted
# text through it and filters the block that the highlight gives.
function make_highlighted_filtered_text_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(
            FilteredText    => FilteredTextToText(),
            HighlightedText => HighlightedTextToText(),
            TextBlock       => IdentityProjection())),
        TextToGraphics(measure=measure),
    )
end
