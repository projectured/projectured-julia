function make_text_filtering_projection_example(; measure=truetype_measure_text)
    SequentialProjection(
        TextFiltering(r"dolor"),   # keep only lines mentioning "dolor"
        TextToGraphics(measure=measure),
    )
end
