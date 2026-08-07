# The natural notation pipeline: the process/julia merged dispatch table through
# the shared Syntax → Text → Graphics tail every domain ends with.
function make_process_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        RecursiveProjection(ProcessToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
