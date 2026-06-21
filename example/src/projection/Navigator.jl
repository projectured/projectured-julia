function make_navigator_projection_example(; measure=truetype_measure_text)
    SequentialProjection(
        RecursiveProjection(WorkspaceToFileSystem()),
        RecursiveProjection(FileSystemToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
