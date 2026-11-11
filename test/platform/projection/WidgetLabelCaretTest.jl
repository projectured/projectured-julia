"""
`WidgetLabelToGraphicsCanvas` — the caret in the text of a label, from the lines
that the label records (`DrawnText`).

Covers:
- a plain click on the text puts the caret at the character under the pointer,
  and an Alt+click, a right click and a double click do not,
- a point there maps back to the same caret, and the caret maps forward to its
  place on the line, which has a box,
- the label draws the caret once its selection is that caret, and no caret before,
- a move names the caret as the part under the pointer,
- a label that shows no `String` records no line, and a click on it answers nothing.
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
        @test read_intent(p, iomap, MouseClick(:left, x, y, ModifierKeys(alt = true); time = 0.0)) === nothing
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

        # A move names the caret as the part under the pointer.
        moved = read_intent(p, iomap, MouseMove(x, y, MouseButtons(), ModifierKeys(); time = 0.0))
        @test moved isa ReplaceMouseTargetOperation && strip_reference_types(moved.path) == caret
    end

    @testset "a label that shows no String records no line" begin
        p = _label_caret_printer()
        iomap = print_document(p, nothing, WidgetLabel(42), PrinterContext())
        @test isempty(iomap.drawn)
        answer = read_intent(p, iomap, MouseClick(:left, 4, Int(iomap.output.h) ÷ 2, ModifierKeys(); time = 0.0))
        @test answer === nothing
    end
end
