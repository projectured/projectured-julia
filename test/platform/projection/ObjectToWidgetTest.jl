# An object whose parameters are cells, as an object that a person configures
# has them: a pattern, a flag, and a colour that the form does not show.
struct _OtwPatternParameters
    pattern::Cell
    case_insensitive::Cell
    color::StyleColor
end

# A plain value that a document holds, and the document.
struct OtwPlainWindow
    title::String
    width::Int
end

@document struct OtwPlainHolder
    name::String
    window::Any
end

function test_object_to_widget()

# A renderable string field + a renderable bool field + an opaque (skipped) field.
_proj() = _OtwPatternParameters(Cell("dolor"), Cell(false), color_red)

# The texts that the last frame draws, each with the point where it is drawn.
function _otw_drawn(canvas, ox = 0, oy = 0, found = Tuple{String,Int,Int}[])
    x = ox + Int(canvas.x)
    y = oy + Int(canvas.y)
    for element in canvas.elements
        element = element isa Cell ? element[] : element
        if element isa GraphicsText
            push!(found, (String(element.text), x + Int(element.x), y + Int(element.y)))
        elseif element isa GraphicsCanvas
            _otw_drawn(element, x, y, found)
        elseif element isa GraphicsViewport
            _otw_drawn(element.content, x + Int(element.x) + round(Int, element.transform.e),
                       y + Int(element.y) + round(Int, element.transform.f), found)
        end
    end
    found
end

_otw_texts(backend) = first.(_otw_drawn(last(rendered_output(backend))))

function _otw_editor(document; projection = make_object_to_widget_projection_example())
    backend = HeadlessBackend()
    editor = build_editor(document, projection;
        backend, devices = ProjecturedKernel.DeviceModule.Device[Keyboard(), Mouse(), Display()],
        window = false, appearance = false, settings = false, tabs = false, focus_cycling = false)
    run_frame!(editor)
    (editor, backend)
end

function _otw_click!(editor, backend, text; dx = 2, dy = 2)
    (_, x, y) = first(entry for entry in _otw_drawn(last(rendered_output(backend))) if entry[1] == text)
    push_event!(backend, MouseClick(:left, x + dx, y + dy, 1, ModifierKeys(); time = 0.0))
    run_frame!(editor)
end

_otw_type!(editor, backend, character::Char) =
    (push_event!(backend, KeyPress(character, string(character), ModifierKeys(); time = 0.0));
     run_frame!(editor))

_otw_selection(document) = get_reference_steps(strip_reference_types(get_selection(document)))

_otw_tick = string(Char(0xe06c))

@testset "ObjectToWidget makes a widget of each field, which holds a field of the object" begin

    proj = _proj()
    iomap = print_document(ObjectToWidget(), proj)
    out = iomap.output

    # The output is a WidgetComposite wrapping a 2-column (label | widget) grid.
    # The StyleColor `color` field is skipped.
    @test out isa WidgetComposite
    grid = out.elements[1]
    @test grid isa GridLayout
    @test length(grid.children) == 4
    @test [path.head.name for (_, path) in iomap.controls] == ["pattern", "case_insensitive"]
    text, checkbox = iomap.controls[1][1], iomap.controls[2][1]
    @test text isa WidgetText && checkbox isa WidgetCheckbox
    @test grid.children[2] === text && grid.children[4] === checkbox
    @test text.content isa ObjectField && get_object_field_value(text.content) == "dolor"
    @test get_object_field_value(checkbox.content) == false

end # @testset

@testset "a field of an object whose parameters are cells writes the cell" begin

    proj = _proj()
    iomap = print_document(ObjectToWidget(), proj)
    for (widget, value) in ((iomap.controls[1][1], "dolorX"), (iomap.controls[2][1], true))
        field = widget.content
        evaluate_operation(nothing,
            ReplaceReferencedValueOperation(get_object_field_root(field), field.path, value))
    end
    @test proj.pattern[] == "dolorX"
    @test proj.case_insensitive[] === true

end # @testset

@testset "make_widget chooses the widget of one field, and is_record the cards" begin

    switch = field -> get_object_field_name(field) == "dark_mode" ?
                      WidgetSwitch(; checked = field) : make_object_field_widget(field)
    app = make_nested_object_to_widget_document_example()
    iomap = print_document(ObjectToWidget(; make_widget = switch), app)
    @test only(w for (w, path) in iomap.controls if path.head.name == "dark_mode") isa WidgetSwitch
    @test only(w for (w, path) in iomap.controls if path.head.name == "name") isa WidgetText

    # With no record, the nested settings are not shown; the vector still is.
    flat = print_document(ObjectToWidget(; is_record = _ -> false), app)
    @test !any(path -> path.head.name == "window", (path for (_, path) in flat.controls))
    @test any(path -> path.head.name == "tags", (path for (_, path) in flat.controls))

end # @testset

@testset "keys through the form edit a field, a nested field and an element, at the caret" begin

    app = make_nested_object_to_widget_document_example()
    editor, backend = _otw_editor(app)

    _otw_click!(editor, backend, "MyApp")
    _otw_type!(editor, backend, 'X')
    @test app.name == "XMyApp"
    @test _otw_selection(app) == [FieldReferenceStep("name"), RangeReferenceStep(1, 1)]

    _otw_click!(editor, backend, "Main")
    _otw_type!(editor, backend, '!')
    @test app.window.title == "!Main"
    @test _otw_selection(app) == [FieldReferenceStep("window"), FieldReferenceStep("title"),
                                  RangeReferenceStep(1, 1)]

    _otw_click!(editor, backend, "beta")
    _otw_type!(editor, backend, '!')
    @test app.tags[2] == "!beta"
    @test app.tags[1] == "alpha"
    @test _otw_selection(app)[1] == FieldReferenceStep("tags")

    # A press on the tick of a checkbox writes its field.
    _otw_click!(editor, backend, _otw_tick)
    @test app.dark_mode == false

end # @testset

@testset "a card keeps its collapse while a field is edited" begin

    app = make_nested_object_to_widget_document_example()
    editor, backend = _otw_editor(app)
    @test "Main" in _otw_texts(backend)
    _otw_click!(editor, backend, string(Char(0xe06d)); dx = 4, dy = 4)
    @test !("Main" in _otw_texts(backend))
    _otw_click!(editor, backend, "MyApp")
    _otw_type!(editor, backend, 'X')
    @test app.name == "XMyApp"
    @test !("Main" in _otw_texts(backend))

end # @testset

@testset "a plain value that a document holds opens with is_record and edits through a copy" begin

    holder = OtwPlainHolder("gateway", OtwPlainWindow("Main", 800), nothing)
    w2g = WidgetToGraphics(StyleFont("Ubuntu Mono", 20); measure = FontFileMeasure())
    projection = ChainingProjection(
        ObjectToWidget(; is_record = value -> value isa OtwPlainWindow || is_form_record(value)),
        RecursiveProjection(TypeDispatchingProjection(vcat(
            LayoutToGraphics().dispatch, make_object_field_widget_dispatch(w2g.dispatch)))))
    editor, backend = _otw_editor(holder; projection)
    @test "OtwPlainWindow" in _otw_texts(backend)
    _otw_click!(editor, backend, "Main")
    _otw_type!(editor, backend, '!')
    @test holder.window isa OtwPlainWindow
    @test holder.window.title == "!Main"
    @test holder.window.width == 800
    @test "!Main" in _otw_texts(backend)

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
