
# The standard widget projection: recursively dispatches every widget node
# through WidgetToGraphics. Use this for every per-widget example whose content
# is a plain string (label, checkbox, button, menu, composite, panes, …).
function make_widget_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(WidgetToGraphics(font_ubuntu_regular_24;
                                             measure=measure,
                                             default_fg=(0xee, 0xee, 0xee, 0xff))),
    )
end

# The editable-text widget projection. A WidgetText whose content is a TextText
# recurses that content through the Text domain, so the combined renderer must
# also dispatch TextText through TextToGraphics. All caret navigation / text
# editing then comes from TextToGraphics and the widget only maps the resulting
# references backward (see make_widget_text_document_example).
function make_widget_text_projection_example(; measure=sdl_measure_text)
    font = font_ubuntu_monospace_regular_24
    fg   = (0x22, 0x22, 0x22, 0xff)   # dark text for the light example background
    w2g  = WidgetToGraphics(font; measure=measure, default_fg=fg)
    RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{DataType,Any}[
            TextText => TextToGraphics(measure=measure),
        ],
    )))
end
