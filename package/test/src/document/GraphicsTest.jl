function test_graphics()
@testset "ReactiveSDL" begin

sdlt = GraphicsText("test", 10, 20, font_ubuntu_monospace_regular_24, color_red)
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
    Cell(() -> Int32(off[] * 10)),
    Cell(Int32(0)),
    Cell(font_ubuntu_monospace_regular_24),
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

@testset "PreservingProjection" begin
    canvas = GraphicsCanvas([GraphicsText("a", 0, 0, font_ubuntu_monospace_regular_24)])
    proj = PreservingProjection()
    iomap = projection_print(proj, nothing, canvas, nothing)
    @test iomap.input === canvas
    @test iomap.output === canvas
end

end # test_graphics
