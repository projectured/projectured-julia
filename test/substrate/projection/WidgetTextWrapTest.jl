# The text a widget draws itself, broken to the width the widget was given.
#
# Prose in a document is broken by `WordWrapping`. A `String` in a widget field
# is not a document, so the widget layer breaks it, and these tests measure
# where each line ends rather than count the lines: a line that ends past the
# box is the fault, whatever its number.

function test_widget_text_wrap()
@testset "a widget breaks its own text to the box" begin

# Eight pixels a character and sixteen a line, so a bound is arithmetic.
_measure = (t, f) -> (length(t) * 8, 16)
_projection() = RecursiveProjection(TypeDispatchingProjection(vcat(
    LayoutToGraphics().dispatch,
    WidgetToGraphics(font_ubuntu_regular_20; measure = _measure).dispatch)))

SENTENCE = "one two three four five six seven eight nine ten eleven twelve"

# Every text a canvas drew, as (left, right, content).
function _spans(node, ox = 0, found = Tuple{Int,Int,String}[])
    if node isa GraphicsCanvas
        for element in node.elements
            _spans(element, ox + Int(node.x), found)
        end
    elseif node isa GraphicsViewport
        _spans(node.content, ox + Int(node.x), found)
    elseif node isa GraphicsText
        text = string(node.text)
        left = ox + Int(node.x)
        push!(found, (left, left + length(text) * 8, text))
    end
    found
end

_print(document, width) = print_document(_projection(), nothing, document,
    with_exact_size(PrinterContext(); width = Cell(Int32(width)),
                                      height = Cell(Int32(600)))).output

@testset "a label breaks at the width it was offered" begin
    label = WidgetLabel(SENTENCE)
    spans = _spans(_print(label, 200))
    @test length(spans) > 1
    @test maximum(right for (_, right, _) in spans) <= 200
    # Every word survives the break, in order and once each.
    @test join((text for (_, _, text) in spans), " ") == SENTENCE
end

@testset "a label with no offer is the one line it measures" begin
    label = WidgetLabel(SENTENCE)
    spans = _spans(print_document(_projection(), nothing, label, PrinterContext()).output)
    @test length(spans) == 1
    @test spans[1][3] == SENTENCE
end

@testset "a card breaks its description to the width it was told" begin
    card = WidgetCard(; title = "A title", description = SENTENCE,
                      content = WidgetLabel(SENTENCE), width = 240)
    canvas = _print(card, 900)
    spans = _spans(canvas)
    # The card is the width it was told, and nothing it drew reaches past it.
    @test Int(canvas.w[]) == 240
    @test maximum(right for (_, right, _) in spans) <= 240
    # Both the card's own description and the label in its body are broken.
    @test count(t -> occursin("one two", t), (text for (_, _, text) in spans)) == 2
end

@testset "a word wider than the box keeps its own line" begin
    long = "short " * repeat("x", 60)
    spans = _spans(_print(WidgetLabel(long), 100))
    @test length(spans) == 2
    @test spans[2][3] == repeat("x", 60)
end

end
end
