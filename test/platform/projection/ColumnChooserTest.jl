# The column chooser of a table: a checkbox for each column, with the label of the
# column, ticked when the column is shown. A press on a box does not flip it: it
# asks the owner of the columns, and the strip shows the answer.

function test_column_chooser()
@testset "the column chooser shows a labelled box for each column, and a press asks the owner" begin
    shown = Cell(Set([:a]))
    asked = Tuple{Symbol,Bool}[]
    bar = make_column_chooser_widget(; columns = [(:a, "Alpha"), (:b, "Beta")],
                                     is_shown = name -> name in shown[],
                                     choose = (name, on) -> begin
                                         push!(asked, (name, on))
                                         shown[] = on ? union(shown[], [name]) : setdiff(shown[], [name])
                                     end)
    boxes() = [child for child in bar.children if child isa WidgetCheckbox]
    @test [box.label for box in boxes()] == ["Alpha", "Beta"]
    @test [box.content for box in boxes()] == [true, false]

    # A left press on the box of Beta, through the projection of the box.
    projection = make_widget_projection_example(measure = FixedMeasure(10, 18, 6, 0))
    iomap = print_document(projection, nothing, boxes()[2],
                           PrinterContext(EmptyReference(), nothing, nothing, Dict{Symbol,Any}()))
    change = read_intent(projection, nothing,
                         Intent(MouseClick(:left, 4, 4, 1, ModifierKeys(); time = 0.0)), iomap)
    operation = change isa Intent ? change.operation : change
    @test operation isa InvokeActionOperation
    evaluate_operation(nothing, operation)
    @test asked == [(:b, true)]
    # The strip follows the answer: Beta is ticked now.
    @test [box.content for box in boxes()] == [true, true]
end
end
