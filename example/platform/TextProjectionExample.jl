# Prose wraps at the edge of its range, and at 800 px at most, so a line stays
# short enough to read also where nothing gives an edge.
function make_text_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        WordWrapping(measure=measure, max_width=800),
        TextToGraphics(measure=measure),
    )
end

# No word wrapping: lay the text out straight through `TextToGraphics`. Paired
# with `make_plain_text_document_example`, this is the minimal flat-text
# pipeline used to watch the renderer's dirty rectangle on caret moves.
function make_plain_text_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        TextToGraphics(measure=measure),
    )
end
