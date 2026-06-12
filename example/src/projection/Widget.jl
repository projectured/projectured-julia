
# The standard widget projection: recursively dispatches every widget node
# through WidgetToGraphics. The light theme drives all colors, radius and
# spacing — see WidgetTheme. Use this for every per-widget example whose content
# is a plain string (label, checkbox, button, menu, composite, panes, …).
function make_widget_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(WidgetToGraphics(font_ubuntu_regular_24; measure=measure)),
    )
end

# The editable-text widget projection. A WidgetText whose content is a TextText
# recurses that content through the Text domain, so the combined renderer must
# also dispatch TextText through TextToGraphics. All caret navigation / text
# editing then comes from TextToGraphics and the widget only maps the resulting
# references backward (see make_widget_text_document_example).
function make_widget_text_projection_example(; measure=sdl_measure_text)
    font = font_ubuntu_monospace_regular_24
    w2g  = WidgetToGraphics(font; measure=measure)
    RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{DataType,Any}[
            TextText => TextToGraphics(measure=measure),
        ],
    )))
end
