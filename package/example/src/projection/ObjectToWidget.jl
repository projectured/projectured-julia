# Project a plain object into an editable widget form: ObjectToWidget reflects
# its scalar Cell fields into labelled controls (text fields / checkboxes), then
# the combined renderer draws the widget tree (widgets via WidgetToGraphics, the
# editable text controls' TextText content via TextToGraphics). Editing a control
# writes back to the object's field cell.
function make_object_to_widget_projection_example(; measure=truetype_measure_text)
    font = font_ubuntu_monospace_regular_24
    fg   = (0x22, 0x22, 0x22, 0xff)
    w2g  = WidgetToGraphics(font; measure=measure)
    SequentialProjection(
        ObjectToWidget(style=StyleText(font, color_default)),
        # The form is a GridLayout of widgets, so the renderer dispatches layout
        # nodes to LayoutToGraphics, widgets to WidgetToGraphics, and the
        # editable controls' TextText content to TextToGraphics.
        RecursiveProjection(TypeDispatchingProjection(vcat(
            LayoutToGraphics().dispatch,
            w2g.dispatch,
            Pair{DataType,Any}[
                TextText => TextToGraphics(measure=measure),
            ],
        ))),
    )
end
