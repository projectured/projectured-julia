function make_text_filtering_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        TextFiltering(r"dolor"),   # keep only lines mentioning "dolor"
        TextToGraphics(measure=measure),
    )
end
