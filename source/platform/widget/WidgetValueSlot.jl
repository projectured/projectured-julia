# Fragment of `WidgetModule` — the value slot of a widget.
#
# A value widget, such as a checkbox or a slider, holds the value that it shows in
# one slot. The slot holds a plain value, which the widget reads and writes
# itself, or a document, such as an `ObjectField`, which the widget prints as the
# child of the slot. The widget then reads the value from the output of the
# child, and asks the reader of the child for the operation that stores each new
# value that it offers or that a person enters. The widget decides how a person
# sees and picks a value; the child decides how a value is read and stored, and
# knows nothing about the widget.
#
# The widget prints the child through the recursion that it gets. A table that
# `make_object_field_widget_dispatch` makes gives each value widget a
# `NestingProjection` whose inner element prints that child, so an `ObjectField`
# in a slot gives a value, while the outer recursion keeps its own row for an
# `ObjectField` anywhere else. A value widget whose row is no such nesting must
# not hold a document in its slot when the outer recursion makes a widget of that
# document: the print would make the widget again, without end.

"""
    WidgetValueIoMap(projection, input, output, value_iomap)

The IO map of a value widget. `value_iomap` is the IO map of the document in the
value slot, printed as the child of the slot, or `nothing` when the slot holds a
plain value. It is no child IO map of the drawing, so a walk of the drawing does
not see it.
"""
@iomap struct WidgetValueIoMap
    projection::Any
    input::Any
    output::Any
    value_iomap::Any
end

# The child of the value slot `name` of `w`: a cell that holds the IO map of the
# document in the slot, reprinted when the slot gets another document, or
# `nothing` when the slot holds a plain value when the widget prints.
function _print_value_slot(recursion, w, name::Symbol, ctx)
    getproperty(w, name) isa Document || return nothing
    child_ctx = ctx === nothing ? nothing : make_child_context(ctx, FieldReferenceStep(String(name)))
    make_reconciled_child_iomap_cell(() -> getproperty(w, name),
                                     value -> print_child(recursion, value, child_ctx))
end

# The IO map of the child that `_print_value_slot` keeps, or `nothing`.
_get_slot_child(slot::Nothing) = nothing
_get_slot_child(slot) = slot[]

# The value that the slot `name` of `w` shows: the output of `child`, the IO map
# of the document in the slot, or the plain value when there is no child. Read
# inside a computation, it follows a write of either.
_get_slot_value(w, name::Symbol, child) =
    child === nothing ? getproperty(w, name) : child.output

"""
    make_slot_store_operation(widget, slot::Symbol, value_iomap, value) -> operation or nothing

The operation that stores `value` in the value slot `slot` of `widget`.

With no child (`value_iomap === nothing`), the slot holds a plain value, and the
answer writes the widget itself: `ReplaceReferencedValueOperation(widget, slot,
value)`. With a child, the answer is what the reader of the child gives for "replace
your output with `value`", for an `ObjectField` a write on the field. A child
whose answer still names a place in its own output takes no such value, and the
answer is `nothing`: the kernel would read that place as the root of the editor.
"""
function make_slot_store_operation(widget, slot::Symbol, value_iomap, value)
    value_iomap === nothing &&
        return ReplaceReferencedValueOperation(widget, String(slot), value)
    answer = read_intent(value_iomap.projection, value_iomap,
                         ReplaceReferencedValueOperation(nothing, EmptyReference(), value))
    _is_child_place_write(answer) ? nothing : answer
end

# The operation that stores a value in the slot of the widget of `iomap`.
make_slot_store_operation(iomap::WidgetValueIoMap, slot::Symbol, value) =
    make_slot_store_operation(iomap.input, slot, iomap.value_iomap, value)

_is_child_place_write(operation::ReplaceReferencedValueOperation) = operation.document === nothing
_is_child_place_write(operation) = false

# ── The table ──────────────────────────────────────────────────────────────

# The widgets with a value slot: `content` of a checkbox and of a text, `checked`
# of a switch, `pressed` of a toggle, `selected` of a radio group, and `value` of
# the others.
const _VALUE_WIDGET_TYPES = (WidgetCheckbox, WidgetSwitch, WidgetToggle, WidgetSlider,
                             WidgetSpinBox, WidgetRadioGroup, WidgetSelect, WidgetText)

"""
    make_object_field_widget_dispatch(dispatch) -> Vector{Pair{Type,Any}}

The rows of `dispatch`, a table of widget projections such as
`WidgetToGraphics(font).dispatch`, with the row of each value widget nested so
that a document in its value slot prints through `ObjectFieldToValue`:

    WidgetCheckbox => NestingProjection(WidgetCheckboxToGraphicsCanvas(...), ObjectFieldToValue())

The content of a `WidgetText` can also be a document that it draws, such as a
`TextBlock`, so its inner element sends any document other than an `ObjectField`
back into the outer recursion. The rows of the other widgets stay as they are.
"""
make_object_field_widget_dispatch(dispatch) =
    Pair{Type,Any}[type => _nest_value_widget(type, projection) for (type, projection) in dispatch]

function _nest_value_widget(type, projection)
    any(value_type -> value_type === type, _VALUE_WIDGET_TYPES) || return projection
    type === WidgetText || return NestingProjection(projection, ObjectFieldToValue())
    NestingProjection(projection,
                      TypeDispatchingProjection(ObjectField => ObjectFieldToValue(),
                                                Any         => NestingProjection()))
end
