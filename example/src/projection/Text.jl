function make_text_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        TextToGraphics(measure=measure),
    )
end
