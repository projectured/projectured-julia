# Fragment of `WidgetModule`.
#
# Projects a bare `ObjectField` — one field of one object, placed where a document
# goes and not in the value slot of a widget — to the widget that edits it. A bare
# field sits in a layout, in a card, or in a document that nobody builds by hand,
# such as a markdown document whose reader makes `ObjectField` nodes.
#
# # The widget
#
# `make_widget` makes the widget from the field; its default is the seam
# `make_object_field_widget`, which picks it by the type of the value:
#
#     Bool             → WidgetCheckbox(field)
#     String / number  → WidgetText(field)
#     anything else    → a WidgetLabel that shows the text of the value
#
# The editable widget holds the field in its value slot, and this projection
# prints it through the recursion. The table of `make_object_field_widget_dispatch`
# nests each value widget with `ObjectFieldToValue`, so the widget reads the
# value from the field and asks the field for the operation that stores a new
# value. That table also holds the row of this projection, so a bare field and a
# field in a slot can not make each other without end.
#
# The widget is made once, from the value at print time. A value that changes
# its type after the print keeps the old widget, and the widget keeps its
# identity, and with it the caret, across an ordinary edit.
#
# # Why a bare control and not a labelled row
#
# A `GridLayout` takes a flat child list, so a label and its control must be two
# separate children. A projection that emitted both could never place them in
# different columns. The caller writes the label:
#
#     FormLayout([
#         (WidgetLabel("Server name"), ObjectField(server, "name")),
#         (WidgetLabel("Client name"), ObjectField(client, "name")),
#     ])
#
# # The caret
#
# The widget is made here and is no part of the document, so no path from the
# root reaches it. A caret in it names a position in a rendering of the field,
# which the defaults of `Projection` keep in the field as a path that this
# projection introduces. The selection and the mouse target of the widget read
# that path back, so the caret sits where the person put it.

"""
    make_object_field_widget(field::ObjectField) -> widget

The widget that edits `field` when no other is chosen, picked by the type of the
value at the time of the call: a `WidgetCheckbox` for a `Bool`, a `WidgetText` for
a string or a number, each with the field in its value slot, and a `WidgetLabel`
that shows the text of the value for any other value.

A domain adds a method for the type of its values:

    make_object_field_widget(::Quantity, field) = WidgetSpinBox(field; min = 0, max = 100)

A form that chooses differently for one field passes `make_widget` to
`ObjectFieldToWidget` or `make_object_field_widget_dispatch`, and falls back to
this function for the others.
"""
make_object_field_widget(field::ObjectField) =
    make_object_field_widget(get_object_field_value(field), field)

make_object_field_widget(::Bool, field::ObjectField) = WidgetCheckbox(field)
make_object_field_widget(::Union{AbstractString, Real}, field::ObjectField) = WidgetText(field)

# A value that no control edits: its text, which follows a write of the field.
function make_object_field_widget(value, field::ObjectField)
    label = WidgetLabel(_as_string(value))
    set_cell_computation!(getfield(label, :content),
                          () -> _as_string(get_object_field_value(field)))
    label
end

"""
    ObjectFieldToWidgetIoMap(projection, input, output, widget_iomap)

`input` is the `ObjectField`; `widget_iomap` is the IO map of the widget that the
projection made and printed, and `output` is its output.
"""
@iomap struct ObjectFieldToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    widget_iomap::Any
end

"""
    ObjectFieldToWidget(; make_widget = make_object_field_widget)

The projection of a bare `ObjectField` to the widget that edits it. `make_widget`
makes the widget from the field. Put it in a table with
`make_object_field_widget_dispatch`, which nests the value widgets so that the
field in the slot of the widget gives a value.
"""
struct ObjectFieldToWidget <: Projection
    make_widget::Any
end

ObjectFieldToWidget(; make_widget = make_object_field_widget) = ObjectFieldToWidget(make_widget)

function print_document(p::ObjectFieldToWidget, recursion, field::ObjectField, ctx)
    widget = p.make_widget(field)
    _follow_object_field_paths!(p, widget, field)
    widget_iomap = print_child(recursion, widget, ctx)
    ObjectFieldToWidgetIoMap(p, field, Cell(@computation widget_iomap.output), widget_iomap)
end

# The selection and the mouse target of the made widget read the path that the
# field keeps for them, a path that this projection introduces.
function _follow_object_field_paths!(p::ObjectFieldToWidget, widget, field::ObjectField)
    hasfield(typeof(widget), :selection) &&
        set_cell_computation!(getfield(widget, :selection),
                              () -> _find_widget_path(p, field.selection))
    hasfield(typeof(widget), :mouse_target) &&
        set_cell_computation!(getfield(widget, :mouse_target),
                              () -> _find_widget_path(p, field.mouse_target))
    nothing
end

_find_widget_path(p::ObjectFieldToWidget, reference::Reference) = find_introduced_path(p, reference)
_find_widget_path(p::ObjectFieldToWidget, reference) = nothing

# The widget answers a gesture, and the defaults of `Projection` map its answer
# back into the field: a write that names the object of the field goes on as it
# is, and a path in the widget becomes a path that this projection introduces. An
# operation is an answer to map back, never a payload for the widget: the default
# maps each member of a compound through this reader again. The reader returns
# the operation and writes nothing (PAR-READER-IS-PURE).
function read_intent(p::ObjectFieldToWidget, iomap::ObjectFieldToWidgetIoMap, payload)
    payload isa Operation &&
        return invoke(read_intent, Tuple{Projection, Any, Any}, p, iomap, payload)
    child = iomap.widget_iomap
    answer = read_intent(child.projection, child, payload)
    answer === nothing ? nothing : read_intent(p, iomap, answer)
end
