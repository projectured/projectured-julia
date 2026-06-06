function make_filesystem_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(FileSystemToSyntax()),
        RecursiveProjection(SyntaxToText(
            expanded_marker  = TextString("▾", font_dejavu_monospace_regular_24, color_default),
            collapsed_marker = TextString("▸", font_dejavu_monospace_regular_24, color_default),
            marker_eligible  = filesystem_marker_eligible)),
        TextToGraphics(measure=measure),
    )
end
