function make_word_wrapping_projection_example(; max_width=600, measure=measure_truetype_text)
    ChainingProjection(
        WordWrapping(max_width=max_width, measure=measure),
        TextToGraphics(measure=measure),
    )
end
