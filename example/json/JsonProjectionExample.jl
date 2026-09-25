function make_json_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

# Console variant: the same pipeline as `make_json_projection_example` but
# **without** the trailing `TextToGraphics` step. It stops at the Text domain
# (`SyntaxToText` output, a `TextBlock`), which the `ConsoleBackend` renders to
# the terminal directly — colors and all. No `measure` is needed because no
# graphics layout happens.
#
# `WindowInputUnwrappingProjection` wraps the chain so the editor's `WindowInput`
# gesture is stripped to its inner event before the readers see it. The SDL
# pipeline gets that unwrapping from its `ScreenToScreen` window seam; this
# pipeline has no screen/window layer, so it supplies the seam directly. Without
# it, keyboard navigation produces no operations (the readers match on `KeyDown`,
# not on the wrapping window input).
function make_json_console_projection_example()
    WindowInputUnwrappingProjection(
        ChainingProjection(
            RecursiveProjection(JsonToSyntax()),
            RecursiveProjection(SyntaxToText()),
            # Bake the selection into the spans as inverse video so the dumb
            # console renderer shows it (no separate cursor/highlight layer).
            SelectionInverting(),
        )
    )
end

function make_json_sorted_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        SortingAtProjection((@reference ::ScreenDocument.windows::CellVector[1]::WindowDocument.content::JsonObject.entries::CellVector), x -> x.key),
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

function make_json_null_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        JsonNullToSyntaxLeaf(),
        SyntaxLeafToText(),
        TextToGraphics(measure=measure),
    )
end

function make_json_string_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        JsonStringToSyntaxLeaf(),
        SyntaxLeafToText(),
        TextToGraphics(measure=measure),
    )
end
