function make_graphics_caching(projection; render=sdl_render_canvas)
    SequentialProjection(projection, RecursiveProjection(GraphicsCaching(render=render)))
end

function make_scrolling_projection(projection; measure=sdl_measure_text,
                                    font=font_ubuntu_monospace_regular_24)
    NestingProjection(
        WidgetScrollPaneToGraphicsViewport(font, measure);
        recursion=projection,
    )
end

function make_introspection_projection(projection; measure=sdl_measure_text)
    font = font_ubuntu_monospace_regular_24
    fg   = (0xee, 0xee, 0xee, 0xff)
    w2g  = WidgetToGraphics(font; measure=measure, default_fg=fg)
    object_chain = SequentialProjection(
        RecursiveProjection(ObjectToSyntax()),
        RecursiveProjection(SyntaxToText()),
        WordWrapping(measure=measure),
        TextToGraphics(measure=measure),
    )
    # Dispatch: widget nodes render as widgets, EditorIntrospection wrappers
    # render via the generic object→syntax chain, and anything else (notably
    # the example's original document at the first tab) defers to the
    # wrapped projection. NestingProjection isolates that wrapped projection
    # so its own recursion machinery isn't disturbed.
    RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{DataType,Any}[
            EditorIntrospection => object_chain,
            Any                 => NestingProjection(projection; recursion=PreservingProjection()),
        ],
    )))
end

# Wrap a Text→Text projection (TextHighlighting / TextFiltering) in a
# ProjectionConfiguringProjection so a control bar for its parameters stacks
# above the projected text, then render the resulting widget+text tree. The
# combined renderer dispatches widget nodes through WidgetToGraphics and the
# projected `TextText` slot through TextToGraphics — the introspection pattern.
# Expects a TextText document (the text examples).
function make_text_configuring_projection(inner_text_projection;
                                          measure=sdl_measure_text,
                                          font=font_ubuntu_monospace_regular_24)
    fg  = (0x22, 0x22, 0x22, 0xff)   # dark text for the light example background
    w2g = WidgetToGraphics(font; measure=measure, default_fg=fg)
    renderer = RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{DataType,Any}[
            TextText => TextToGraphics(measure=measure),
        ],
    )))
    SequentialProjection(
        ProjectionConfiguringProjection(inner=inner_text_projection),
        renderer,
    )
end

function make_workbench_projection(; measure=sdl_measure_text,
                                   content_projections=Pair{DataType,Any}[
                                       JsonDocument         => SequentialProjection(RecursiveProjection(JsonToSyntax()), RecursiveProjection(SyntaxToText()), WordWrapping(measure=measure), TextToGraphics(measure=measure)),
                                       XmlDocument          => SequentialProjection(RecursiveProjection(XmlToSyntax()), RecursiveProjection(SyntaxToText()), WordWrapping(measure=measure), TextToGraphics(measure=measure)),
                                       TextDocument         => SequentialProjection(WordWrapping(measure=measure), TextToGraphics(measure=measure)),
                                       ConversationDocument => SequentialProjection(RecursiveProjection(ConversationToSyntax()), RecursiveProjection(SyntaxToText(indent_size=0)), WordWrapping(measure=measure), TextToGraphics(measure=measure)),
                                       PrimitiveDocument    => SequentialProjection(RecursiveProjection(PrimitiveToSyntax()), RecursiveProjection(SyntaxToText()), WordWrapping(measure=measure), TextToGraphics(measure=measure)),
                                   ])
    font = font_ubuntu_monospace_regular_24
    fg   = (0xee, 0xee, 0xee, 0xff)
    w2g  = WidgetToGraphics(font; measure=measure, default_fg=fg)
    combined_w2g = RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        content_projections,
    )))
    SequentialProjection(RecursiveProjection(WorkbenchToWidget()), combined_w2g)
end
