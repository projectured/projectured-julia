function make_text_highlighting_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        TextHighlighting(r"dolor"),   # yellow swatch behind every "dolor"
        TextToGraphics(measure=measure),
    )
end
