function make_text_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        WordWrapping(measure=measure),
        TextToGraphics(measure=measure),
    )
end

# No word wrapping: lay the text out straight through `TextToGraphics`. Paired
# with `make_plain_text_document_example`, this is the minimal flat-text
# pipeline used to watch the renderer's dirty rectangle on caret moves.
function make_plain_text_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        TextToGraphics(measure=measure),
    )
end
