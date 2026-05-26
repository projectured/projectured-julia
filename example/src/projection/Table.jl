function make_table_projection_example(; measure=sdl_measure_text)
    content_projection = SequentialProjection(
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
    NestingProjection(
        TableToGraphics();
        recursion=content_projection,
    )
end

function make_math_table_projection_example(; measure=sdl_measure_text)
    content_projection = SequentialProjection(
        TypeDispatchingProjection(
            PrimitiveDocument => RecursiveProjection(PrimitiveToSyntax()),
            MathDocument => RecursiveProjection(MathToSyntax()),
        ),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
    NestingProjection(
        TableToGraphics();
        recursion=content_projection,
    )
end
