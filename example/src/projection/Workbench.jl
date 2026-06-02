
function make_workbench_projection_example(; measure=sdl_measure_text)
    font = font_ubuntu_regular_24
    fg   = (0xee, 0xee, 0xee, 0xff)
    w2g  = WidgetToGraphics(font; measure=measure, default_fg=fg)
    combined_w2g = RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{DataType,Any}[
            BookDocument          => SequentialProjection(RecursiveProjection(BookToSyntax()), RecursiveProjection(SyntaxToText()), TextToGraphics(measure=measure)),
            JsonDocument          => SequentialProjection(RecursiveProjection(JsonToSyntax()), RecursiveProjection(SyntaxToText()), TextToGraphics(measure=measure)),
            XmlDocument           => SequentialProjection(RecursiveProjection(XmlToSyntax()), RecursiveProjection(SyntaxToText()), TextToGraphics(measure=measure)),
            TextDocument          => TextToGraphics(measure=measure),
            JuliaDocument         => make_julia_projection_example(measure=measure),
            TableDocument         => make_table_projection_example(measure=measure),
            ListNode              => make_lazy_projection_example(measure=measure),
            CellVector            => make_collection_projection_example(measure=measure),
            PrimitiveDocument     => SequentialProjection(RecursiveProjection(PrimitiveToSyntax()), RecursiveProjection(SyntaxToText()), TextToGraphics(measure=measure)),
            ConversationDocument  => SequentialProjection(RecursiveProjection(ConversationToSyntax()), RecursiveProjection(SyntaxToText(indent_size=0)), TextToGraphics(measure=measure)),
            WorkspaceDocument     => SequentialProjection(RecursiveProjection(WorkspaceToFileSystem()), RecursiveProjection(FileSystemToSyntax()), RecursiveProjection(SyntaxToText()), TextToGraphics(measure=measure)),
            FileSystemDocument    => SequentialProjection(RecursiveProjection(FileSystemToSyntax()), RecursiveProjection(SyntaxToText()), TextToGraphics(measure=measure)),
        ],
    )))
    SequentialProjection(RecursiveProjection(WorkbenchToWidget()), combined_w2g)
end
