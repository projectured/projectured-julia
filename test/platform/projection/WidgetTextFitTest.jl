# The parts that a row of an outline draws with: a label that keeps to a number of
# lines, a text field that wraps and draws its box only while it holds the caret,
# a text that a trailing part follows on its line, and an icon, a mark that can be
# pressed, a chip and an avatar.

# Each drawn text and the top of its box, in the frame of `canvas`.
function _fit_drawn_texts(canvas, ox = 0, oy = 0, found = Tuple{String,Int,Int}[])
    x = ox + Int(canvas.x); y = oy + Int(canvas.y)
    for element in canvas.elements
        if element isa GraphicsText
            push!(found, (String(element.text), x + Int(element.x), y + Int(element.y)))
        elseif element isa GraphicsCanvas
            _fit_drawn_texts(element, x, y, found)
        end
    end
    found
end

# Each drawn element of type `T`, at any depth of `canvas`.
function _fit_drawn_elements(T, canvas, found = Any[])
    for element in canvas.elements
        element isa T && push!(found, element)
        element isa GraphicsCanvas && _fit_drawn_elements(T, element, found)
    end
    found
end

function test_widget_text_fit()
@testset "text that fits" begin
    font = StyleFont("Ubuntu Mono", 20)
    # Every character is 10 pixels wide, and a line of the font is 24 pixels tall.
    measure = FixedMeasure(10, 18, 6, 0)
    projection = RecursiveProjection(TypeDispatchingProjection(WidgetToGraphics(font; measure).dispatch))
    bounded(width) = with_bounded_size(PrinterContext(); width = Cell(width))
    print_at(document, width) = print_document(projection, nothing, document, bounded(width))
    texts(document, width) = [t for t in _fit_drawn_texts(print_at(document, width).output) if !isempty(strip(t[1]))]

    @testset "a label keeps to its lines, and the last one ends with an ellipsis" begin
        label = WidgetLabel("one two three four five six seven"; max_lines = 2,
                            padding = Inset(0, 0, 0, 0))
        lines = texts(label, 100)
        @test length(lines) == 2
        @test endswith(lines[end][1], "…")
        @test all(length(line[1]) * 10 <= 100 for line in lines)
        # With room for the whole text it is one line, with no ellipsis.
        whole = texts(label, 1000)
        @test length(whole) == 1 && !endswith(whole[1][1], "…")
    end

    @testset "a label takes the distance of its lines from its spacing" begin
        label = WidgetLabel("a\nb"; line_spacing = ExactSpacing(30), padding = Inset(0, 0, 0, 0))
        lines = texts(label, 200)
        @test [line[1] for line in lines] == ["a", "b"]
        @test lines[2][3] - lines[1][3] == 30
        @test Int(print_at(label, 200).output.h[]) == 60
    end

    @testset "a text field wraps a long value at its width, and keeps one line where it fits" begin
        field = WidgetText("one two three four"; wrap = true, padding = Inset(0, 0, 0, 0),
                           border = Inset(0, 0, 0, 0))
        narrow = texts(field, 100)
        @test length(unique(line[3] for line in narrow)) >= 2
        wide = texts(field, 1000)
        @test length(unique(line[3] for line in wide)) == 1
    end

    @testset "a trailing part follows a text of one line, and stands under a longer one" begin
        row(text) = FlowLayout(Any[WidgetText(text; wrap = true, margin = inset_default, border = inset_default,
                                              padding = inset_default),
                                   WidgetLabel("14:02"; padding = inset_default)];
                               horizontal_gap = 8)
        short = texts(row("Short"), 400)
        time_line = only(line for line in short if line[1] == "14:02")
        text_line = only(line for line in short if line[1] == "Short")
        @test time_line[3] == text_line[3]
        @test time_line[2] > text_line[2]
        long = texts(row("A statement that takes more than one line here"), 200)
        time_below = only(line for line in long if line[1] == "14:02")
        @test time_below[3] > minimum(line[3] for line in long if line[1] != "14:02")
    end

    @testset "a quiet field draws its box only while it holds the caret" begin
        field = WidgetText("abc"; quiet = true)
        output = print_at(field, 400).output
        boxes = [rect for rect in _fit_drawn_elements(GraphicsRect, output) if Int(rect.w) > 0]
        @test !isempty(boxes)
        @test all(rect -> rect.color == color_transparent && rect.border_color == color_transparent, boxes)
        set_selection!(field, ConcreteReference(FieldReferenceStep("content"),
                                                ConcreteReference(TextRangeReferenceStep(1, 1), EmptyReference())))
        @test any(rect -> rect.color != color_transparent || rect.border_color != color_transparent, boxes)
        # A field that is not quiet draws its box at rest.
        plain = print_at(WidgetText("abc"), 400).output
        @test any(rect -> rect.color != color_transparent || rect.border_color != color_transparent,
                  _fit_drawn_elements(GraphicsRect, plain))
    end

    @testset "a text field takes the font of its own text style" begin
        large = StyleFont("Ubuntu Mono", 30)
        field = WidgetText("abc"; text_style = large)
        @test any(element -> element.font == large, _fit_drawn_elements(GraphicsText, print_at(field, 400).output))
    end

    @testset "a chip is a label with round corners that answers a press" begin
        pressed = Ref(0)
        chip = WidgetLabel("Q1"; corner_radius = 4, padding = Inset(2, 2, 6, 6),
                           style = WidgetStyle(; padding_color = color_red, content_color = color_red),
                           gestures = GestureBinding[GestureBinding(MouseClickPattern(:left),
                                                                    (_, _) -> (pressed[] += 1; DoNothingOperation());
                                                                    description = "Select Q1",
                                                                    domain = "test")])
        iomap = print_at(chip, 400)
        @test any(rect -> Int(rect.radius_tl) == 4, _fit_drawn_elements(GraphicsRect, iomap.output))
        operation = read_intent(projection, iomap, MouseClick(:left, 3, 3, 1, ModifierKeys(); time = 0.0))
        @test operation isa DoNothingOperation
        @test pressed[] == 1
    end

    @testset "an icon draws in a layout with its mark, at its own size" begin
        icon = WidgetIcon(:circle; role = :success, bottom_right = WidgetIconMark(:dot), size = 17)
        output = print_at(HorizontalLayout(Any[icon, WidgetLabel("Q1")]; gap = 4), 400).output
        drawn = _fit_drawn_texts(output)
        label = only(text for text in drawn if text[1] == "Q1")
        @test label[2] >= 17 + 4
        # The glyph of the icon, and the disc of its mark.
        @test length(drawn) >= 2
        @test !isempty(_fit_drawn_elements(GraphicsCircle, output)) ||
              length(_fit_drawn_elements(GraphicsRect, output)) >= 1
    end

    @testset "a toolbar item shows a mark at its size, and a press invokes its action" begin
        invoked = Ref(0)
        action = Action("Open the menu of Q1"; icon = WidgetIcon(:circle; bottom_right = WidgetIconMark(:dot),
                                                                 size = 17),
                        callback = (_...) -> (invoked[] += 1; nothing))
        item = WidgetToolbarItem(action; padding = Inset(0, 0, 0, 0), border = Inset(0, 0, 0, 0),
                                 margin = Inset(0, 0, 0, 0))
        @test Int(print_at(item, 400).output.w[]) == 17
    end

    @testset "an avatar shows an icon, and scales its text to its size" begin
        small = print_at(WidgetAvatar(:sparkle; size = 14, padding = Inset(0, 0, 0, 0)), 400).output
        glyphs = _fit_drawn_elements(GraphicsText, small)
        @test length(glyphs) == 1 && only(glyphs).font.size < 14
        large = print_at(WidgetAvatar("JD"; size = 64), 400).output
        @test only(_fit_drawn_elements(GraphicsText, large)).font.size > font.size
    end
end
end
