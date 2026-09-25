# The ranges of the child rule, on the width: exact `(s, s)`, bounded `(0, l)`,
# free `(0, ∅)`, and a bounded range with a minimum `(m, l)`.
_range_exact(s) = PrinterContext(EmptyReference(), Cell(s), nothing, Dict{Symbol,Any}())
_range_bounded(l) = with_bounded_size(PrinterContext(); width = Cell(l))
_range_free() = PrinterContext()
_range_between(m, l) = PrinterContext(EmptyReference(), Cell(m), Cell(l), nothing, nothing,
                                      Dict{Symbol,Any}(), Clock())

_range_widget_projection() = RecursiveProjection(TypeDispatchingProjection(
    WidgetToGraphics(font_ubuntu_monospace_regular_20; measure = (t, f) -> (length(t) * 10, 24)).dispatch))

# The width that `document` draws in the range `ctx`.
_range_drawn_width(document, ctx) =
    Int(print_document(_range_widget_projection(), nothing, document, ctx).output.w[])

# The count of line breaks that wrapping inserts in `text` in the range `ctx`.
function _range_wrap_breaks(text, ctx)
    wrapped = print_document(WordWrapping(; measure = (t, f) -> (length(t) * 10, 18)), nothing,
                             TextBlock(TextString(text, font_ubuntu_monospace_regular_20, color_default)), ctx).output
    count(element -> element isa TextNewline, wrapped.elements)
end

"""
    test_size_range_child_rule()

Every child draws `max(minimum, content)` in the range its parent gives, or its
authored size; an overlay caps at the maximum; wrapped text and a flow break at
the maximum, and a flow draws its widest line. The drawn width is asserted in each state of the range.
"""
function test_size_range_child_rule()
@testset "a rigid widget draws max(minimum, content)" begin
    content = _range_drawn_width(WidgetLabel("Hello"), _range_free())
    @test content > 0
    @test _range_drawn_width(WidgetLabel("Hello"), _range_exact(300)) == 300
    @test _range_drawn_width(WidgetLabel("Hello"), _range_bounded(200)) == content
    # A child never draws smaller than its content: the container clips it.
    @test _range_drawn_width(WidgetLabel("Hello"), _range_bounded(content ÷ 2)) == content
    @test _range_drawn_width(WidgetLabel("Hello"), _range_between(content + 40, 400)) == content + 40
    # An authored size wins in every state.
    @test _range_drawn_width(WidgetSlider(0.5; width = 90), _range_exact(300)) ==
          _range_drawn_width(WidgetSlider(0.5; width = 90), _range_free())
end

@testset "an overlay caps at the maximum and never stretches" begin
    tooltip = () -> WidgetTooltip("a tooltip that is wider than a hundred pixels")
    content = _range_drawn_width(tooltip(), _range_free())
    @test content > 100
    @test _range_drawn_width(tooltip(), _range_exact(100)) == 100
    @test _range_drawn_width(tooltip(), _range_bounded(100)) == 100
    @test _range_drawn_width(tooltip(), _range_exact(content + 500)) == content
end

@testset "wrapped text breaks at the maximum, exact or bounded" begin
    text = "word word word word word word word word word word"    # 500 px on one line
    @test _range_wrap_breaks(text, _range_exact(120)) > 0
    @test _range_wrap_breaks(text, _range_bounded(120)) == _range_wrap_breaks(text, _range_exact(120))
    @test _range_wrap_breaks(text, _range_between(60, 120)) == _range_wrap_breaks(text, _range_exact(120))
    @test _range_wrap_breaks(text, _range_bounded(1000)) == 0
end

@testset "a flow breaks at the smaller of its max_width and the maximum, and draws its widest line" begin
    cards = (; kwargs...) -> FlowLayout(Any[WidgetLabel("abcd") for _ in 1:5]; kwargs...)
    one_line = _range_drawn_width(cards(), _range_free())      # with no edge, one line
    @test one_line < 1000
    @test _range_drawn_width(cards(), _range_bounded(1000)) == one_line
    # Broken at half, a bounded flow draws its widest line and an exact flow its edge.
    narrow = _range_drawn_width(cards(), _range_bounded(one_line ÷ 2))
    @test narrow <= one_line ÷ 2
    @test _range_drawn_width(cards(), _range_exact(one_line ÷ 2)) == one_line ÷ 2
    # A max_width less than the edge breaks the lines where that edge does.
    @test _range_drawn_width(cards(; max_width = one_line ÷ 2), _range_bounded(1000)) == narrow
end
end # test_size_range_child_rule
