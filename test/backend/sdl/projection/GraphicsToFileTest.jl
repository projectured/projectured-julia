function test_write_image()

@testset "write_image(document, projection, filename)" begin
    doc  = make_json_document_example()
    proj = make_json_projection_example()
    filename = tempname() * ".bmp"
    img = write_image(doc, proj, filename; width=400, height=300)
    @test img isa ImageFile
    @test isfile(filename)
    @test filesize(filename) > 0
    rm(filename)
end

@testset "an image has the scales of the appearance at its export, and not its zoom" begin
    # An export prints the projection of a view, so it has the scales that the
    # projection reads when it prints. The zoom belongs to a view on a screen:
    # the caller gives the density of an image.
    document = WidgetButton("Appearance")
    # The width, the height and the bytes of the BMP file of an export.
    function export_image(projection)
        filename = tempname() * ".bmp"
        write_image(document, projection, filename)
        bytes = read(filename)
        rm(filename)
        le(i) = sum(Int(bytes[i + k]) << (8k) for k in 0:3)
        (le(19), abs(Int32(le(23) % UInt32)), bytes)
    end
    make_projection(appearance) = NaturalToGraphics(; measure = FontFileMeasure(), appearance)
    started = export_image(make_projection(Appearance(font_scale = 1.5)))
    live = Appearance()
    projection = make_projection(live)
    before = export_image(projection)
    @test before[1:2] != started[1:2]
    live.font_scale = 1.5
    @test export_image(projection) == started
    @test export_image(make_projection(Appearance(font_scale = 1.5, zoom = 2.0))) == started
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

@testset "an arc draws its sweep and nothing else" begin
    # The band of radius 30 to 40 around (50, 50), on white, with no supersample:
    # the supersample smooths an edge and hides a pixel that is wrong.
    red   = StyleColor(1.0, 0.0, 0.0, 1.0)
    white = StyleColor(1.0, 1.0, 1.0, 1.0)
    # The BGR bytes of a 100x100 BMP of `shapes` on white, bottom-up, and the
    # RGB of the pixel (x, y) in them.
    function draw_pixels(shapes)
        canvas = GraphicsCanvas(Any[GraphicsRect(0, 0, 100, 100; color = white), shapes...])
        filename = tempname() * ".bmp"
        write_image(canvas, filename; width = 100, height = 100, supersample = 1)
        bytes = read(filename)
        rm(filename)
        le(i, n) = sum(Int(bytes[i + k]) << (8k) for k in 0:(n - 1))
        bytes[le(11, 4) + 1:end], le(29, 2) ÷ 8
    end
    function pixel_at(drawn, x, y)
        pixels, depth = drawn
        i = (100 - 1 - y) * (((100 * depth + 3) ÷ 4) * 4) + x * depth + 1
        (pixels[i + 2], pixels[i + 1], pixels[i])
    end
    quarter = draw_pixels([GraphicsArc(50, 50, 40; width = 10, start_angle = 0, sweep_angle = 90, color = red)])
    @test pixel_at(quarter, 75, 25) == (0xff, 0x00, 0x00)   # 45 degrees, in the band
    @test pixel_at(quarter, 60, 13) == (0xff, 0x00, 0x00)   # 16 degrees: the sweep starts at the top
    @test pixel_at(quarter, 40, 13) == (0xff, 0xff, 0xff)   # 344 degrees: before the start
    @test pixel_at(quarter, 25, 25) == (0xff, 0xff, 0xff)   # 315 degrees, in the band
    @test pixel_at(quarter, 75, 75) == (0xff, 0xff, 0xff)   # 135 degrees, past the end
    @test pixel_at(quarter, 50, 50) == (0xff, 0xff, 0xff)   # the center
    @test pixel_at(quarter, 63, 37) == (0xff, 0xff, 0xff)   # 45 degrees, inside the inner edge

    # A whole sweep colors exactly the pixels of the ring of a circle.
    ring = draw_pixels([GraphicsArc(50, 50, 40; width = 10, color = red)])
    circle = draw_pixels([GraphicsCircle(50, 50, 40; color = color_transparent, border_width = 10,
                                         border_color = red)])
    @test ring == circle
    @test pixel_at(ring, 25, 25) == (0xff, 0x00, 0x00)
    # An empty sweep draws nothing.
    @test draw_pixels([GraphicsArc(50, 50, 40; width = 10, sweep_angle = 0, color = red)]) == draw_pixels([])
end

@testset "GraphicsCanvasToImageFile projection" begin
    doc  = make_json_document_example()
    filename = tempname() * ".bmp"
    # GraphicsCanvasToImageFile is exported by the Sdl package, which the
    # test module opts into via `using ProjecturedSDL`.
    proj = ChainingProjection(
        make_json_projection_example(),
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
        generic = getfield(ProjecturedKernel.ProjectionModule, name)
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
