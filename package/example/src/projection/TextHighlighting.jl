function make_text_highlighting_projection_example(; measure=truetype_measure_text)
    SequentialProjection(
        TextHighlighting(r"dolor"),   # yellow swatch behind every "dolor"
        TextToGraphics(measure=measure),
    )
end
