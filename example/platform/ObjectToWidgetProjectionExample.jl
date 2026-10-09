# Project an object into an editable widget form: ObjectToWidget makes a labelled
# widget for each field (a text field, a checkbox), each holding an `ObjectField`
# of the object, and the renderer draws the form with the rows of a hand-laid form
# of fields. Editing a widget writes the field of the object.
make_object_to_widget_projection_example(; measure=FontFileMeasure()) =
    _make_object_form_chain(ObjectToWidget(); measure)

# The same form with widgets that `make_widget` chooses by the name of the field:
# a switch for the dark mode, spin boxes for the size of the window, and a toggle
# for whether it is shown. Every other field takes the default widget.
make_object_to_widget_chosen_widgets_projection_example(; measure=FontFileMeasure()) =
    _make_object_form_chain(ObjectToWidget(; make_widget = _choose_settings_widget); measure)

function _choose_settings_widget(field::ObjectField)
    name = get_object_field_name(field)
    name == "dark_mode" && return WidgetSwitch(; checked = field)
    name in ("width", "height") && return WidgetSpinBox(field; min = 100, max = 4000, step = 50)
    name == "visible" && return WidgetToggle("Shown"; pressed = field)
    make_object_field_widget(field)
end

# A form that opens a plain value: `is_record` opens a `PlainResolution`, which
# holds no cell, as well as every value that `is_form_record` opens. An edit of a
# field of the resolution writes a copy of it into the field of the document.
make_object_to_widget_plain_record_projection_example(; measure=FontFileMeasure()) =
    _make_object_form_chain(
        ObjectToWidget(; is_record = value -> value isa PlainResolution || is_form_record(value));
        measure)

# `stage` makes the form, and the renderer draws it. The form is a GridLayout of
# widgets whose value slots hold fields, so the renderer dispatches layout nodes to
# LayoutToGraphics, and the widgets and their fields to the rows of
# `make_object_field_widget_dispatch`.
function _make_object_form_chain(stage; measure)
    w2g = WidgetToGraphics(StyleFont("Ubuntu Mono", 20); measure=measure)
    ChainingProjection(
        stage,
        RecursiveProjection(TypeDispatchingProjection(vcat(
            LayoutToGraphics().dispatch,
            make_object_field_widget_dispatch(w2g.dispatch),
            Pair{Type,Any}[
                TextBlock => TextToGraphics(measure=measure),
            ],
        ))),
    )
end
