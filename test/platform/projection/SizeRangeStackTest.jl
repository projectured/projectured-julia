# A column printed in an exact width, and the width that each of its children
# draws, in order.
function _range_column_child_widths(children, width)
    projection = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(font_ubuntu_monospace_regular_20; measure = FixedMeasure(10, 18, 6, 0)).dispatch))
    ctx = PrinterContext(EmptyReference(), Cell(width), nothing, Dict{Symbol,Any}())
    iomap = print_document(projection, nothing, VerticalLayout(children; gap = 4), ctx)
    [Int(last(entry).output.w[]) for entry in getfield(iomap, :child_iomaps)[]]
end

_RANGE_PROSE = join(fill("word", 40), " ")    # 199 characters, 1990 px on one line

"""
    test_size_range_cross_axis()

A column gives a `Content` child its content up to the column's edge: a label and
a button keep their natural width, and a long label wraps at the edge. A `Fill`
child still takes the column's width.
"""
function test_size_range_cross_axis()
@testset "a Content child draws its content, up to the column's edge" begin
    children() = Any[WidgetLabel("Name"), WidgetLabel(_RANGE_PROSE), WidgetButton("Go")]
    wide = _range_column_child_widths(children(), 500)
    narrow = _range_column_child_widths(children(), 300)
    # The label and the button keep their natural width at both widths.
    @test wide[1] == narrow[1] < 300
    @test wide[3] == narrow[3] < 300
    # The long label wraps at the edge: never wider than the column.
    @test 400 < wide[2] <= 500
    @test 200 < narrow[2] <= 300
end

@testset "a Fill child takes the column's width" begin
    children() = Any[LayoutConstraint(WidgetButton("Go"); width = Fill), WidgetButton("Go")]
    widths = _range_column_child_widths(children(), 400)
    @test widths[1] == 400
    @test widths[2] < 400
end

@testset "a placement minimum and maximum bound a Content child" begin
    children() = Any[LayoutConstraint(WidgetLabel("Go"); min_width = 120),
                     LayoutConstraint(WidgetLabel(_RANGE_PROSE); max_width = 250)]
    widths = _range_column_child_widths(children(), 500)
    @test widths[1] == 120
    @test 150 < widths[2] <= 250
end
end # test_size_range_cross_axis

# A composite printed in a window of `width` by `height`, or with no window when
# `width` is `nothing`, and the size that each of its children draws, in order.
function _range_composite_child_sizes(composite, width, height)
    projection = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(font_ubuntu_monospace_regular_20; measure = FixedMeasure(10, 18, 6, 0)).dispatch))
    ctx = width === nothing ? PrinterContext() :
          PrinterContext(EmptyReference(), Cell(width), Cell(height), Dict{Symbol,Any}())
    iomap = print_document(projection, nothing, composite, ctx)
    [(Int(last(entry).output.w[]), Int(last(entry).output.h[])) for entry in getfield(iomap, :child_iomaps)[]]
end

"""
    test_size_range_composite()

A composite gives each child its content, up to the composite's edge: a label in
a window keeps the size of its text. A `Fill` child reaches the edge from its
own position, and a composite whose children fill gives the edge to every child
that has no size of its own.
"""
function test_size_range_composite()
@testset "a child of a composite fits its content, and a Fill child reaches the edge" begin
    natural = only(_range_composite_child_sizes(WidgetComposite(Any[WidgetLabel("Name")]), nothing, nothing))
    sizes = _range_composite_child_sizes(
        WidgetComposite(Any[WidgetLabel("Name"),
                            LayoutConstraint(WidgetButton("Go"); width = Fill),
                            LayoutConstraint(WidgetButton("Go"; position = Point2D(10, 20));
                                             width = Fill, height = Fill)]),
        400, 300)
    @test sizes[1] == natural
    @test sizes[1][1] < 400 && sizes[1][2] < 300
    @test sizes[2][1] == 400
    @test sizes[2][2] < 300
    # The edge less the position of the child.
    @test sizes[3] == (390, 280)
end

@testset "a composite whose children fill gives every child the edge" begin
    sizes = _range_composite_child_sizes(
        WidgetComposite(Any[WidgetLabel("Name"), WidgetButton("Go"; size = Point2D(80, 24))];
                        child_width = Fill, child_height = Fill),
        400, 300)
    @test sizes[1] == (400, 300)
    # A size of its own wins over the fill.
    @test sizes[2] == (80, 24)
end
end # test_size_range_composite

# A widget with one child printed in a range of `width` by `height`: exact when
# `exact`, bounded when not, free with no `width`. The size of the widget, and
# the place and the size of its child.
function _range_one_child_sizes(widget, width, height; exact = true)
    projection = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(font_ubuntu_monospace_regular_20; measure = FixedMeasure(10, 18, 6, 0)).dispatch))
    ctx = width === nothing ? PrinterContext() :
          exact ? PrinterContext(EmptyReference(), Cell(width), Cell(height), Dict{Symbol,Any}()) :
          with_bounded_size(PrinterContext(); width = Cell(width), height = Cell(height))
    iomap = print_document(projection, nothing, widget, ctx)
    x, y, child = only(getfield(iomap, :child_iomaps)[])
    ((Int(iomap.output.w[]), Int(iomap.output.h[])), (x, y),
     (Int(child.output.w[]), Int(child.output.h[])))
end

"""
    test_size_range_one_child()

A widget with one child gives the child its own range less the parts it draws
around the child: a slot stays a slot and an edge stays an edge (§3 of
layout-rules.md).
"""
function test_size_range_one_child()
@testset "a title pane gives its content its slot less the insets and the title bar" begin
    pane() = WidgetTitlePane("T", WidgetLabel("Name"))
    free, _, content = _range_one_child_sizes(pane(), nothing, nothing)
    frame = (free[1] - content[1], free[2] - content[2])
    size, (x, y), content = _range_one_child_sizes(pane(), 300, 200)
    @test size == (300, 200)
    @test content == (300 - frame[1], 200 - frame[2])
    @test x + content[1] <= 300 && y + content[2] <= 200
    # At an edge, a long label wraps inside the pane.
    _, _, content = _range_one_child_sizes(WidgetTitlePane("T", WidgetLabel(_RANGE_PROSE)), 300, 200;
                                           exact = false)
    @test 200 < content[1] <= 300 - frame[1]
end
end # test_size_range_one_child
