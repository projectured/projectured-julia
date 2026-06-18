function make_text_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        WordWrapping(measure=measure),
        TextToGraphics(measure=measure),
    )
end

# No word wrapping: lay the text out straight through `TextToGraphics`. Paired
# with `make_plain_text_document_example`, this is the minimal flat-text
# pipeline used to watch the renderer's dirty rectangle on caret moves.
function make_plain_text_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        TextToGraphics(measure=measure),
    )
end
