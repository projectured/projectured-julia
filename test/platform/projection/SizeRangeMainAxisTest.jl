# A layout printed in an exact width, and the width that each of its children
# draws, in order.
function _range_layout_child_widths(layout, width)
    projection = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(StyleFont("Ubuntu Mono", 20); measure = FixedMeasure(10, 18, 6, 0)).dispatch))
    ctx = PrinterContext(EmptyReference(), Cell(width), nothing, Dict{Symbol,Any}())
    iomap = print_document(projection, nothing, layout, ctx)
    [Int(last(entry).output.w[]) for entry in getfield(iomap, :child_iomaps)[]]
end

# The width that `document` draws alone, with no edge.
_range_natural_width(document) = only(_range_layout_child_widths(VerticalLayout(Any[document]), 100_000))

_RANGE_LONG = join(fill("word", 40), " ")    # 1990 px on one line

"""
    test_size_range_main_axis()

A stack gives each child on the axis it divides the room the others leave: an
unweighted child draws its content up to that room, a `Fixed` child its number,
and a weighted child its share. A `Content` column of a grid gives its cells its
edge. The worked examples 2 and 3 of `plan/done/layout-sizing-model.md`.
"""
function test_size_range_main_axis()
@testset "a row gives the field what the label and the button leave (example 2)" begin
    label, button = _range_natural_width(WidgetLabel("Name:")), _range_natural_width(WidgetButton("Go"))
    row = HorizontalLayout(Any[WidgetLabel("Name:"), LayoutConstraint(WidgetText(""); width = Fill),
                               WidgetButton("Go")]; gap = 8)
    @test _range_layout_child_widths(row, 400) == [label, 400 - 16 - label - button, button]
end

@testset "in a row of two long texts, the first takes the room (example 3)" begin
    widths = _range_layout_child_widths(HorizontalLayout(Any[WidgetLabel(_RANGE_LONG), WidgetLabel(_RANGE_LONG)];
                                                         gap = 8), 400)
    @test 300 < widths[1] <= 392
    shared = _range_layout_child_widths(HorizontalLayout(Any[WidgetLabel(_RANGE_LONG), WidgetLabel(_RANGE_LONG)];
                                                         gap = 8, child_width = Fill), 400)
    @test shared == [196, 196]
end

@testset "a long text before a button takes the room, unless it has a weight" begin
    button = _range_natural_width(WidgetButton("Go"))
    # As Content, the text counts only the button's minimum, 0, and wraps at 392;
    # the button keeps its width and passes the edge.
    widths = _range_layout_child_widths(HorizontalLayout(Any[WidgetLabel(_RANGE_LONG), WidgetButton("Go")];
                                                         gap = 8), 400)
    @test 400 - 8 - button < widths[1] <= 392
    @test widths[2] == button
    # With a weight, the text takes exactly what the button leaves.
    weighted = _range_layout_child_widths(HorizontalLayout(Any[LayoutConstraint(WidgetLabel(_RANGE_LONG); width = Fill),
                                                               WidgetButton("Go")]; gap = 8), 400)
    @test weighted == [400 - 8 - button, button]
end

@testset "a Fixed child on the main axis takes its number" begin
    widths = _range_layout_child_widths(HorizontalLayout(Any[LayoutConstraint(WidgetLabel("x"); width = Fixed(90)),
                                                             WidgetLabel("y")]; gap = 4), 400)
    @test widths[1] == 90
end

@testset "rows in a column wrap in both directions, and nothing loops" begin
    # A text before a button takes a weight; a text after it needs none.
    column = VerticalLayout(Any[HorizontalLayout(Any[LayoutConstraint(WidgetLabel(_RANGE_LONG); width = Fill),
                                                     WidgetButton("Go")]; gap = 8),
                                HorizontalLayout(Any[WidgetButton("Go"), WidgetLabel(_RANGE_LONG)]; gap = 8)])
    widths = _range_layout_child_widths(column, 300)
    @test all(w -> w <= 300, widths)
end

@testset "a Content column of a grid gives its cells its edge" begin
    short = _range_natural_width(WidgetLabel("key"))
    grid = GridLayout(Any[WidgetLabel("key"), WidgetLabel(_RANGE_LONG), WidgetLabel("key"), WidgetLabel(_RANGE_LONG)], 2;
                      horizontal_gap = 10)
    widths = _range_layout_child_widths(grid, 500)
    @test widths[1] == widths[3] == short
    @test 300 < widths[2] <= 500 - 10 - short
    @test 300 < widths[4] <= 500 - 10 - short
end
end # test_size_range_main_axis
