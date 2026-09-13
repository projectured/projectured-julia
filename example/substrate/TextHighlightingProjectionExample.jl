function make_text_highlighting_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        TextHighlighting(r"dolor"),   # yellow swatch behind every "dolor"
        TextToGraphics(measure=measure),
    )
end
