# The texts that a printed widget draws, from the top of its canvas down, and
# through the viewports of its panes.
function _collect_drawn_texts(element, texts = String[])
    element isa GraphicsText && push!(texts, String(element.text))
    element isa GraphicsCanvas && foreach(child -> _collect_drawn_texts(child, texts), element.elements)
    element isa GraphicsViewport && _collect_drawn_texts(element.content, texts)
    texts
end

_print_live_widget(widget) = print_document(
    RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(StyleFont("Ubuntu Mono", 20); measure = FixedMeasure(10, 18, 6, 0)).dispatch)),
    nothing, widget, PrinterContext())

"""
    test_widget_live_values()

A widget that shows a value takes a function of no arguments where it shows it,
and draws what the function answers now: the content of a `WidgetLabel`, the
value of a `WidgetProgressBar`, and a cell of a `WidgetTable`.
"""
function test_widget_live_values()
@testset "a label follows the function it is given" begin
    presses = Cell(1)
    label = WidgetLabel(() -> "Pressed $(presses[]) times")
    iomap = _print_live_widget(label)
    @test "Pressed 1 times" in _collect_drawn_texts(iomap.output)
    presses[] = 3
    @test label.content == "Pressed 3 times"
    @test "Pressed 3 times" in _collect_drawn_texts(iomap.output)
end

@testset "an answer that is not a string shows as its text" begin
    value = Cell(0.25)
    label = WidgetLabel(() -> value[])
    @test label.content == "0.25"
    value[] = 0.8
    @test label.content == "0.8"
end

@testset "a label takes a cell as it is, and a string as a plain value" begin
    text = Cell("one")
    @test WidgetLabel(text).content == "one"
    text[] = "two"
    @test WidgetLabel(text).content == "two"
    @test WidgetLabel("fixed").content == "fixed"
end

@testset "a progress bar follows the function it is given" begin
    share = Cell(0.25)
    bar = WidgetProgressBar(() -> share[])
    @test bar.value == 0.25
    share[] = 0.5
    @test bar.value == 0.5
    @test WidgetProgressBar(0.4).value == 0.4
end

@testset "a function in a table row is a live cell" begin
    presses = Cell(1)
    table = WidgetTable(["what", "value"], [["presses", () -> presses[]]])
    iomap = _print_live_widget(table)
    @test "1" in _collect_drawn_texts(iomap.output)
    presses[] = 7
    texts = _collect_drawn_texts(iomap.output)
    @test "7" in texts
    @test !("1" in texts)
end
end # test_widget_live_values
