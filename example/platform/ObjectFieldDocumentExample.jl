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
# DIFFERENT objects. The last row addresses a vector element, which the field
# writes through its path.
function make_object_field_form_document_example()
    server = _form_server()
    client = _form_client()
    tag_2 = extend_reference(ConcreteReference(FieldReferenceStep("tags"), EmptyReference()),
                             ElementReferenceStep(2))
    # `FormLayout` takes (label, field) pairs of documents and builds the
    # two-column grid. A bare control is exactly what its field slot wants, which
    # is the second reason `ObjectFieldToWidget` emits no label of its own.
    FormLayout([
        (WidgetLabel("Server name"), ObjectField(server, "name")),
        (WidgetLabel("Client name"), ObjectField(client, "name")),
        (WidgetLabel("Capacity"),    ObjectField(server, "capacity")),
        (WidgetLabel("Enabled"),     ObjectField(server, "enabled")),
        (WidgetLabel("Second tag"),  ObjectField(server, tag_2)),
    ])
end

# A plain value: a server and its window, with no cell. A form edits it in one of
# two ways, with the same layout: on a copy in a document of a schema, or in
# place, in one cell that every field of the form shares.
struct PlainServerWindow
    title::String
    width::Int
end

struct PlainServer
    name::String
    capacity::Int
    enabled::Bool
    window::PlainServerWindow
end

_plain_server() = PlainServer("gateway", 4, true, PlainServerWindow("Main", 800))

# The schema of a copy of a server: the same field names, each in a cell.
@document struct PlainServerWindowForm
    title::String
    width::Int
end

@document struct PlainServerForm
    name::String
    capacity::Int
    enabled::Bool
    window::PlainServerWindowForm
end

# The form of a server, laid out once for any root that has the fields of a
# server: a document of the schema, or a cell that holds a plain server.
function _make_plain_server_form(root)
    title = extend_reference(ConcreteReference(FieldReferenceStep("window"), EmptyReference()),
                             FieldReferenceStep("title"))
    FormLayout([
        (WidgetLabel("Name"),     ObjectField(root, "name")),
        (WidgetLabel("Capacity"), ObjectField(root, "capacity")),
        (WidgetLabel("Enabled"),  ObjectField(root, "enabled")),
        (WidgetLabel("Title"),    ObjectField(root, title)),
    ])
end

# A form on a copy: the plain server becomes a document of the schema, and the
# form edits the document. `convert_document_to_object(PlainServer, form)` makes a
# plain server of it again, for example when the person confirms the form.
make_plain_server_copy_form_document_example() =
    _make_plain_server_form(convert_object_to_document(PlainServerForm, _plain_server()))

# A form in place: the plain server stays plain, in one cell that every field
# shares. An edit puts a copy with the field changed into the cell, so the cell
# holds the edited server at any time.
make_plain_server_cell_form_document_example() = _make_plain_server_form(Cell(_plain_server()))

# A form whose widgets the author chooses: each widget holds a field of the plain
# server in its value slot, where it would hold a value.
function make_object_field_widget_form_document_example()
    root = Cell(_plain_server())
    FormLayout([
        (WidgetLabel("Name"),     WidgetText(ObjectField(root, "name"))),
        (WidgetLabel("Capacity"), WidgetSpinBox(ObjectField(root, "capacity"); min = 1, max = 16)),
        (WidgetLabel("Enabled"),  WidgetSwitch(; checked = ObjectField(root, "enabled"))),
    ])
end
