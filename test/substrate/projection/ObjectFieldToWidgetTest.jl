function test_object_field_to_widget()

_of_server() = FormServer("gateway", 4, true, Any["alpha", "beta"], nothing)

_of_tag_path(i) = extend_reference(ConcreteReference(FieldReferenceStep("tags"), EmptyReference()),
                                   ElementReferenceStep(i))

# The reference a checkbox click carries: rooted at the control, naming its own
# `content` slot.
_of_content_ref() = ConcreteReference(FieldReferenceStep("content"), EmptyReference())

# The reference a Text-domain edit carries, rooted at the control:
# `content.elements[0:1].content[cs:ce]`.
_of_text_ref(cs, ce) = ConcreteReference(FieldReferenceStep("content"),
    ConcreteReference(FieldReferenceStep("elements"),
      ConcreteReference(RangeReferenceStep(0, 1),
        ConcreteReference(FieldReferenceStep("content"),
          ConcreteReference(RangeReferenceStep(cs, ce), EmptyReference())))))

@testset "ObjectField names one field, and a name is a one-step path" begin

    srv = _of_server()
    f = ObjectField(srv, "name")
    @test f.object === srv
    @test f.path.head == FieldReferenceStep("name")
    @test f.path.tail isa EmptyReference
    @test object_field_value(f) == "gateway"
    @test object_field_name(f) == "name"

    # An element step names no field, so there is no label to derive from it.
    element = ObjectField(srv, _of_tag_path(2))
    @test object_field_value(element) == "beta"
    @test object_field_name(element) === nothing

end # @testset

@testset "ObjectFieldToWidget picks the control from the value type" begin

    srv = _of_server()
    p = ObjectFieldToWidget()

    # The output is the BARE control — no label, no wrapper. A GridLayout takes a
    # flat child list, so the label has to be a separate child the caller writes.
    @test print_document(p, ObjectField(srv, "name")).output isa WidgetText
    @test print_document(p, ObjectField(srv, "capacity")).output isa WidgetText
    @test print_document(p, ObjectField(srv, "enabled")).output isa WidgetCheckbox
    @test print_document(p, ObjectField(srv, "name")).output.content isa TextBlock

end # @testset

@testset "a control repaints when the object is written from elsewhere" begin

    srv = _of_server()
    p = ObjectFieldToWidget()
    text = print_document(p, ObjectField(srv, "name")).output
    check = print_document(p, ObjectField(srv, "enabled")).output
    @test text.content.elements[1].content == "gateway"
    @test check.content == true

    # The printer reads the value only inside a cell, so a write anywhere else —
    # another form, a background task — repaints the control.
    srv.name = "gw2"
    srv.enabled = false
    @test text.content.elements[1].content == "gw2"
    @test check.content == false

end # @testset

@testset "a checkbox click writes the field of the field's own object" begin

    srv = _of_server()
    p = ObjectFieldToWidget()
    iomap = print_document(p, ObjectField(srv, "enabled"))

    op = read_intent(p, iomap,
                     ReplaceReferencedValueOperation(iomap.output, _of_content_ref(), false))
    @test op isa ReplaceReferencedValueOperation
    @test op.document === srv
    @test op.reference.head == FieldReferenceStep("enabled")
    @test op.value == false

    evaluate_operation(nothing, op)
    @test srv.enabled == false

end # @testset

@testset "a text edit is coerced to the type the field already holds" begin

    srv = _of_server()
    p = ObjectFieldToWidget()

    name = print_document(p, ObjectField(srv, "name"))
    op = read_intent(p, name, ReplaceStringRangeOperation(_of_text_ref(7, 7), "X"))
    @test op isa ReplaceReferencedValueOperation
    @test op.document === srv
    @test op.value == "gatewayX"
    evaluate_operation(nothing, op)
    @test srv.name == "gatewayX"

    # An Int field stays an Int: the control delivers "42", the write is 42.
    cap = print_document(p, ObjectField(srv, "capacity"))
    op = read_intent(p, cap, ReplaceStringRangeOperation(_of_text_ref(1, 1), "2"))
    @test op.value === 42
    evaluate_operation(nothing, op)
    @test srv.capacity == 42

end # @testset

@testset "a vector element edits, which ObjectToWidget renders read-only" begin

    srv = _of_server()

    # ObjectToWidget registers a control only when it holds the field's backing
    # Cell, and a vector's elements live inside one cell — so no control of its
    # form addresses `tags`.
    reflected = print_document(ObjectToWidget(), srv)
    @test !any(pth -> get_reference_steps(pth)[1] == FieldReferenceStep("tags"),
               (pth for (_, pth) in reflected.controls))

    # ObjectField needs no cell. It writes through the path, and
    # ElementReferenceStep(i) is the RangeReferenceStep the kernel writes as
    # `parent[i] = value`.
    p = ObjectFieldToWidget()
    element = print_document(p, ObjectField(srv, _of_tag_path(2)))
    @test element.output isa WidgetText
    @test element.output.content.elements[1].content == "beta"

    op = read_intent(p, element, ReplaceStringRangeOperation(_of_text_ref(4, 4), "!"))
    @test op isa ReplaceReferencedValueOperation
    @test op.document === srv
    @test op.value == "beta!"
    evaluate_operation(nothing, op)
    @test srv.tags == Any["alpha", "beta!"]

end # @testset

@testset "a deep path writes the nested field" begin

    app = make_nested_object_to_widget_document_example()
    p = ObjectFieldToWidget()
    f = ObjectField(app, Reference(FieldReferenceStep("window"), FieldReferenceStep("title")))
    @test object_field_value(f) == "Main"
    @test object_field_name(f) == "title"

    iomap = print_document(p, f)
    op = read_intent(p, iomap, ReplaceStringRangeOperation(_of_text_ref(4, 4), "!"))
    evaluate_operation(nothing, op)
    @test app.window.title == "Main!"

end # @testset

@testset "one form holds fields of two different objects" begin

    form = make_object_field_form_document_example()
    fields = [c for c in form.children if c isa ObjectField]
    @test length(fields) == 5

    # Rows 1 and 2 name the SAME field of DIFFERENT objects. That is what
    # ObjectToWidget can not express: it takes one root.
    @test fields[1].object !== fields[2].object
    @test object_field_name(fields[1]) == object_field_name(fields[2]) == "name"
    @test object_field_value(fields[1]) == "gateway"
    @test object_field_value(fields[2]) == "laptop"

    # The projection replaces each ObjectField with its control and copies the
    # labels through untouched.
    stage = RecursiveProjection(TypeDispatchingProjection(
        ObjectField => ObjectFieldToWidget(),
        Any         => CopyingProjection()))
    out = print_document(stage, stage, form, PrinterContext()).output
    @test out isa GridLayout
    @test [typeof(c).name.name for c in out.children] ==
          [:WidgetLabel, :WidgetText, :WidgetLabel, :WidgetText,
           :WidgetLabel, :WidgetText, :WidgetLabel, :WidgetCheckbox,
           :WidgetLabel, :WidgetText]

end # @testset

end # test_object_field_to_widget
