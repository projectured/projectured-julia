function make_ini_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(IniToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
