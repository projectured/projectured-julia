function make_json_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

# Console variant: the same pipeline as `make_json_projection_example` but
# **without** the trailing `TextToGraphics` step. It stops at the Text domain
# (`SyntaxToText` output, a `TextText`), which the `ConsoleBackend` renders to
# the terminal directly — colors and all. No `measure` is needed because no
# graphics layout happens.
#
# `EnvelopeUnwrappingProjection` wraps the chain so the editor's `EventEnvelope`
# gesture is stripped to its inner event before the readers see it. The SDL
# pipeline gets that unwrapping from its `ScreenToScreen` window seam; this
# pipeline has no screen/window layer, so it supplies the seam directly. Without
# it, keyboard navigation produces no operations (the readers match on `KeyDown`,
# not on the wrapping envelope).
function make_json_console_projection_example()
    EnvelopeUnwrappingProjection(
        SequentialProjection(
            RecursiveProjection(JsonToSyntax()),
            RecursiveProjection(SyntaxToText()),
            # Bake the selection into the spans as inverse video so the dumb
            # console renderer shows it (no separate cursor/highlight layer).
            SelectionInverting(),
        )
    )
end

function make_json_sorted_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        SortingAtProjection(@reference(entries), x -> x.key),
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

function make_json_null_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        JsonNullToSyntaxLeaf(),
        SyntaxLeafToText(),
        TextToGraphics(measure=measure),
    )
end

function make_json_string_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        JsonStringToSyntaxLeaf(),
        SyntaxLeafToText(),
        TextToGraphics(measure=measure),
    )
end
