
function make_workbench_projection_example(; measure=truetype_measure_text)
    font = font_ubuntu_regular_24
    # Dark text for the assistant input: the SDL backend renders on a light
    # (cream) background, so the pale `#eeeeee` that suits a dark theme is
    # almost invisible here. Keep it dark enough to read against the light
    # input surface (cf. make_assistant_projection_example).
    fg   = StyleColor(0x22/255, 0x22/255, 0x22/255, 1.0)
    # Dimmed gray for the empty assistant-input "type message here" placeholder.
    hint = StyleColor(0x88/255, 0x88/255, 0x88/255, 1.0)
    w2g  = WidgetToGraphics(font; measure=measure)
    text_to_graphics = SequentialProjection(WordWrapping(measure=measure), TextToGraphics(measure=measure))
    text_to_graphics_no_wrap = TextToGraphics(measure=measure)
    object_chain = SequentialProjection(
        RecursiveProjection(ObjectToSyntax()),
        RecursiveProjection(SyntaxToText()),
        text_to_graphics,
    )
    combined_w2g = RecursiveProjection(TypeDispatchingProjection(vcat(
        # Layout dispatch first: the WidgetTable renderer builds a GridLayout and
        # recurses it through this same dispatcher, so GridLayout must be routable.
        LayoutToGraphics().dispatch,
        w2g.dispatch,
        Pair{DataType,Any}[
            BookDocument          => SequentialProjection(RecursiveProjection(BookToSyntax()), RecursiveProjection(SyntaxToText()), text_to_graphics),
            # JSON/XML are structured code: word-wrapping at arbitrary space
            # boundaries ignores their syntax, so render them no-wrap (the scroll
            # pane handles overflow) like the file tree below.
            JsonDocument          => SequentialProjection(RecursiveProjection(JsonToSyntax()), RecursiveProjection(SyntaxToText()), text_to_graphics_no_wrap),
            XmlDocument           => SequentialProjection(RecursiveProjection(XmlToSyntax()), RecursiveProjection(SyntaxToText()), text_to_graphics_no_wrap),
            TextDocument          => text_to_graphics,
            JuliaDocument         => make_julia_projection_example(measure=measure),
            ListNode              => make_lazy_projection_example(measure=measure),
            CellVector            => make_collection_projection_example(measure=measure),
            # Assistant input → text directly (no SyntaxLeaf → no quotes), with a
            # pale "type message here" hint when empty. It is the only
            # PrimitiveString rendered through this entry.
            PrimitiveDocument     => SequentialProjection(RecursiveProjection(PrimitiveToText(string_kw=(style=StyleText(font_ubuntu_monospace_regular_24, fg), placeholder="type message here", placeholder_style=StyleText(font_ubuntu_monospace_regular_24, hint)))), text_to_graphics),
            # Assistant panel: composer input (draft) + widget chat-bubble history.
            # ConversationDraft precedes ConversationDocument (its subtype).
            conversation_draft_entry(measure=measure),
            conversation_widget_entry(measure=measure),
            WorkspaceDocument     => SequentialProjection(RecursiveProjection(WorkspaceToFileSystem()), RecursiveProjection(FileSystemToSyntax()), RecursiveProjection(SyntaxToText()), text_to_graphics_no_wrap),
            FileSystemDocument    => SequentialProjection(RecursiveProjection(FileSystemToSyntax()), RecursiveProjection(SyntaxToText()), text_to_graphics_no_wrap),
            EditorIntrospection   => object_chain,
        ],
    )))
    SequentialProjection(RecursiveProjection(WorkbenchToWidget()), combined_w2g)
end
