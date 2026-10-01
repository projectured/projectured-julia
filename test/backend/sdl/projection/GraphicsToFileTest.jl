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

@testset "a viewport inside a viewport keeps the outer clip" begin
    # Viewports nest and SDL's clip rectangle does not: setting one REPLACES what
    # is in force, and clearing it removes clipping rather than putting the
    # enclosing one back. So an inner viewport used to drop the outer clip when it
    # finished, and everything drawn after it was unclipped — which is how a tab
    # page's content reached the tab strip above it.
    #
    # An outer viewport at (50,50) 100x100 holds an inner viewport and then a rect
    # that spills far outside the outer box. The pixel outside must stay white.
    red   = StyleColor(1.0, 0.0, 0.0, 1.0)
    blue  = StyleColor(0.0, 0.0, 1.0, 1.0)
    white = StyleColor(1.0, 1.0, 1.0, 1.0)
    hold(e) = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Int32(0), Int32(0),
                             CellVector(Cell[Cell(x) for x in e]),
                             layout_none, true, Cell(nothing))
    inner = GraphicsViewport(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(20)), Cell(Int32(20)),
                             Cell(hold([GraphicsRect(0, 0, 20, 20; color = blue)])),
                             Cell(affine_identity), Cell(nothing))
    outer = GraphicsViewport(Cell(Int32(50)), Cell(Int32(50)), Cell(Int32(100)), Cell(Int32(100)),
                             Cell(hold([inner, GraphicsRect(-40, -40, 300, 300; color = red)])),
                             Cell(affine_identity), Cell(nothing))
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(200)), Cell(Int32(200)),
                            CellVector(Cell[Cell(GraphicsRect(0, 0, 200, 200; color = white)), Cell(outer)]),
                            layout_none, true, Cell(nothing))
    filename = tempname() * ".bmp"
    write_image(canvas, filename; width = 200, height = 200)
    pixels = read(filename)
    # BMP, bottom-up. Read the data offset and the depth from the header rather
    # than assuming either: this writer produces 32-bit with a 122-byte header.
    le(i, n) = sum(Int(pixels[i + k]) << (8k) for k in 0:(n - 1))
    data_off = le(11, 4)
    bytes    = le(29, 2) ÷ 8
    stride   = ((200 * bytes + 3) ÷ 4) * 4
    at(x, y) = let i = data_off + (200 - 1 - y) * stride + x * bytes + 1
        (pixels[i + 2], pixels[i + 1], pixels[i])             # BGR -> RGB
    end
    @test at(10, 10)   == (0xff, 0xff, 0xff)   # outside the outer box: clipped
    @test at(100, 100) == (0xff, 0x00, 0x00)   # inside it: painted
    rm(filename)
end

@testset "GraphicsCanvasToImageFile projection" begin
    doc  = make_json_document_example()
    filename = tempname() * ".bmp"
    # GraphicsCanvasToImageFile is exported by the Sdl package, which the
    # test module opts into via `using ProjecturedSDL`.
    proj = ChainingProjection(
        make_graphics_image_projection_example(),
        GraphicsCanvasToImageFile(filename; width=400, height=300),
    )
    iomap = print_document(proj, doc)
    @test iomap.output isa ImageFile
    @test isfile(filename)
    @test filesize(filename) > 0
    rm(filename)
end

@testset "GraphicsCanvasToImageFile maps references with the projection generics" begin
    # The methods extend the generics of the projection layer: the slice holds
    # no function of its own under these names.
    for name in (:map_reference_forward, :map_reference_backward)
        generic = getfield(Projectured.ProjectionModule, name)
        method = which(generic, Tuple{GraphicsCanvasToImageFile, Any, Any})
        @test method.module === ProjecturedSDL.SdlModule
        @test !isdefined(ProjecturedSDL.SdlModule, name) ||
              getfield(ProjecturedSDL.SdlModule, name) === generic
    end
end

@testset "unsupported format raises error" begin
    canvas = GraphicsCanvas()
    @test_throws ErrorException write_image(canvas, tempname() * ".jpg")
end

end # test_write_image
