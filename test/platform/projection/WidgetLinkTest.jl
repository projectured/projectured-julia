"""
`WidgetLink`: a text that opens the page of its target. A click and Return open
the page here, and Ctrl and a click and a middle click open it in a new tab. A
link draws its text in the link color, with no frame, as tall as a label, and a
line under its text only while the pointer is on it.
"""

function test_widget_link()
@testset "WidgetLink" begin

font = StyleFont("Ubuntu Mono", 20)
measure = FixedMeasure(10, 18, 6, 0)
link_color = WidgetLinkToGraphicsCanvas(make_widget_theme(font = font); measure).link_text.color

make_projection() = ChainingProjection(
    FocusCyclingProjection(inner =
        RecursiveProjection(TypeDispatchingProjection(WidgetToGraphics(font; measure).dispatch))))

# The elements that a canvas draws, through the canvases inside it.
function collect_elements(canvas)
    found = Any[]
    for element in canvas.elements
        element isa GraphicsCanvas ? append!(found, collect_elements(element)) : push!(found, element)
    end
    found
end

click(projection, iomap, button; ctrl = false, x = 5) =
    read_intent(projection, iomap, MouseClick(button, x, 5, 1, ModifierKeys(ctrl = ctrl); time = 0.0))

@testset "a click and Return open the target here, Ctrl and a click and a middle click in a new tab" begin
    target = WidgetLabel("the page")
    reference = extend_reference(EmptyReference(), FieldReferenceStep("content"))
    link = WidgetLink("notes.txt", DocumentLocator(target, reference))
    projection = make_projection()
    iomap = print_document(projection, nothing, link, PrinterContext())
    here = click(projection, iomap, :left)
    @test here isa OpenPageOperation && here.document === target && here.reference === reference &&
          here.place === :here
    @test click(projection, iomap, :left; ctrl = true).place === :new_tab
    @test click(projection, iomap, :middle).place === :new_tab
    @test read_intent(projection, iomap, KeyPress('\n'; time = 0.0)).place === :here
    @test click(projection, iomap, :right) === nothing
    @test click(projection, iomap, :left; x = 500) === nothing
end

@testset "a link with a path opens the part that the path names from the link" begin
    projection = make_projection()
    iomap = print_document(projection, nothing, WidgetLink("row 2", EmptyReference()), PrinterContext())
    opened = click(projection, iomap, :left)
    @test opened isa OpenPageOperation && opened.document === nothing && opened.place === :here
    @test isempty(get_reference_steps(strip_reference_types(opened.reference)))
end

@testset "a link draws its text in the link color, with no frame, as tall as a label" begin
    projection = make_projection()
    link_canvas = print_document(projection, nothing, WidgetLink("notes.txt", EmptyReference()), PrinterContext()).output
    label_canvas = print_document(projection, nothing, WidgetLabel("notes.txt"), PrinterContext()).output
    @test (link_canvas.w, link_canvas.h) == (label_canvas.w, label_canvas.h)
    elements = collect_elements(link_canvas)
    text = only(element for element in elements if element isa GraphicsText)
    @test text.text == "notes.txt" && is_color_equal(text.color, link_color)
    label_text = only(element for element in collect_elements(label_canvas) if element isa GraphicsText)
    @test !is_color_equal(label_text.color, link_color)
    # At rest the line under the text and the ring of the focus have no size.
    @test all(element -> !(element isa GraphicsRect) || Int(element.w) * Int(element.h) == 0, elements)
    @test any(element -> element isa GraphicsPointerShape && element.shape === :pointing_hand, elements)
end

@testset "an icon stands before the text" begin
    projection = make_projection()
    plain = print_document(projection, nothing, WidgetLink("notes", EmptyReference()), PrinterContext()).output
    with_icon = print_document(projection, nothing, WidgetLink("notes", EmptyReference(); icon = :folder),
                               PrinterContext()).output
    @test with_icon.w > plain.w
    # The icon is a glyph, so the text is the one that says the name.
    text = only(element for element in collect_elements(with_icon) if element isa GraphicsText && element.text == "notes")
    @test Int(text.x) > 0
end

@testset "a line shows under the text only while the pointer is on the link" begin
    link = WidgetLink("notes.txt", EmptyReference())
    driver = MttDriver(make_projection(), link)
    underline() = only(element for element in collect_elements(driver.iomap.output)
                       if element isa GraphicsRect && is_color_equal(element.color, link_color))
    text = only(element for element in collect_elements(driver.iomap.output) if element isa GraphicsText)
    @test Int(underline().w) == 0
    _mtt_move!(driver, 5, 5, 1.0)
    @test get_mouse_target(link) !== nothing
    @test Int(underline().w) == Int(driver.iomap.output.w) && Int(underline().h) > 0
    @test Int(underline().y) > Int(text.y)
    _mtt_move!(driver, 500, 500, 2.0)
    @test Int(underline().w) == 0
end

@testset "a link breaks its text at the width it was offered, with a line under each line" begin
    text = "H1 A queue capacity of thirteen is enough"
    context = with_exact_size(PrinterContext(); width = Cell(Int32(120)), height = Cell(Int32(600)))
    link = WidgetLink(text, EmptyReference())
    canvas = print_document(make_projection(), nothing, link, context).output
    elements = collect_elements(canvas)
    lines = [element for element in elements if element isa GraphicsText]
    underlines = [element for element in elements if element isa GraphicsRect && is_color_equal(element.color, link_color)]
    @test length(lines) > 1 && length(underlines) == length(lines)
    @test all(line -> Int(line.x) + 10 * length(line.text) <= 120, lines)
    @test join((line.text for line in lines), " ") == text
    @test issorted([Int(line.y) for line in lines]) && allunique([Int(line.y) for line in lines])
end

@testset "a link is a stop of Tab, and the gesture help lists its opens" begin
    @test get_first_focusable_path(WidgetLink("notes.txt", EmptyReference())) isa EmptyReference
    bindings = collect_document_gesture_bindings(WidgetLink)
    opens = [binding for binding in bindings if binding.domain == "widget"]
    @test length(opens) == 4
    @test Set(binding.description for binding in opens) == Set(["Open as a page", "Open in a new tab"])
end

@testset "a button that opens a page takes the middle click and Return too" begin
    target = WidgetLabel("the page")
    button = WidgetButton("Open the page"; gestures = make_open_page_gestures(target, EmptyReference(); domain = "test"))
    projection = make_projection()
    iomap = print_document(projection, nothing, button, PrinterContext())
    @test click(projection, iomap, :left).place === :here
    @test click(projection, iomap, :left; ctrl = true).place === :new_tab
    @test click(projection, iomap, :middle).place === :new_tab
    pressed = read_intent(projection, iomap, KeyPress('\n'; time = 0.0))
    @test pressed isa OpenPageOperation && pressed.document === target && pressed.place === :here
end

end
end # test_widget_link
