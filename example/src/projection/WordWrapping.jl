function make_word_wrapping_projection_example(; wrap_width=60, measure=sdl_measure_text)
    SequentialProjection(
        WordWrapping(width=wrap_width),
        TextToGraphics(measure=measure),
    )
end
