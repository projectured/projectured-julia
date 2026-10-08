# A plain value, which is no document, with a plain value inside it, and a plain
# value that can change in place.
struct OfPlainWindow
    title::String
    width::Int
end

struct OfPlainServer
    name::String
    enabled::Bool
    window::OfPlainWindow
end

mutable struct OfPlainCounter
    count::Int
end

function test_object_field_to_widget()

_of_server() = FormServer("gateway", 4, true, Any["alpha", "beta"], nothing)

_of_tag_path(i) = extend_reference(ConcreteReference(FieldReferenceStep("tags"), EmptyReference()),
                                   ElementReferenceStep(i))

# The texts that a frame draws, each with the point where it is drawn.
function _of_drawn(canvas, ox = 0, oy = 0, found = Tuple{String,Int,Int}[])
    x = ox + Int(canvas.x)
    y = oy + Int(canvas.y)
    for element in canvas.elements
        element = element isa Cell ? element[] : element
        if element isa GraphicsText
            push!(found, (String(element.text), x + Int(element.x), y + Int(element.y)))
        elseif element isa GraphicsCanvas
            _of_drawn(element, x, y, found)
        elseif element isa GraphicsViewport
            _of_drawn(element.content, x + Int(element.x) + round(Int, element.transform.e),
                      y + Int(element.y) + round(Int, element.transform.f), found)
        end
    end
    found
end

_of_texts(backend) = first.(_of_drawn(last(rendered_output(backend))))

# A press at the first text `text` of the last frame, and the frame after it.
function _of_click!(editor, backend, text)
    (_, x, y) = first(entry for entry in _of_drawn(last(rendered_output(backend)))
                      if entry[1] == text)
    push_event!(backend, MouseClick(:left, x + 2, y + 2, 1, ModifierKeys(); time = 0.0))
    run_frame!(editor)
end

_of_type!(editor, backend, character::Char) =
    (push_event!(backend, KeyPress(character, string(character), ModifierKeys(); time = 0.0));
     run_frame!(editor))

# The tick that a checked checkbox draws.
of_tick = string(Char(0xe06c))

# The projection of the examples, with `make_widget` for a bare field, and with
# the row of an undo buffer.
function _of_projection(; make_widget = make_object_field_widget)
    measure = FontFileMeasure()
    w2g = WidgetToGraphics(StyleFont("Ubuntu Mono", 20); measure)
    RecursiveProjection(TypeDispatchingProjection(vcat(
        Pair{Type,Any}[UndoBuffer => UndoBufferToAnyProjection()],
        LayoutToGraphics().dispatch,
        make_object_field_widget_dispatch(w2g.dispatch; make_widget),
        Pair{Type,Any}[TextBlock => TextToGraphics(measure = measure)])))
end

# An editor on `document`, through the whole chain, after its first frame.
function _of_editor(document; projection = make_object_field_form_projection_example())
    backend = HeadlessBackend()
    editor = build_editor(document, projection;
        backend, devices = ProjecturedKernel.DeviceModule.Device[Keyboard(), Mouse(), Display()],
        window = false, appearance = false, settings = false, tabs = false,
        focus_cycling = false)
    run_frame!(editor)
    (editor, backend)
end

@testset "ObjectField names one field, and a name is a one-step path" begin

    srv = _of_server()
    f = ObjectField(srv, "name")
    @test f.object === srv
    @test f.path.head == FieldReferenceStep("name")
    @test f.path.tail isa EmptyReference
    @test get_object_field_value(f) == "gateway"
    @test get_object_field_name(f) == "name"

    # An element step names no field, so there is no label to derive from it.
    element = ObjectField(srv, _of_tag_path(2))
    @test get_object_field_value(element) == "beta"
    @test get_object_field_name(element) === nothing

end # @testset

@testset "the seam picks the widget from the value type, with the field in its slot" begin

    srv = _of_server()
    name = ObjectField(srv, "name")
    text = make_object_field_widget(name)
    @test text isa WidgetText
    @test text.content === name
    @test make_object_field_widget(ObjectField(srv, "capacity")) isa WidgetText
    check = make_object_field_widget(ObjectField(srv, "enabled"))
    @test check isa WidgetCheckbox
    @test check.content isa ObjectField

    # A value that no control edits is a label of its text.
    label = make_object_field_widget(ObjectField(srv, "tags"))
    @test label isa WidgetLabel
    @test label.content isa AbstractString

end # @testset

@testset "the table puts the row of a bare field before the widgets" begin

    table = make_object_field_widget_dispatch(
        WidgetToGraphics(StyleFont("Ubuntu Mono", 20); measure = FontFileMeasure()).dispatch)
    @test first(table).first === ObjectField
    @test first(table).second isa ObjectFieldToWidget
    rows = Dict(table)
    @test rows[WidgetCheckbox] isa NestingProjection
    @test rows[WidgetText] isa NestingProjection
    @test !(rows[WidgetLabel] isa NestingProjection)

end # @testset

@testset "a function argument chooses another widget, and falls back to the seam" begin

    srv = _of_server()
    choose(field) = get_object_field_name(field) == "name" ?
        WidgetSelect(field; options = Any["gateway", "edge"]) : make_object_field_widget(field)
    projection = _of_projection(; make_widget = choose)
    name = print_document(projection, projection, ObjectField(srv, "name"), PrinterContext())
    @test name.widget_iomap.input isa WidgetSelect
    enabled = print_document(projection, projection, ObjectField(srv, "enabled"), PrinterContext())
    @test enabled.widget_iomap.input isa WidgetCheckbox

end # @testset

@testset "a control repaints when the object is written from elsewhere" begin

    srv = _of_server()
    form = FormLayout([(WidgetLabel("Name"), ObjectField(srv, "name")),
                       (WidgetLabel("Enabled"), ObjectField(srv, "enabled"))])
    editor, backend = _of_editor(form)
    @test "gateway" in _of_texts(backend)
    @test of_tick in _of_texts(backend)

    # The widgets read the value only inside a cell, so a write anywhere else —
    # another form, a background task — repaints them.
    srv.name = "gw2"
    srv.enabled = false
    run_frame!(editor)
    @test "gw2" in _of_texts(backend)
    @test !(of_tick in _of_texts(backend))

end # @testset

@testset "a press and keys through the whole hand-laid form write the fields" begin

    form = make_object_field_form_document_example()
    server = first(c for c in form.children if c isa ObjectField).object
    editor, backend = _of_editor(form)

    # A press on the text and keys write the name of the server, and the caret
    # moves after each key.
    _of_click!(editor, backend, "gateway")
    _of_type!(editor, backend, 'X')
    _of_type!(editor, backend, 'Y')
    @test server.name == "XYgateway"

    # A press on the tick of the checkbox writes the field.
    _of_click!(editor, backend, of_tick)
    @test server.enabled == false

end # @testset

@testset "a text edit is coerced to the type the field already holds" begin

    srv = _of_server()
    editor, backend = _of_editor(FormLayout([(WidgetLabel("Capacity"), ObjectField(srv, "capacity"))]))
    _of_click!(editor, backend, "4")
    _of_type!(editor, backend, '2')
    @test srv.capacity isa Int
    @test srv.capacity in (24, 42)

end # @testset

@testset "a vector element edits through its path" begin

    srv = _of_server()
    editor, backend = _of_editor(FormLayout([(WidgetLabel("Tag"), ObjectField(srv, _of_tag_path(2)))]))
    _of_click!(editor, backend, "beta")
    _of_type!(editor, backend, '!')
    @test srv.tags[1] == "alpha"
    @test occursin("!", srv.tags[2])

end # @testset

@testset "a deep path writes the nested field" begin

    app = make_nested_object_to_widget_document_example()
    f = ObjectField(app, Reference(FieldReferenceStep("window"), FieldReferenceStep("title")))
    @test get_object_field_value(f) == "Main"
    @test get_object_field_name(f) == "title"

    editor, backend = _of_editor(FormLayout([(WidgetLabel("Title"), f)]))
    _of_click!(editor, backend, "Main")
    _of_type!(editor, backend, '!')
    @test occursin("!", app.window.title)

end # @testset

@testset "one form holds fields of two different objects" begin

    form = make_object_field_form_document_example()
    fields = [c for c in form.children if c isa ObjectField]
    @test length(fields) == 5

    # Rows 1 and 2 name the SAME field of DIFFERENT objects. That is what
    # ObjectToWidget can not express: it takes one root.
    @test fields[1].object !== fields[2].object
    @test get_object_field_name(fields[1]) == get_object_field_name(fields[2]) == "name"
    @test get_object_field_value(fields[1]) == "gateway"
    @test get_object_field_value(fields[2]) == "laptop"

    # The form draws the labels and the value of each field.
    editor, backend = _of_editor(form)
    texts = _of_texts(backend)
    @test all(text -> text in texts, ["Server name", "gateway", "Client name", "laptop",
                                       "Capacity", "4", "Enabled", of_tick, "Second tag", "beta"])

end # @testset

@testset "a plain value in one cell is edited by a form, and Ctrl+Z takes it back" begin

    root = Cell(OfPlainServer("gateway", true, OfPlainWindow("Main", 800)))
    title = Reference(FieldReferenceStep("window"), FieldReferenceStep("title"))
    form = FormLayout([(WidgetLabel("Name"),    ObjectField(root, "name")),
                       (WidgetLabel("Enabled"), ObjectField(root, "enabled")),
                       (WidgetLabel("Title"),   ObjectField(root, title))])
    editor, backend = _of_editor(UndoBuffer(form); projection = _of_projection())

    # A key in the nested title replaces the value in the cell by a copy, which
    # keeps the other fields.
    _of_click!(editor, backend, "Main")
    _of_type!(editor, backend, '!')
    @test root[] isa OfPlainServer
    @test occursin("!", root[].window.title)
    @test root[].name == "gateway"

    # The fields share the cell, so a second edit keeps the first.
    _of_click!(editor, backend, of_tick)
    @test root[].enabled == false
    @test occursin("!", root[].window.title)

    # Each way back writes the cell again.
    push_event!(backend, KeyDown(:z, ModifierKeys(ctrl = true); time = 0.0)); run_frame!(editor)
    @test root[].enabled == true
    push_event!(backend, KeyDown(:z, ModifierKeys(ctrl = true); time = 0.0)); run_frame!(editor)
    @test root[].window.title == "Main"

end # @testset

@testset "a plain mutable value changes in place, and the form repaints" begin

    counter = OfPlainCounter(4)
    editor, backend = _of_editor(FormLayout([(WidgetLabel("Count"), ObjectField(counter, "count"))]))
    _of_click!(editor, backend, "4")
    _of_type!(editor, backend, '2')
    @test counter.count in (24, 42)
    @test string(counter.count) in _of_texts(backend)

end # @testset

end # test_object_field_to_widget
