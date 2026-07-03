function make_json_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
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
        ChainingProjection(
            RecursiveProjection(JsonToSyntax()),
            RecursiveProjection(SyntaxToText()),
            # Bake the selection into the spans as inverse video so the dumb
            # console renderer shows it (no separate cursor/highlight layer).
            SelectionInverting(),
        )
    )
end

# ── Widget-based pipeline: Domain → Syntax → Widget → Graphics ──────────────
#
# Shared final step for the widget path: a recursive dispatch that renders both
# the widget/layout chrome (WidgetToGraphics + the layout canvases) and the
# embedded `TextText` leaf content (TextToGraphics) in one pass — the
# widgets-for-structure / text-for-content composition (mirrors the
# conversation_widget inner dispatch).
function make_syntax_widget_graphics(; measure=truetype_measure_text)
    font = font_ubuntu_monospace_regular_20
    w2g  = WidgetToGraphics(font; measure=measure)
    RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{Type,Any}[
            HorizontalLayout => HorizontalLayoutToGraphicsCanvas(),
            VerticalLayout   => VerticalLayoutToGraphicsCanvas(),
            TextText         => TextToGraphics(measure=measure),
        ],
    )))
end

function make_json_widget_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToWidget()),
        make_syntax_widget_graphics(measure=measure),
    )
end

function make_json_sorted_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        SortingAtProjection(@reference(windows[1].content.entries), x -> x.key),
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

function make_json_null_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        JsonNullToSyntaxLeaf(),
        SyntaxLeafToText(),
        TextToGraphics(measure=measure),
    )
end

function make_json_string_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        JsonStringToSyntaxLeaf(),
        SyntaxLeafToText(),
        TextToGraphics(measure=measure),
    )
end
