# The form is one recursion that draws it. The table of
# `make_object_field_widget_dispatch` holds the row of a bare `ObjectField`, which
# makes the widget for the type of its value with the field in its value slot,
# and nests each value widget, so the widget reads the value from the field and
# asks the field for the operation that stores a new value. The labels and the
# layout are drawn as they are.
function make_object_field_form_projection_example(; measure=FontFileMeasure())
    font = StyleFont("Ubuntu Mono", 20)
    w2g  = WidgetToGraphics(font; measure=measure)
    RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        make_object_field_widget_dispatch(w2g.dispatch),
        Pair{Type,Any}[
            TextBlock => TextToGraphics(measure=measure),
        ],
    )))
end

# The same form of bare fields, with widgets that the table chooses: the
# capacity is a spin box and the flag a switch, and every other field takes the
# default widget of `make_object_field_widget`.
function make_object_field_form_chosen_widgets_projection_example(; measure=FontFileMeasure())
    choose(field) = get_object_field_name(field) == "capacity" ? WidgetSpinBox(field; min = 1, max = 16) :
                    get_object_field_name(field) == "enabled"  ? WidgetSwitch(; checked = field) :
                    make_object_field_widget(field)
    w2g = WidgetToGraphics(StyleFont("Ubuntu Mono", 20); measure=measure)
    RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        make_object_field_widget_dispatch(w2g.dispatch; make_widget = choose),
        Pair{Type,Any}[TextBlock => TextToGraphics(measure=measure)],
    )))
end

# One field to syntax and on to graphics. The `ObjectField` entry stands in front
# of `ObjectToSyntax`'s own table, so the field is named rather than reflected:
# without it the `Any` row would dispatch to `ObjectNodeToSyntaxNode` and dump the
# whole object and its reference path.
function make_object_field_syntax_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(vcat(
            Pair{Type,Any}[ObjectField => ObjectFieldToSyntax()],
            ObjectToSyntax(open_delimiter="{", close_delimiter="}").dispatch,
        ))),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
