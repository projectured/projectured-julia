# Project an object into an editable widget form: ObjectToWidget makes a labelled
# widget for each field (a text field, a checkbox), each holding an `ObjectField`
# of the object, and the renderer draws the form with the rows of a hand-laid form
# of fields. Editing a widget writes the field of the object.
function make_object_to_widget_projection_example(; measure=FontFileMeasure())
    font = StyleFont("Ubuntu Mono", 20)
    w2g  = WidgetToGraphics(font; measure=measure)
    ChainingProjection(
        ObjectToWidget(),
        # The form is a GridLayout of widgets whose value slots hold fields, so the
        # renderer dispatches layout nodes to LayoutToGraphics, and the widgets and
        # their fields to the rows of `make_object_field_widget_dispatch`.
        RecursiveProjection(TypeDispatchingProjection(vcat(
            LayoutToGraphics().dispatch,
            make_object_field_widget_dispatch(w2g.dispatch),
            Pair{Type,Any}[
                TextBlock => TextToGraphics(measure=measure),
            ],
        ))),
    )
end
