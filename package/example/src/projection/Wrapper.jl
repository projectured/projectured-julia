function make_graphics_caching(projection; render=render_canvas)
    ChainingProjection(projection, RecursiveProjection(GraphicsCaching(render=render)))
end

function make_scrolling_projection(projection; measure=truetype_measure_text,
                                    font=font_ubuntu_monospace_regular_20)
    NestingProjection(
        WidgetScrollPaneToGraphicsViewport(font, measure);
        recursion=projection,
    )
end

function make_introspection_projection(projection; measure=truetype_measure_text)
    font = font_ubuntu_monospace_regular_20
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

# Stack the clipboard projection on top of an arbitrary example projection, as a
# two-stage ChainingProjection (mirroring the hand-written
# `make_clipboard_projection_example`, but domain-generic):
#
#   stage 1: the clipboard dispatcher exposes the *active child document* (the
#            wrapped content, or the stored slice once toggled) unchanged — its `Any`
#            branch is a IdentityProjection, so the recursion just hands the child
#            document back.
#   stage 2: the example's own projection (isolated in a NestingProjection) renders
#            that document all the way to graphics.
#
# Why not collapse to a single RecursiveProjection that renders to graphics inside
# the clipboard's `Any` branch? Because `ClipboardSliceToAnyProjection.output` is a
# reactive `Cell` (it has to be, so the display toggle propagates without dropping
# `editor.iomap`). A ChainingProjection de-references a stage's cell-valued output
# before feeding the next stage, but the *last* stage's output is returned raw — so a
# clipboard projection used as the outermost stage would leak a `Cell` to the
# backend (which expects a `GraphicsCanvas`). Keeping the example projection as a
# trailing stage both renders to graphics and forces that de-reference.
#
# `to_text`/`from_text` are the optional OS-clipboard converters; they default to
# `nothing` (OS bridge off), because pasting OS text into an arbitrary domain is not
# generally type-safe. A caller that knows the wrapped domain accepts the converted
# node can opt in. `collection=true` uses the elements view instead of a slice (the
# collection display mode exposes a CellVector, which only the matching example
# projection can render — slice mode is the general case).
function make_clipboard_projection(projection; collection=false,
                                   to_text=nothing, from_text=nothing, text=false)
    clip = collection ?
        ClipboardCollectionToAnyProjection() :
        ClipboardSliceToAnyProjection(; to_text=to_text, from_text=from_text, text=text)
    ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
            (collection ? ClipboardCollection : ClipboardSlice) => clip,
            Any => IdentityProjection(),
        ])),
        NestingProjection(projection; recursion=IdentityProjection()),
    )
end

# Wrap a Text→Text projection (TextHighlighting / TextFiltering) in a
# ProjectionConfiguringProjection so a control bar for its parameters stacks
# above the projected text, then render the resulting widget+text tree. The
# combined renderer dispatches widget nodes through WidgetToGraphics and the
# projected `TextText` slot through TextToGraphics — the introspection pattern.
# Expects a TextText document (the text examples).
function make_text_configuring_projection(inner_text_projection;
                                          measure=truetype_measure_text,
                                          font=font_ubuntu_monospace_regular_20)
    fg  = (0x22, 0x22, 0x22, 0xff)   # dark text for the light example background
    w2g = WidgetToGraphics(font; measure=measure)
    renderer = RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{Type,Any}[
            TextText => TextToGraphics(measure=measure),
        ],
    )))
    ChainingProjection(
        ProjectionConfiguringProjection(inner=inner_text_projection),
        renderer,
    )
end

function make_workbench_projection(; measure=truetype_measure_text,
                                   content_projections=Pair{Type,Any}[
                                       JsonDocument         => ChainingProjection(RecursiveProjection(JsonToSyntax()), RecursiveProjection(SyntaxToText()), WordWrapping(measure=measure), TextToGraphics(measure=measure)),
                                       XmlDocument          => ChainingProjection(RecursiveProjection(XmlToSyntax()), RecursiveProjection(SyntaxToText()), WordWrapping(measure=measure), TextToGraphics(measure=measure)),
                                       JuliaDocument        => make_julia_projection_example(measure=measure),
                                       SqlDocument          => make_sql_syntax_projection_example(measure=measure),
                                       TextDocument         => ChainingProjection(WordWrapping(measure=measure), TextToGraphics(measure=measure)),
                                       # Navigator: render the workspace file system as a native WidgetTree
                                       # (icons, chevrons, selection band) — `Workspace → FileSystem →
                                       # WidgetTree → Graphics` — instead of the generic object projection.
                                       WorkspaceDocument    => ChainingProjection(RecursiveProjection(WorkspaceToFileSystem()), RecursiveProjection(FileSystemToWidget()), WidgetToGraphics(font_ubuntu_monospace_regular_20; measure=measure)),
                                       # Assistant panel: composer input + widget chat history.
                                       conversation_draft_entry(measure=measure),
                                       conversation_widget_entry(measure=measure),
                                       PrimitiveDocument    => ChainingProjection(RecursiveProjection(PrimitiveToSyntax()), RecursiveProjection(SyntaxToText()), WordWrapping(measure=measure), TextToGraphics(measure=measure)),
                                   ])
    # `NaturalToGraphics` provides the widget/layout/Any rendering; the caller's
    # `content_projections` are passed as `extra` (matched first, so they win).
    # The hover tracker wraps the whole pipeline so a hovered widget (e.g. a
    # navigator tree row) clears when the pointer leaves it — container hit-routing
    # only delivers a MouseMove to the child under the pointer, so the tracker is
    # what synthesises the MouseEnter/MouseLeave crossings (cf.
    # make_workbench_projection_example / make_widget_projection_example).
    WidgetHoverTrackingProjection(inner = ChainingProjection(
        RecursiveProjection(WorkbenchToWidget()),
        NaturalToGraphics(measure=measure, extra=content_projections),
    ))
end
