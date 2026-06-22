function test_write_image()

@testset "write_image(document, projection, filename)" begin
    doc  = make_json_document_example()
    proj = make_graphics_image_projection_example()
    filename = tempname() * ".bmp"
    img = write_image(doc, proj, filename; width=400, height=300)
    @test img isa ImageFile
    @test isfile(filename)
    @test filesize(filename) > 0
    rm(filename)
end

@testset "write_image(canvas, filename)" begin
    canvas = GraphicsCanvas()
    filename = tempname() * ".bmp"
    img = write_image(canvas, filename; width=100, height=80)
    @test img isa ImageFile
    @test isfile(filename)
    @test filesize(filename) > 0
    rm(filename)
end

@testset "GraphicsCanvasToImageFile projection" begin
    doc  = make_json_document_example()
    filename = tempname() * ".bmp"
    # GraphicsCanvasToImageFile is exported by the ProjecturedSDL package, which the
    # test module opts into via `using ProjecturedSDL`.
    proj = SequentialProjection(
        make_graphics_image_projection_example(),
        GraphicsCanvasToImageFile(filename; width=400, height=300),
    )
    iomap = projection_print(proj, doc)
    @test iomap.output isa ImageFile
    @test isfile(filename)
    @test filesize(filename) > 0
    rm(filename)
end

@testset "unsupported format raises error" begin
    canvas = GraphicsCanvas()
    @test_throws ErrorException write_image(canvas, tempname() * ".jpg")
end

end # test_write_image
