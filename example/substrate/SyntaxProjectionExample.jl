function make_syntax_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        RecursiveProjection(SyntaxToText(
            expanded_marker  = TextString("▾", font_dejavu_monospace_regular_20, color_default),
            collapsed_marker = TextString("▸", font_dejavu_monospace_regular_20, color_default))),
        TextToGraphics(measure=measure),
    )
end
