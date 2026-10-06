function test_graphics()
@testset "ReactiveSDL" begin

sdlt = GraphicsText("test", 10, 20; font = StyleFont("Ubuntu Mono", 20), color = color_red)
@test sdlt.text == "test"
@test sdlt.x == 10
@test sdlt.y == 20
@test sdlt.color == color_red

sdlt.text = "changed"
@test sdlt.text == "changed"

# computed position
off = Cell(5)
sdlt2 = GraphicsText(
    Cell("hi"),
    Cell(@computation Int32(off[] * 10)),
    Cell(Int32(0)),
    Cell(StyleFont("Ubuntu Mono", 20)),
    Cell(color_black),
    Cell(nothing)
)
@test sdlt2.x == 50
off[] = 10
@test sdlt2.x == 100

end # @testset "ReactiveSDL"

@testset "GraphicsImage" begin
    img = GraphicsImage(10, 20, 100, 200, nothing)
    @test img.x == 10
    @test img.y == 20
    @test img.w == 100
    @test img.h == 200
    @test img.data === nothing

    img2 = GraphicsImage(0, 0, 64, 64, UInt8[0xff])
    @test img2.data == UInt8[0xff]
end

@testset "GraphicsPolygon" begin
    # A five-pointed star: concave, so a bounding-box hit test would claim the
    # notches between the arms.
    star = [(50, 0), (62, 33), (98, 35), (70, 56), (79, 90),
            (50, 71), (21, 90), (30, 56), (2, 35), (38, 33)]
    pg = GraphicsPolygon(star; color = color_red, border_width=2, border_color=color_black)
    @test pg.points == star
    @test pg.color == color_red
    @test pg.border_width == 2
    @test pg.border_color == color_black

    @test is_point_in_polygon(star, 50, 40)      # the body
    @test is_point_in_polygon(star, 50, 5)       # inside the top arm
    @test !is_point_in_polygon(star, 50, 80)     # the notch between the bottom arms
    @test !is_point_in_polygon(star, 10, 10)     # outside, but inside the bounding box

    canvas = GraphicsCanvas([pg])
    @test hit_element_at(canvas, 50, 40) == 0
    @test hit_element_at(canvas, 50, 80) === nothing

    # The extent is the outline padded by the border width.
    @test get_graphics_size(pg) == (100, 92)

    # `nothing` normalizes to a fully transparent border color.
    plain = GraphicsPolygon([(0, 0), (10, 0), (10, 10)])
    @test plain.border_width == 0
    @test plain.border_color.alpha == 0
    @test get_graphics_size(plain) == (10, 10)
end

@testset "GraphicsArc" begin
    # A quarter from the top to the right: the band of radius 16 to 20 around (50, 50).
    arc = GraphicsArc(50, 50, 20; width = 4, start_angle = 0, sweep_angle = 90, color = color_red)
    @test (arc.cx, arc.cy, arc.radius, arc.width) == (50, 50, 20, 4)
    @test (arc.start_angle, arc.sweep_angle) == (0.0, 90.0)
    @test arc.color == color_red

    canvas = GraphicsCanvas([arc])
    @test hit_element_at(canvas, 63, 37) == 0           # 45 degrees, on the band
    @test hit_element_at(canvas, 37, 37) === nothing    # 315 degrees: outside the sweep
    @test hit_element_at(canvas, 50, 50) === nothing    # the center
    @test hit_element_at(canvas, 50, 20) === nothing    # 0 degrees, past the outer edge

    # The extent is the box of the whole ring, padded by the width as the ring
    # of a circle is, whatever the angles.
    @test get_graphics_size(arc) == (74, 74)
    @test get_graphics_size(GraphicsArc(50, 50, 20; width = 4, start_angle = 180, sweep_angle = 10)) == (74, 74)

    # A full sweep claims the whole band; an empty one claims nothing.
    @test hit_element_at(GraphicsCanvas([GraphicsArc(50, 50, 20; width = 4)]), 37, 37) == 0
    @test hit_element_at(GraphicsCanvas([GraphicsArc(50, 50, 20; width = 4, sweep_angle = 0)]), 63, 37) === nothing

    # An angle follows a cell or a function, and it is not rounded.
    start = Cell(10.5)
    turning = GraphicsArc(0, 0, 8; start_angle = start, sweep_angle = () -> 2 * start[])
    @test (turning.start_angle, turning.sweep_angle) == (10.5, 21.0)
    start[] = 30.25
    @test (turning.start_angle, turning.sweep_angle) == (30.25, 60.5)
end

@testset "a geometric argument is a number, a cell or a function" begin
    angle = Cell(0.0)
    # A function follows what it reads, and its answer is rounded to a pixel.
    dot = GraphicsCircle(() -> 90 + 60 * cos(angle[]), () -> 90 - 60 * sin(angle[]), 5.4;
                         color = color_red)
    @test (dot.cx, dot.cy, dot.radius) == (150, 90, 5)
    angle[] = pi / 2
    @test (dot.cx, dot.cy) == (90, 30)
    # A cell is taken as it is.
    x = Cell(Int32(7))
    line = GraphicsLine(x, 0, 20, 30; color = color_black)
    @test line.x1 == 7
    x[] = Int32(9)
    @test line.x1 == 9
    # Points: a vector or a function, each point rounded.
    trace = GraphicsPolyline(() -> [(i, 2.6 * i) for i in 0:2]; color = color_black, width = 2)
    @test trace.points == [(0, 0), (1, 3), (2, 5)]
    # A text can be live too.
    label = GraphicsText(() -> string("t = ", round(Int, angle[])), 0, 0; font = StyleFont("Ubuntu Mono", 20))
    @test label.text == "t = 2"
end

@testset "IdentityProjection" begin
    canvas = GraphicsCanvas([GraphicsText("a", 0, 0; font = StyleFont("Ubuntu Mono", 20))])
    proj = IdentityProjection()
    iomap = print_document(proj, nothing, canvas, nothing)
    @test iomap.input === canvas
    @test iomap.output === canvas
end

@testset "compute_first_visible_index" begin
    rows(n; layout = layout_vertical, overlapping = false) = GraphicsCanvas(
        CellVector(Cell[Cell(GraphicsRect(0, 10 * (k - 1), 50, 10)) for k in 1:n]);
        layout = layout, overlapping = overlapping)
    canvas = rows(100)
    @test compute_first_visible_index(canvas, -5) == 1       # before the first row
    @test compute_first_visible_index(canvas, 0) == 1
    @test compute_first_visible_index(canvas, 9) == 1        # inside the first row
    @test compute_first_visible_index(canvas, 10) == 2       # at the top of the second
    @test compute_first_visible_index(canvas, 505) == 51
    @test compute_first_visible_index(canvas, 5000) == 100   # past the last row
    # Without a layout, with elements that can overlap, and with no elements, the
    # walk starts at the first element.
    @test compute_first_visible_index(rows(100; layout = layout_none), 505) == 1
    @test compute_first_visible_index(rows(100; overlapping = true), 505) == 1
    @test compute_first_visible_index(rows(0), 505) == 1
    # The hit test starts there and finds the row under the point.
    @test hit_element_at(canvas, 25, 505) == 50              # the offset of row 51
end

@testset "has_declared_extent" begin
    elements = CellVector(Cell[Cell(GraphicsRect(0, 10 * (k - 1), 500, 10)) for k in 1:3])
    rows = GraphicsCanvas(elements; w = 100, h = 30, layout = layout_vertical, overlapping = false)
    @test has_declared_extent(rows)
    # The size is the box, not the elements: the rects are 500 wide, the box 100.
    @test get_graphics_size(rows) == (100, 30)
    @test !has_declared_extent(GraphicsCanvas(elements; w = 100, h = 0, layout = layout_vertical,
                                              overlapping = false))
    @test !has_declared_extent(GraphicsCanvas(elements; w = 100, h = 30))   # no layout
    @test get_graphics_size(GraphicsCanvas(elements; w = 100, h = 30)) == (500, 30)
end

@testset "the graphics leaf maps a point to the element at it" begin
    # The hit test of a rasterized canvas is its backward mapping, and the reader of
    # a click reads it: the element at the point, and the point inside that element.
    rect = GraphicsRect(10, 10, 30, 20)
    text = GraphicsText("ab", 50, 0; font = StyleFont("Ubuntu Mono", 20))
    canvas = GraphicsCanvas(CellVector(Cell[Cell(rect), Cell(text)]))
    p = GraphicsCanvasToGraphicsImage()
    iomap = print_document(p, canvas)
    at_rect = map_reference_backward(p, iomap, PointReferenceStep(15, 12))
    @test at_rect == ConcreteReference(ElementReferenceStep(1),
                                       ConcreteReference(PointReferenceStep(5, 2)))
    at_text = map_reference_backward(p, iomap, ConcreteReference(PointReferenceStep(60, 5)))
    @test at_text == ConcreteReference(ElementReferenceStep(2),
                                       ConcreteReference(PointReferenceStep(10, 5)))
    @test map_reference_backward(p, iomap, PointReferenceStep(5, 200)) === nothing
    click = read_intent(p, iomap, MouseClick(:left, 15, 12; time = 0.0))
    @test click isa ReplaceSelectionOperation && click.path == at_rect
end

@testset "a dispatching and a switching projection map a point through their choice" begin
    rect = GraphicsRect(10, 10, 30, 20)
    canvas = GraphicsCanvas(CellVector(Cell[Cell(rect)]))
    expected = ConcreteReference(ElementReferenceStep(1), ConcreteReference(PointReferenceStep(5, 2)))
    by_predicate = PredicateDispatchingProjection((_ -> true) => GraphicsCanvasToGraphicsImage())
    @test map_reference_backward(by_predicate, print_document(by_predicate, canvas),
                                 PointReferenceStep(15, 12)) == expected
    switching = SwitchingProjection(Any[GraphicsCanvasToGraphicsImage()])
    @test map_reference_backward(switching, print_document(switching, canvas),
                                 PointReferenceStep(15, 12)) == expected
end

end # test_graphics
