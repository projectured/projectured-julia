# Fragment of `WidgetModule`.
#
# Projects an `ObjectField` in the value slot of a widget to the value that the
# field names, and reads a write of that whole value back as a write on the field.
# The widget reads the value from the output and asks the reader for the
# operation that stores a new value (`make_slot_store_operation`), so this
# projection knows nothing about the widget that holds the field.
#
# The output is a computed cell, so a reader of it follows a write on the field.
# A caret in the widget is a range in the text of the value, and the same range is
# a path in the document: `object.<path of the field>{start:stop}`
# (`make_object_field_range_reference`). The maps turn the one into the other, so
# a selection that a key or an operation writes into the field shows as the caret
# of the widget. Any other path goes as the defaults of `Projection` map it.

"""
    ObjectFieldToValue()

The projection of an `ObjectField` in the value slot of a widget: its output is the
value that the field names, and a write of the whole output is a write on the
field, with the value converted to the type of the value that the field holds.
"""
struct ObjectFieldToValue <: Projection end

function print_document(p::ObjectFieldToValue, recursion, field::ObjectField, ctx)
    output = Cell(nothing)
    set_cell_computation!(output, () -> get_object_field_value(field))
    SimpleIoMap(p, field, output)
end

print_document(p::ObjectFieldToValue, field::ObjectField) =
    print_document(p, nothing, field, nothing)

# "Replace your output with `value`": a write on the field of its own object and
# path. The reader returns the operation and writes nothing (PAR-READER-IS-PURE).
function read_intent(::ObjectFieldToValue, iomap::SimpleIoMap,
                     operation::ReplaceReferencedValueOperation)
    (operation.document === nothing &&
     strip_reference_types(operation.reference) isa EmptyReference) || return operation
    field = iomap.input
    ReplaceReferencedValueOperation(get_object_field_root(field), field.path,
                                    _coerce(get_object_field_value(field), operation.value))
end

read_intent(::ObjectFieldToValue, iomap::SimpleIoMap, operation) = operation

function map_reference_forward(p::ObjectFieldToValue, iomap::SimpleIoMap, reference)
    range = find_object_field_range(iomap.input, reference)
    range === nothing || return make_flat_range_reference(range...)
    invoke(map_reference_forward, Tuple{Projection, Any, Any}, p, iomap, reference)
end

function map_reference_backward(p::ObjectFieldToValue, iomap::SimpleIoMap, reference)
    flat = strip_reference_types(reference)
    (flat isa ConcreteReference && flat.head isa TextRangeReferenceStep && flat.tail isa EmptyReference) &&
        return make_object_field_range_reference(iomap.input, flat.head.start, flat.head.stop)
    invoke(map_reference_backward, Tuple{Projection, Any, Any}, p, iomap, reference)
end
