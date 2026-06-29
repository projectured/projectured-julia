function make_graphics_caching(projection; render=render_canvas)
    SequentialProjection(projection, RecursiveProjection(GraphicsCaching(render=render)))
end

function make_scrolling_projection(projection; measure=truetype_measure_text,
                                    font=font_ubuntu_monospace_regular_24)
    NestingProjection(
        WidgetScrollPaneToGraphicsViewport(font, measure);
        recursion=projection,
    )
end

function make_introspection_projection(projection; measure=truetype_measure_text)
    font = font_ubuntu_monospace_regular_24
    fg   = (0xee, 0xee, 0xee, 0xff)
    w2g  = WidgetToGraphics(font; measure=measure)
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

# Stack the clipboard projection on top of an arbitrary example projection. The
# clipboard projection exposes the active child (the wrapped content, or the stored
# slice) directly; the dispatcher routes that child's type to `Any =>
# NestingProjection(projection)`, which renders it to graphics through the example's
# own complete pipeline (the introspection wrapper pattern). So, unlike the
# hand-written `make_clipboard_projection_example`, no JSON-specific downstream
# stages are needed here — the inner projection already goes all the way to graphics.
#
# `to_text`/`from_text` are the optional OS-clipboard converters; they default to
# `nothing` (OS bridge off), because pasting OS text into an arbitrary domain is not
# generally type-safe. A caller that knows the wrapped domain accepts the converted
# node can opt in. `collection=true` uses the elements view instead of a slice.
function make_clipboard_projection(projection; collection=false,
                                   to_text=nothing, from_text=nothing)
    clip = collection ?
        ClipboardCollectionToAnyProjection() :
        ClipboardSliceToAnyProjection(; to_text=to_text, from_text=from_text)
    RecursiveProjection(TypeDispatchingProjection(Pair{DataType,Any}[
        (collection ? ClipboardCollection : ClipboardSlice) => clip,
        Any => NestingProjection(projection; recursion=PreservingProjection()),
    ]))
end

# Wrap a Text→Text projection (TextHighlighting / TextFiltering) in a
# ProjectionConfiguringProjection so a control bar for its parameters stacks
# above the projected text, then render the resulting widget+text tree. The
# combined renderer dispatches widget nodes through WidgetToGraphics and the
# projected `TextText` slot through TextToGraphics — the introspection pattern.
# Expects a TextText document (the text examples).
function make_text_configuring_projection(inner_text_projection;
                                          measure=truetype_measure_text,
                                          font=font_ubuntu_monospace_regular_24)
    fg  = (0x22, 0x22, 0x22, 0xff)   # dark text for the light example background
    w2g = WidgetToGraphics(font; measure=measure)
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

function make_workbench_projection(; measure=truetype_measure_text,
                                   content_projections=Pair{DataType,Any}[
                                       JsonDocument         => SequentialProjection(RecursiveProjection(JsonToSyntax()), RecursiveProjection(SyntaxToText()), WordWrapping(measure=measure), TextToGraphics(measure=measure)),
                                       XmlDocument          => SequentialProjection(RecursiveProjection(XmlToSyntax()), RecursiveProjection(SyntaxToText()), WordWrapping(measure=measure), TextToGraphics(measure=measure)),
                                       TextDocument         => SequentialProjection(WordWrapping(measure=measure), TextToGraphics(measure=measure)),
                                       # Assistant panel: composer input + widget chat history.
                                       conversation_draft_entry(measure=measure),
                                       conversation_widget_entry(measure=measure),
                                       PrimitiveDocument    => SequentialProjection(RecursiveProjection(PrimitiveToSyntax()), RecursiveProjection(SyntaxToText()), WordWrapping(measure=measure), TextToGraphics(measure=measure)),
                                   ])
    # `NaturalToGraphics` provides the widget/layout/Any rendering; the caller's
    # `content_projections` are passed as `extra` (matched first, so they win).
    SequentialProjection(
        RecursiveProjection(WorkbenchToWidget()),
        NaturalToGraphics(measure=measure, extra=content_projections),
    )
end
