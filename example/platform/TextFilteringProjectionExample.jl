function make_text_filtering_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        TextFiltering(r"dolor"),   # keep only lines mentioning "dolor"
        TextToGraphics(measure=measure),
    )
end
