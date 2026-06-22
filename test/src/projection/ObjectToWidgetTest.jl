function test_object_to_widget()

# A renderable string field + a renderable bool field + an opaque (skipped) field.
_proj() = TextHighlighting("dolor"; case_insensitive=false, color=color_red)

_content_ref() = ConcreteReferencePath(FieldReference("content"), EmptyReferencePath())

@testset "ObjectToWidget reflects renderable Cell fields into controls" begin

    proj = _proj()
    iomap = projection_print(ObjectToWidget(), proj)
    out = iomap.output

    # The output is a WidgetComposite (a real widget, carrying `visible`) wrapping
    # a 2-column (label | control) grid. The grid has 4 children: pattern
    # (String → WidgetText) and case_insensitive (Bool → WidgetCheckbox); the
    # StyleColor `color` field is skipped.
    @test out isa WidgetComposite
    grid = out.elements[1]
    @test grid isa GridLayout
    @test length(grid.children) == 4
    @test [nm for (_, nm) in iomap.controls] == ["pattern", "case_insensitive"]
    @test iomap.controls[1][1] isa WidgetText
    @test iomap.controls[2][1] isa WidgetCheckbox
    # The string control is editable: its content is a TextText viewing the field.
    @test iomap.controls[1][1].content isa TextText
    @test iomap.controls[1][1].content.elements[1].content == "dolor"
    @test iomap.controls[2][1].content == false

end # @testset

@testset "ObjectToWidget converts a text edit to a parameter value op" begin

    proj = _proj()
    iomap = projection_print(ObjectToWidget(), proj)

    # A Text-domain edit on the pattern control: insert "X" at the end (caret at
    # char 5 of "dolor"). Reference is rooted at the grid output: the pattern
    # control is grid child 2 (row 1) → 0-based children[1], then into the
    # WidgetText's TextText: children[1].content.elements[1].content[5:5].
    ref = ConcreteReferencePath(FieldReference("children"),
            ConcreteReferencePath(RangeReference(1, 2),
              ConcreteReferencePath(FieldReference("content"),
                ConcreteReferencePath(FieldReference("elements"),
                  ConcreteReferencePath(RangeReference(0, 1),
                    ConcreteReferencePath(FieldReference("content"),
                      ConcreteReferencePath(RangeReference(5, 5), EmptyReferencePath())))))))
    op = projection_read(ObjectToWidget(), iomap, StringReplaceRangeOperation(ref, "X"))
    @test op isa ReplaceReferencedValue
    @test op.document === proj
    @test op.reference.head == FieldReference("pattern")
    @test op.value == "dolorX"

end # @testset

@testset "ObjectToWidget redirects a checkbox edit to the object's field" begin

    proj = _proj()
    iomap = projection_print(ObjectToWidget(), proj)

    # The checkbox control emits an edit rooted at itself; redirect to the field.
    cb_ctrl = iomap.controls[2][1]
    op = projection_read(ObjectToWidget(), iomap,
                         ReplaceReferencedValue(cb_ctrl, _content_ref(), true))
    @test op isa ReplaceReferencedValue
    @test op.document === proj
    @test op.reference.head == FieldReference("case_insensitive")
    @test op.value == true

end # @testset

@testset "ObjectToWidget coerces a checkbox edit to Bool" begin

    proj = _proj()
    iomap = projection_print(ObjectToWidget(), proj)
    cb_ctrl = iomap.controls[2][1]

    op = projection_read(ObjectToWidget(), iomap,
                         ReplaceReferencedValue(cb_ctrl, _content_ref(), true))
    evaluate_operation(nothing, op)
    @test proj.case_insensitive[] === true

end # @testset

@testset "ObjectToWidget passes through an unrelated operation" begin

    proj = _proj()
    iomap = projection_print(ObjectToWidget(), proj)
    foreign = WidgetText(Point2D(0, 0), "x")
    op = ReplaceReferencedValue(foreign, _content_ref(), "y")
    @test projection_read(ObjectToWidget(), iomap, op) === op

end # @testset

@testset "WidgetCheckbox click emits the toggle convention operation" begin

    stub(t, f) = (length(t) * 10, 24)
    font = font_ubuntu_monospace_regular_24
    w2g  = WidgetToGraphics(font; measure=stub)
    cb_proj = first(pr for (T, pr) in w2g.dispatch if T === WidgetCheckbox)

    cb = WidgetCheckbox(Point2D(0, 0), false)
    iomap = projection_print(cb_proj, nothing, cb, PrinterContext())
    op = projection_read(cb_proj, iomap, MousePress(:left, 1, 1, Modifiers()))

    @test op isa ReplaceReferencedValue
    @test op.document === cb
    @test op.reference.head == FieldReference("content")
    @test op.value === true            # toggled from false

end # @testset

end # test_object_to_widget
