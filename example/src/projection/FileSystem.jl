function make_filesystem_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(FileSystemToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
