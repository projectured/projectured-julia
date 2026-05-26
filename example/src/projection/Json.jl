function make_json_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

function make_json_sorted_projection_example(; measure=sdl_measure_text)
    # Projection that sorts top-level JSON object entries by key
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
