function make_navigator_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(WorkspaceToFileSystem()),
        RecursiveProjection(FileSystemToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
