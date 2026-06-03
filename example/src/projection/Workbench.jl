
function make_workbench_projection_example(; measure=sdl_measure_text)
    font = font_ubuntu_regular_24
    fg   = (0xee, 0xee, 0xee, 0xff)
    w2g  = WidgetToGraphics(font; measure=measure, default_fg=fg)
    text_to_graphics = SequentialProjection(WordWrapping(measure=measure), TextToGraphics(measure=measure))
    object_chain = SequentialProjection(
        RecursiveProjection(ObjectToSyntax()),
        RecursiveProjection(SyntaxToText()),
        text_to_graphics,
    )
    combined_w2g = RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{DataType,Any}[
            BookDocument          => SequentialProjection(RecursiveProjection(BookToSyntax()), RecursiveProjection(SyntaxToText()), text_to_graphics),
            JsonDocument          => SequentialProjection(RecursiveProjection(JsonToSyntax()), RecursiveProjection(SyntaxToText()), text_to_graphics),
            XmlDocument           => SequentialProjection(RecursiveProjection(XmlToSyntax()), RecursiveProjection(SyntaxToText()), text_to_graphics),
            TextDocument          => text_to_graphics,
            JuliaDocument         => make_julia_projection_example(measure=measure),
            TableDocument         => make_table_projection_example(measure=measure),
            ListNode              => make_lazy_projection_example(measure=measure),
            CellVector            => make_collection_projection_example(measure=measure),
            PrimitiveDocument     => SequentialProjection(RecursiveProjection(PrimitiveToSyntax()), RecursiveProjection(SyntaxToText()), text_to_graphics),
            ConversationDocument  => SequentialProjection(RecursiveProjection(ConversationToSyntax()), RecursiveProjection(SyntaxToText(indent_size=0)), text_to_graphics),
            WorkspaceDocument     => SequentialProjection(RecursiveProjection(WorkspaceToFileSystem()), RecursiveProjection(FileSystemToSyntax()), RecursiveProjection(SyntaxToText()), text_to_graphics),
            FileSystemDocument    => SequentialProjection(RecursiveProjection(FileSystemToSyntax()), RecursiveProjection(SyntaxToText()), text_to_graphics),
            EditorIntrospection   => object_chain,
        ],
    )))
    SequentialProjection(RecursiveProjection(WorkbenchToWidget()), combined_w2g)
end
