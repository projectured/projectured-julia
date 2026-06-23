# Table examples render a `WidgetTable` (the single table abstraction). The
# renderer delegates positioning to a GridLayout and recurses each cell document
# through the projection, so the recursion must dispatch:
#   - WidgetTable / WidgetLabel  → WidgetToGraphics
#   - GridLayout (+ other layouts) → LayoutToGraphics
#   - the cell domain (JSON / Math primitives) → its own ToGraphics chain
# A single RecursiveProjection(TypeDispatchingProjection(...)) ties them together.

# A JSON cell renders through Json → Syntax → Text → Graphics.
_json_cell_projection(; measure=truetype_measure_text) = SequentialProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure=measure),
)

function make_table_projection_example(; measure=truetype_measure_text)
    w2g  = WidgetToGraphics(font_ubuntu_regular_24; measure=measure)
    json = _json_cell_projection(measure=measure)
    RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        w2g.dispatch,
        Pair{Type,Any}[
            JsonDocument => json,
        ],
    )))
end

function make_math_table_projection_example(; measure=truetype_measure_text)
    w2g = WidgetToGraphics(font_ubuntu_regular_24; measure=measure)
    primitive_chain = SequentialProjection(
        RecursiveProjection(PrimitiveToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
    math_chain = SequentialProjection(
        RecursiveProjection(MathToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
    RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        w2g.dispatch,
        Pair{Type,Any}[
            PrimitiveDocument => primitive_chain,
            MathDocument      => math_chain,
        ],
    )))
end
