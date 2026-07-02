
function make_workbench_projection_example(; measure=truetype_measure_text)
    font = font_ubuntu_regular_20
    # Dark text for the assistant input: the SDL backend renders on a light
    # (cream) background, so the pale `#eeeeee` that suits a dark theme is
    # almost invisible here. Keep it dark enough to read against the light
    # input surface (cf. make_assistant_projection_example).
    fg   = StyleColor(0x22/255, 0x22/255, 0x22/255, 1.0)
    # Dimmed gray for the empty assistant-input "type message here" placeholder.
    hint = StyleColor(0x88/255, 0x88/255, 0x88/255, 1.0)
    text_to_graphics = SequentialProjection(WordWrapping(measure=measure), TextToGraphics(measure=measure))
    object_chain = SequentialProjection(
        RecursiveProjection(ObjectToSyntax()),
        RecursiveProjection(SyntaxToText()),
        text_to_graphics,
    )
    # The content renderer is `NaturalToGraphics` (which already covers
    # JSON/XML/Text/FileSystem/Any and layouts/widgets), plus the workbench's
    # context-specific overrides. `extra` is matched first, so these win:
    renderer = NaturalToGraphics(measure=measure, font=font, extra=Pair{Type,Any}[
        # Book is prose-like → word-wrapped (the generic syntax path is no-wrap).
        BookDocument          => SequentialProjection(RecursiveProjection(BookToSyntax()), RecursiveProjection(SyntaxToText()), text_to_graphics),
        JuliaDocument         => make_julia_projection_example(measure=measure),
        # Lazy/possibly-infinite list — must use the lazy projection, not the
        # generic collection-as-stack.
        ListNode              => make_lazy_projection_example(measure=measure),
        # The collection demo (vs the generic CellVector→vertical-stack).
        CellVector            => make_collection_projection_example(measure=measure),
        # Assistant input → text directly (no SyntaxLeaf → no quotes), with a
        # pale "type message here" hint when empty.
        PrimitiveDocument     => SequentialProjection(RecursiveProjection(PrimitiveToText(string_kw=(style=StyleText(font_ubuntu_monospace_regular_20, fg), placeholder="type message here", placeholder_style=StyleText(font_ubuntu_monospace_regular_20, hint)))), text_to_graphics),
        # Assistant panel: composer input (draft) + widget chat-bubble history.
        # ConversationDraft precedes ConversationDocument (its subtype).
        conversation_draft_entry(measure=measure),
        conversation_widget_entry(measure=measure),
        # Navigator: render the workspace file system as a native WidgetTree
        # (icons, chevrons, selection band) — `Workspace → FileSystem →
        # WidgetTree → Graphics` — matching the real workbench projection
        # (make_workbench_projection) instead of the generic text tree.
        WorkspaceDocument     => SequentialProjection(RecursiveProjection(WorkspaceToFileSystem()), RecursiveProjection(FileSystemToWidget()), WidgetToGraphics(font_ubuntu_monospace_regular_20; measure=measure)),
        EditorIntrospection   => object_chain,
    ])
    SequentialProjection(RecursiveProjection(WorkbenchToWidget()), renderer)
end
