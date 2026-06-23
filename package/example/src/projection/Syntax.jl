function make_syntax_projection_example(; measure=truetype_measure_text)
    SequentialProjection(
        RecursiveProjection(SyntaxToText(
            expanded_marker  = TextString("▾", font_dejavu_monospace_regular_24, color_default),
            collapsed_marker = TextString("▸", font_dejavu_monospace_regular_24, color_default))),
        TextToGraphics(measure=measure),
    )
end
