function make_graphics_caching(projection; render=render_canvas)
    ChainingProjection(projection, RecursiveProjection(GraphicsCaching(render=render)))
end

function make_scrolling_projection(projection; measure=FontFileMeasure(),
                                    font=StyleFont("Ubuntu Mono", 20))
    theme = make_widget_theme(font = font)
    NestingProjection(
        WidgetScrollPaneToGraphicsCanvas(theme; measure = measure, font = font, content_color = color_transparent);
        recursion=projection,
    )
end

# Apply DraggingProjection at the DraggingState wrapper and hand the inner
# `content` to the example's own projection — the `make_scrolling_projection`
# shape. The dragging printer is transparent, so the content renders as usual;
# its reader turns press → drag → drop into a MoveRangeOperation. This pairs
# `make_dragging_document` with `make_dragging_projection`, both
# `ProjecturedPlatform`'s; the domain-specific twin,
# `make_dragging_projection_example`, is this package's own — see
# `GalleryWrapperDocumentExample.jl`.

# Render a WidgetShell and the content it frames: the shell's own bands are
# widgets, and the content slot defers to the example's projection. This is the
# introspection dispatch, with a shell in place of the tabbed pane. Pairs with
# `make_shell_document`.
function make_shell_projection(projection; measure=FontFileMeasure(),
                               font=StyleFont("Ubuntu", 20))
    w2g = WidgetToGraphics(font; measure=measure)
    RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{Type,Any}[
            Any => NestingProjection(projection; recursion=IdentityProjection()),
        ],
    )))
end

# Wrap a pipeline in the command type-in overlay: Ctrl+Shift+P opens a field over
# the content that runs a named operation on it.
#
# Each call mints its own `CommandPaletteState`, so every window gets its own
# palette. The help window is a *sibling window* and can share one flag across
# windows; the palette is drawn INTO its window, so a shared flag would draw it
# over every window at once.
make_command_palette_decorator_projection(projection; measure=FontFileMeasure()) =
    CommandPaletteDecoratorProjection(inner = projection, measure = measure)

function make_introspection_projection(projection; measure=FontFileMeasure())
    font = StyleFont("Ubuntu Mono", 20)
    fg   = (0xee, 0xee, 0xee, 0xff)
    w2g  = WidgetToGraphics(font; measure=measure)
    object_chain = ChainingProjection(
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
        Pair{Type,Any}[
            EditorIntrospection => object_chain,
            Any                 => NestingProjection(projection; recursion=IdentityProjection()),
        ],
    )))
end

# Wrap a Text→Text projection (TextHighlighting / TextFiltering) in a
# ProjectionConfiguringProjection so a control bar for its parameters stacks
# above the projected text, then render the resulting widget+text tree. The
# combined renderer dispatches widget nodes through WidgetToGraphics and the
# projected `TextBlock` slot through TextToGraphics — the introspection pattern.
# Expects a TextBlock document (the text examples).
function make_text_configuring_projection(inner_text_projection;
                                          measure=FontFileMeasure(),
                                          font=StyleFont("Ubuntu Mono", 20))
    fg  = (0x22, 0x22, 0x22, 0xff)   # dark text for the light example background
    w2g = WidgetToGraphics(font; measure=measure)
    renderer = RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{Type,Any}[
            TextBlock => TextToGraphics(measure=measure),
        ],
    )))
    ChainingProjection(
        ProjectionConfiguringProjection(inner=inner_text_projection),
        renderer,
    )
end
