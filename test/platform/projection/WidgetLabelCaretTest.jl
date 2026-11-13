"""
`WidgetLabelToGraphicsCanvas` — the caret in the text of a label, from the lines
that the label records (`DrawnTextLine`).

Covers:
- a plain click on the text puts the caret at the character under the pointer,
  an Alt+click answers the same caret, which the container makes the text as a
  whole, and a right click and a double click answer nothing,
- a point there maps back to the same caret, and the caret maps forward to its
  place on the line, which has a box,
- the label draws the caret once its selection is that caret, and no caret before,
  and a band behind its text while the selection is the text as a whole,
- a move names the caret as the part under the pointer,
- a label of a number records its line too, as every value that it draws as a text,
- a badge takes the caret, the band and the move as a label does, and so do the
  initials of an avatar and the title and the description of an alert,
- a press that is bound to a label, as to a chip, acts before the caret.
"""

_label_caret_measure = FixedMeasure(10, 18, 6, 0)
_label_caret_printer() = WidgetLabelToGraphicsCanvas(WidgetTheme(); measure = _label_caret_measure)

# The point on the label at `dx` from the start of its text, in the middle of the label.
function _label_caret_point(iomap, dx::Int)
    line = only(iomap.drawn)
    (Int(unwrap_cell(getfield(line.text, :x))) + dx, Int(iomap.output.h) ÷ 2)
end

function test_widget_label_caret()
    @testset "a plain click on the text of a label puts the caret at the character" begin
        p = _label_caret_printer()
        label = WidgetLabel("Details")
        iomap = print_document(p, nothing, label, PrinterContext())
        caret = ConcreteReference(FieldReferenceStep("content"),
                    ConcreteReference(RangeReferenceStep(3, 3), EmptyReference()))
        # Each character of the stub measure is 10 wide, so 32 is nearest the place after "Det".
        x, y = _label_caret_point(iomap, 32)
        answer = read_intent(p, iomap, MouseClick(:left, x, y, ModifierKeys(); time = 0.0))
        @test answer isa ReplaceSelectionOperation && strip_reference_types(answer.path) == caret
        for count in (1, 2)
            alt_answer = read_intent(p, iomap, MouseClick(:left, x, y, count, ModifierKeys(alt = true); time = 0.0))
            @test alt_answer isa ReplaceSelectionOperation && strip_reference_types(alt_answer.path) == caret
        end
        @test read_intent(p, iomap, MouseClick(:right, x, y, ModifierKeys(); time = 0.0)) === nothing
        # A double click is left to the widget around the label.
        @test read_intent(p, iomap, MouseClick(:left, x, y, 2, ModifierKeys(); time = 0.0)) === nothing

        # A point there maps back to the same caret, and the caret maps forward to its
        # place on the line, which has a box.
        @test strip_reference_types(map_reference_backward(p, iomap, PointReferenceStep(x, y))) == caret
        place = map_reference_forward(p, iomap, caret)
        @test place !== nothing && find_reference_box(iomap.output, place; measure = _label_caret_measure) !== nothing

        # The label draws the caret, and no caret before.
        mark() = [e for e in iomap.output.elements if e isa GraphicsRect && Int(e.w) == 2]
        @test isempty(mark())
        evaluate_operation((document = label,), answer)
        @test length(mark()) == 1 && Int(only(mark()).x) == x - 2

        # The text selected as a whole draws a band behind its line, and no caret.
        bands() = [e for e in iomap.output.elements if e isa GraphicsRect && is_color_equal(e.color, p.selected_color)]
        @test isempty(bands())
        evaluate_operation((document = label,), ReplaceSelectionOperation(
            ConcreteReference(FieldReferenceStep("content"), EmptyReference())))
        @test length(bands()) == 1 && isempty(mark())
        set_selection!(label, nothing)
        @test isempty(bands())

        # A move names the caret as the part under the pointer.
        moved = read_intent(p, iomap, MouseMove(x, y, MouseButtons(), ModifierKeys(); time = 0.0))
        @test moved isa ReplaceMouseTargetOperation && strip_reference_types(moved.path) == caret
    end

    @testset "a label of a number records its line, as a label of a String does" begin
        p = _label_caret_printer()
        iomap = print_document(p, nothing, WidgetLabel(42), PrinterContext())
        @test length(iomap.drawn) == 1
        x, y = _label_caret_point(iomap, 8)
        answer = read_intent(p, iomap, MouseClick(:left, x, y, ModifierKeys(); time = 0.0))
        @test answer isa ReplaceSelectionOperation && strip_reference_types(answer.path) ==
              ConcreteReference(FieldReferenceStep("content"), ConcreteReference(RangeReferenceStep(1, 1), EmptyReference()))
    end

    @testset "a badge takes the caret as a label does" begin
        p = WidgetBadgeToGraphicsCanvas(WidgetTheme(); measure = _label_caret_measure)
        badge = WidgetBadge("running")
        iomap = print_document(p, nothing, badge, PrinterContext())
        caret = ConcreteReference(FieldReferenceStep("content"),
                    ConcreteReference(RangeReferenceStep(3, 3), EmptyReference()))
        x, y = _label_caret_point(iomap, 32)
        answer = read_intent(p, iomap, MouseClick(:left, x, y, ModifierKeys(); time = 0.0))
        @test answer isa ReplaceSelectionOperation && strip_reference_types(answer.path) == caret
        for count in (1, 2)
            alt_answer = read_intent(p, iomap, MouseClick(:left, x, y, count, ModifierKeys(alt = true); time = 0.0))
            @test alt_answer isa ReplaceSelectionOperation && strip_reference_types(alt_answer.path) == caret
        end
        @test read_intent(p, iomap, MouseClick(:left, x, y, 2, ModifierKeys(); time = 0.0)) === nothing
        moved = read_intent(p, iomap, MouseMove(x, y, MouseButtons(), ModifierKeys(); time = 0.0))
        @test moved isa ReplaceMouseTargetOperation && strip_reference_types(moved.path) == caret
        @test strip_reference_types(map_reference_backward(p, iomap, PointReferenceStep(x, y))) == caret
        # The badge draws the caret, and the band of its text selected as a whole.
        mark() = [e for e in iomap.output.elements if e isa GraphicsRect && Int(e.w) == 2]
        bands() = [e for e in iomap.output.elements if e isa GraphicsRect && is_color_equal(e.color, p.selected_color)]
        @test isempty(mark()) && isempty(bands())
        evaluate_operation((document = badge,), answer)
        @test length(mark()) == 1 && Int(only(mark()).x) == x - 2
        evaluate_operation((document = badge,), ReplaceSelectionOperation(
            ConcreteReference(FieldReferenceStep("content"), EmptyReference())))
        @test length(bands()) == 1 && isempty(mark())
        set_selection!(badge, nothing)
        @test isempty(mark()) && isempty(bands())
    end

    @testset "the initials of an avatar take the caret as a label does" begin
        p = WidgetAvatarToGraphicsCanvas(WidgetTheme(); measure = _label_caret_measure)
        avatar = WidgetAvatar("Q1")
        iomap = print_document(p, nothing, avatar, PrinterContext())
        x, y = _label_caret_point(iomap, 6)
        caret = ConcreteReference(FieldReferenceStep("initials"),
                    ConcreteReference(RangeReferenceStep(1, 1), EmptyReference()))
        answer = read_intent(p, iomap, MouseClick(:left, x, y, ModifierKeys(); time = 0.0))
        @test answer isa ReplaceSelectionOperation && strip_reference_types(answer.path) == caret
        # An avatar that shows an icon has no text, and a click on it answers nothing.
        icon = print_document(p, nothing, WidgetAvatar(:user), PrinterContext())
        @test isempty(icon.drawn)
    end

    @testset "the title and the description of an alert take the caret" begin
        p = WidgetAlertToGraphicsCanvas(WidgetTheme(); measure = _label_caret_measure)
        alert = WidgetAlert("Saved"; description = "All files are written")
        iomap = print_document(p, nothing, alert, PrinterContext())
        @test [strip_reference_types(line.part) for line in iomap.drawn] ==
              [ConcreteReference(FieldReferenceStep("title"), EmptyReference()),
               ConcreteReference(FieldReferenceStep("description"), EmptyReference())]
        for (line, field) in zip(iomap.drawn, ("title", "description"))
            x = Int(unwrap_cell(getfield(line.text, :x))) + 22
            y = Int(unwrap_cell(getfield(line.text, :y))) + 4
            answer = read_intent(p, iomap, MouseClick(:left, x, y, ModifierKeys(); time = 0.0))
            @test answer isa ReplaceSelectionOperation
            @test strip_reference_types(answer.path) ==
                  ConcreteReference(FieldReferenceStep(field), ConcreteReference(RangeReferenceStep(2, 2), EmptyReference()))
        end
    end

    @testset "a press that is bound to a label acts before the caret, as for a chip" begin
        p = _label_caret_printer()
        chosen = ReplaceSelectionOperation(EmptyReference())
        binding = GestureBinding(MouseClickPattern(:left; modifiers = Symbol[]), (_, _) -> chosen;
                                 description = "Choose the chip", domain = "test")
        label = WidgetLabel("open"; gestures = GestureBinding[binding])
        iomap = print_document(p, nothing, label, PrinterContext())
        x, y = _label_caret_point(iomap, 12)
        @test read_intent(p, iomap, MouseClick(:left, x, y, ModifierKeys(); time = 0.0)) === chosen
        # The chip is a control: a move names it as a whole, so its text gives no caret.
        # An Alt+click and an Alt+double click read no binding and answer the caret.
        @test read_intent(p, iomap, MouseMove(x, y, MouseButtons(), ModifierKeys(); time = 0.0)) === nothing
        caret = ConcreteReference(FieldReferenceStep("content"),
                    ConcreteReference(RangeReferenceStep(1, 1), EmptyReference()))
        for count in (1, 2)
            alt_answer = read_intent(p, iomap, MouseClick(:left, x, y, count, ModifierKeys(alt = true); time = 0.0))
            @test alt_answer isa ReplaceSelectionOperation && strip_reference_types(alt_answer.path) == caret
        end
        @test map_reference_backward(p, iomap, PointReferenceStep(x, y)) === nothing
    end

    @testset "a key moves the caret or the range in the text of a label, which stays read-only" begin
        p = _label_caret_printer()
        label = WidgetLabel("alpha beta")
        iomap = print_document(p, nothing, label, PrinterContext())
        place(a, b = a; direction = :forward) = ConcreteReference(FieldReferenceStep("content"),
            ConcreteReference(RangeReferenceStep(a, b, direction), EmptyReference()))
        # The answer to `key` from the selection `at`: the path that it selects, or what it answers.
        function press(widget, io, at, key; modifiers...)
            set_selection!(widget, at)
            answer = read_intent(p, io, KeyDown(key, ModifierKeys(; modifiers...); time = 0.0))
            answer isa ReplaceSelectionOperation ? strip_reference_types(answer.path) : answer
        end
        press(at, key; modifiers...) = press(label, iomap, at, key; modifiers...)
        @test press(place(2), :right) == place(3)
        @test press(place(2), :left) == place(1)
        @test press(place(2), :right; ctrl = true) == place(6)
        @test press(place(2), :right; shift = true) == place(2, 3)
        @test press(place(2), :left; shift = true) == place(1, 2; direction = :backward)
        @test press(place(1, 2; direction = :backward), :left; shift = true) == place(0, 2; direction = :backward)
        @test press(place(2, 4), :left) == place(2)
        @test press(place(2), :home) == place(0)
        @test press(place(2), :end) == place(10)
        @test press(place(2), :end; shift = true) == place(2, 10)
        @test press(place(2), :a; ctrl = true) == place(0, 10)
        # The text as a whole: Left and Right give the caret at its start and its end,
        # and Down goes on to the container.
        whole = ConcreteReference(FieldReferenceStep("content"), EmptyReference())
        @test press(whole, :left) == place(0)
        @test press(whole, :right) == place(10)
        @test press(whole, :down) === nothing
        # A typed letter and a removal change nothing, and go on to the container.
        set_selection!(label, place(2))
        @test read_intent(p, iomap, KeyPress('x'; time = 0.0)) === nothing
        @test press(place(2), :backspace) === nothing
        @test label.content == "alpha beta"

        # Up and Down go to the nearest character of the line above or below, and past
        # the first or the last line the key goes on to the container.
        two = WidgetLabel("alpha\nbeta")
        lines = print_document(p, nothing, two, PrinterContext())
        @test length(lines.drawn) == 2
        @test press(two, lines, place(8), :up) == place(2)
        @test press(two, lines, place(2), :down) == place(8)
        @test press(two, lines, place(2), :down; shift = true) == place(2, 8)
        @test press(two, lines, place(8), :down) === nothing
        @test press(two, lines, place(2), :up) === nothing

        # A badge takes the keys from the same helper.
        badge_printer = WidgetBadgeToGraphicsCanvas(WidgetTheme(); measure = _label_caret_measure)
        badge = WidgetBadge("running")
        badge_io = print_document(badge_printer, nothing, badge, PrinterContext())
        set_selection!(badge, place(1))
        answer = read_intent(badge_printer, badge_io, KeyDown(:right, ModifierKeys(); time = 0.0))
        @test answer isa ReplaceSelectionOperation && strip_reference_types(answer.path) == place(2)
    end
end
