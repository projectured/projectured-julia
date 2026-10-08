# An object whose parameters are cells, as an object that a person configures
# has them: a pattern, a flag, and a colour that the form does not show.
struct _OtwPatternParameters
    pattern::Cell
    case_insensitive::Cell
    color::StyleColor
end

function test_object_to_widget()

# A renderable string field + a renderable bool field + an opaque (skipped) field.
_proj() = _OtwPatternParameters(Cell("dolor"), Cell(false), color_red)

_content_ref() = ConcreteReference(FieldReferenceStep("content"), EmptyReference())

@testset "ObjectToWidget reflects renderable Cell fields into controls" begin

    proj = _proj()
    iomap = print_document(ObjectToWidget(), proj)
    out = iomap.output

    # The output is a WidgetComposite (a real widget, carrying `visible`) wrapping
    # a 2-column (label | control) grid. The grid has 4 children: pattern
    # (String → WidgetText) and case_insensitive (Bool → WidgetCheckbox); the
    # StyleColor `color` field is skipped.
    @test out isa WidgetComposite
    grid = out.elements[1]
    @test grid isa GridLayout
    @test length(grid.children) == 4
    @test [pth.head.name for (_, pth) in iomap.controls] == ["pattern", "case_insensitive"]
    @test iomap.controls[1][1] isa WidgetText
    @test iomap.controls[2][1] isa WidgetCheckbox
    # The string control is editable: its content is a TextBlock viewing the field.
    @test iomap.controls[1][1].content isa TextBlock
    @test iomap.controls[1][1].content.elements[1].content == "dolor"
    @test iomap.controls[2][1].content == false

end # @testset

@testset "ObjectToWidget converts a text edit to a parameter value op" begin

    proj = _proj()
    iomap = print_document(ObjectToWidget(), proj)

    # A Text-domain edit on the pattern control: insert "X" at the end (caret at
    # char 5 of "dolor"). Reference is rooted at the grid output: the pattern
    # control is grid child 2 (row 1) → 0-based children[1], then into the
    # WidgetText's TextBlock: children[1].content.elements[1].content[5:5].
    ref = ConcreteReference(FieldReferenceStep("children"),
            ConcreteReference(RangeReferenceStep(1, 2),
              ConcreteReference(FieldReferenceStep("content"),
                ConcreteReference(FieldReferenceStep("elements"),
                  ConcreteReference(RangeReferenceStep(0, 1),
                    ConcreteReference(FieldReferenceStep("content"),
                      ConcreteReference(RangeReferenceStep(5, 5), EmptyReference())))))))
    op = read_intent(ObjectToWidget(), iomap, ReplaceStringRangeOperation(ref, "X"))
    @test op isa ReplaceReferencedValueOperation
    @test op.document === proj
    @test op.reference.head == FieldReferenceStep("pattern")
    @test op.value == "dolorX"

end # @testset

@testset "ObjectToWidget redirects a checkbox edit to the object's field" begin

    proj = _proj()
    iomap = print_document(ObjectToWidget(), proj)

    # The checkbox control emits an edit rooted at itself; redirect to the field.
    cb_ctrl = iomap.controls[2][1]
    op = read_intent(ObjectToWidget(), iomap,
                         ReplaceReferencedValueOperation(cb_ctrl, _content_ref(), true))
    @test op isa ReplaceReferencedValueOperation
    @test op.document === proj
    @test op.reference.head == FieldReferenceStep("case_insensitive")
    @test op.value == true

end # @testset

@testset "ObjectToWidget coerces a checkbox edit to Bool" begin

    proj = _proj()
    iomap = print_document(ObjectToWidget(), proj)
    cb_ctrl = iomap.controls[2][1]

    op = read_intent(ObjectToWidget(), iomap,
                         ReplaceReferencedValueOperation(cb_ctrl, _content_ref(), true))
    evaluate_operation(nothing, op)
    @test proj.case_insensitive[] === true

end # @testset

@testset "ObjectToWidget passes through an unrelated operation" begin

    proj = _proj()
    iomap = print_document(ObjectToWidget(), proj)
    foreign = WidgetText("x")
    op = ReplaceReferencedValueOperation(foreign, _content_ref(), "y")
    @test read_intent(ObjectToWidget(), iomap, op) === op

end # @testset

@testset "WidgetCheckbox click emits the toggle convention operation" begin

    stub = FixedMeasure(10, 18, 6, 0)
    font = StyleFont("Ubuntu Mono", 20)
    w2g  = WidgetToGraphics(font; measure=stub)
    cb_proj = first(pr for (T, pr) in w2g.dispatch if T === WidgetCheckbox)

    cb = WidgetCheckbox(false)
    iomap = print_document(cb_proj, nothing, cb, PrinterContext())
    op = read_intent(cb_proj, iomap, MouseClick(:left, 1, 1, ModifierKeys(); time = 0.0))

    @test op isa ReplaceReferencedValueOperation
    @test op.document === cb
    @test op.reference.head == FieldReferenceStep("content")
    @test op.value === true            # toggled from false

end # @testset

@testset "ObjectToWidget renders nested struct + vector as collapsible cards" begin

    app = make_nested_object_to_widget_document_example()
    iomap = print_document(ObjectToWidget(), app)
    out = iomap.output

    # Root stays a bare composite wrapping a 2-column grid (no card) — flat-compat.
    @test out isa WidgetComposite
    grid = out.elements[1]
    @test grid isa GridLayout
    # 4 displayable fields (name, dark_mode, window, tags) → 8 label|value cells.
    @test length(grid.children) == 8

    # The struct field (`window`) and the vector field (`tags`) each become a card.
    cards = filter(c -> c isa WidgetCard, collect(grid.children))
    @test length(cards) == 2
    window_card, tags_card = cards[1], cards[2]

    # A card folds from its chevron, is titled with what it holds, and starts
    # expanded. Its body is the window's own grid composite.
    @test window_card.collapsible == true
    @test window_card.collapsed == false
    @test window_card.title isa WidgetLabel
    @test window_card.content isa WidgetComposite

    # The vector card holds a VerticalLayout of its (read-only) elements.
    @test tags_card.collapsible == true
    @test tags_card.content isa VerticalLayout
    @test length(tags_card.content.children) == 2               # "alpha", "beta"

end # @testset

@testset "ObjectToWidget collapse is the card's own and is reversible" begin

    app = make_nested_object_to_widget_document_example()
    iomap = print_document(ObjectToWidget(), app)
    grid = iomap.output.elements[1]
    window_card = first(c for c in collect(grid.children) if c isa WidgetCard)
    body = window_card.content
    @test window_card.collapsible == true

    # The card-graphics reader turns a chevron click into ToggleCollapseOperation(card);
    # the default handler flips the card's own `collapsed` cell (output view state).
    # The card drops its body as it draws (see "WidgetCard folds a Document body"
    # below), so the body itself stays as it was.
    evaluate_operation(nothing, ToggleCollapseOperation(window_card))
    @test window_card.collapsed == true
    @test window_card.content === body

    evaluate_operation(nothing, ToggleCollapseOperation(window_card))
    @test window_card.collapsed == false
    @test window_card.content === body

end # @testset

@testset "ObjectToWidget edits a nested field through its full path" begin

    app = make_nested_object_to_widget_document_example()
    iomap = print_document(ObjectToWidget(), app)

    # The deep checkbox is `window.visible`; its control path is window → visible.
    vis = first((c, pth) for (c, pth) in iomap.controls
                if c isa WidgetCheckbox && pth.head == FieldReferenceStep("window"))
    vis_ctrl, vis_path = vis

    op = read_intent(ObjectToWidget(), iomap,
                         ReplaceReferencedValueOperation(vis_ctrl, _content_ref(), false))
    @test op isa ReplaceReferencedValueOperation
    @test op.document === app
    @test op.reference.head == FieldReferenceStep("window")
    @test op.reference.tail.head == FieldReferenceStep("visible")
    @test op.value == false

    # And it writes through to the nested cell.
    evaluate_operation(nothing, op)
    @test app.window.visible[] === false

end # @testset

@testset "WidgetCard defaults to not collapsed" begin
    @test WidgetCard(; title="t", content="c").collapsed == false
end # @testset

@testset "WidgetCard height: content-tall by default, fixed when given" begin
    proj = make_widget_projection_example()
    # height = 0 (default) wraps the content...
    auto = WidgetCard(; title="t", content="c")
    @test auto.height == 0
    auto_h = Int(print_document(proj, auto).output.h[])
    @test auto_h > 0
    # ...while a positive height is taken literally, so a scrolling body has a
    # bounded allocation to scroll inside instead of extending past the border.
    fixed = WidgetCard(; title="t", content="c", height = auto_h + 200)
    @test Int(print_document(proj, fixed).output.h[]) == auto_h + 200
end # @testset

# A body that is a Document cannot make itself empty the way a reactive
# `CellVector` content can, so the card itself has to drop it. The child IO map
# survives the fold, so unfolding places the same child again.
@testset "WidgetCard folds a Document body and unfolds to the same child" begin
    # The card's own IO map, not the example chain's: the fold is asserted on the
    # card's child entries.
    proj = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(StyleFont("Ubuntu Mono", 20);
                         measure = FixedMeasure(10, 18, 6, 0)).dispatch))
    button = WidgetButton("Go"; size = Point2D(120, 40))
    card = WidgetCard(; title="t", content=button, width=240)
    iomap = print_document(proj, nothing, card, PrinterContext())
    entries() = length(getfield(iomap, :child_iomaps)[])
    open_height, open_entries = Int(iomap.output.h[]), entries()
    @test open_entries == 1

    card.collapsed = true
    @test Int(iomap.output.h[]) < open_height        # the body is gone
    @test entries() == 0                             # and takes no click

    card.collapsed = false
    @test Int(iomap.output.h[]) == open_height       # and comes back as it was
    @test entries() == open_entries
end # @testset

end # test_object_to_widget
