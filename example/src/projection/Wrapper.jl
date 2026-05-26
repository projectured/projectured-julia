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

function make_workbench_projection(; measure=sdl_measure_text,
                                   content_projections=Pair{DataType,Any}[
                                       JsonDocument => SequentialProjection(RecursiveProjection(JsonToSyntax()), RecursiveProjection(SyntaxToText()), TextToGraphics(measure=measure)),
                                       XmlDocument  => SequentialProjection(RecursiveProjection(XmlToSyntax()), RecursiveProjection(SyntaxToText()), TextToGraphics(measure=measure)),
                                       TextDocument => TextToGraphics(measure=measure),
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
