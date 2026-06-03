function make_text_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        WordWrapping(measure=measure),
        TextToGraphics(measure=measure),
    )
end
