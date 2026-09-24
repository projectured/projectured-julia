function test_graphics()
@testset "ReactiveSDL" begin

sdlt = GraphicsText("test", 10, 20; font = font_ubuntu_monospace_regular_20, color = color_red)
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
    Cell(font_ubuntu_monospace_regular_20),
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
    label = GraphicsText(() -> string("t = ", round(Int, angle[])), 0, 0; font = font_ubuntu_monospace_regular_20)
    @test label.text == "t = 2"
end

@testset "IdentityProjection" begin
    canvas = GraphicsCanvas([GraphicsText("a", 0, 0; font = font_ubuntu_monospace_regular_20)])
    proj = IdentityProjection()
    iomap = print_document(proj, nothing, canvas, nothing)
    @test iomap.input === canvas
    @test iomap.output === canvas
end

end # test_graphics
