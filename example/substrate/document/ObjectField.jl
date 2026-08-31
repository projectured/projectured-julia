using ProjecturedKernel.DocumentModule: Document
using ProjecturedKernel.DocumentModule: @document
using ProjecturedKernel.ReferenceModule: Reference, ConcreteReference, EmptyReference,
                                         FieldReferenceStep, ElementReferenceStep,
                                         extend_reference

# Two of these make the point of `ObjectField`: a form can show a field of one
# object beside a field of another. `ObjectToWidget` takes one root and emits a
# fixed grid of that root's own fields, so it can not.
@document struct FormServer
    name::String
    capacity::Int
    enabled::Bool
    tags::Vector
end

_form_server() = FormServer("gateway", 4, true, Any["alpha", "beta"], nothing)
_form_client() = FormServer("laptop", 1, false, Any["x"], nothing)

# One field on its own. `ObjectFieldToSyntax` renders it as `name "gateway"`.
function make_object_field_document_example()
    ObjectField(_form_server(), "name")
end

# A hand-laid form. Each row is a label the author wrote and an `ObjectField` the
# projection turns into a control. Rows 1 and 2 name the SAME field of two
# DIFFERENT objects.
#
# The last row addresses a vector element. `ObjectToWidget` renders one read-only,
# because it registers a control only when it holds the field's backing cell, and
# a vector's elements live inside one cell. `ObjectField` writes through the path
# instead, so this row edits.
function make_object_field_form_document_example()
    server = _form_server()
    client = _form_client()
    tag_2 = extend_reference(ConcreteReference(FieldReferenceStep("tags"), EmptyReference()),
                             ElementReferenceStep(2))
    # `FormLayout` takes (label, field) pairs of documents and builds the
    # two-column grid. A bare control is exactly what its field slot wants, which
    # is the second reason `ObjectFieldToWidget` emits no label of its own.
    FormLayout([
        (WidgetLabel(Point2D(0, 0), "Server name"), ObjectField(server, "name")),
        (WidgetLabel(Point2D(0, 0), "Client name"), ObjectField(client, "name")),
        (WidgetLabel(Point2D(0, 0), "Capacity"),    ObjectField(server, "capacity")),
        (WidgetLabel(Point2D(0, 0), "Enabled"),     ObjectField(server, "enabled")),
        (WidgetLabel(Point2D(0, 0), "Second tag"),  ObjectField(server, tag_2)),
    ])
end
