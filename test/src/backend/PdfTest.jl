function test_write_pdf()

# Helper: a well-formed PDF starts with "%PDF-" and ends near "%%EOF".
function _is_pdf(filename)
    bytes = read(filename)
    length(bytes) > 16 &&
        String(bytes[1:5]) == "%PDF-" &&
        occursin("%%EOF", String(bytes[max(1, end - 32):end]))
end

@testset "write_pdf(document, projection, filename)" begin
    doc  = make_json_document_example()
    proj = make_graphics_image_projection_example(measure=pdf_measure_text)
    filename = tempname() * ".pdf"
    img = write_pdf(doc, proj, filename; width=400, height=300, measure=pdf_measure_text)
    @test img isa ImageFile
    @test isfile(filename)
    @test filesize(filename) > 0
    @test _is_pdf(filename)
    rm(filename)
end

@testset "write_pdf content-fit sizing (omitted axes)" begin
    doc  = make_json_document_example()
    proj = make_graphics_image_projection_example(measure=pdf_measure_text)
    filename = tempname() * ".pdf"
    img = write_pdf(doc, proj, filename; measure=pdf_measure_text)   # no width/height
    @test img isa ImageFile
    @test _is_pdf(filename)
    rm(filename)
end

@testset "write_pdf(canvas, filename)" begin
    canvas = GraphicsCanvas()
    filename = tempname() * ".pdf"
    img = write_pdf(canvas, filename; width=100, height=80)
    @test img isa ImageFile
    @test isfile(filename)
    @test filesize(filename) > 0
    @test _is_pdf(filename)
    rm(filename)
end

@testset "write_pdf renders every primitive + embedded font" begin
    fnt = Projectured.FontModule.font_dejavu_sans_regular_18
    canvas = GraphicsCanvas([
        GraphicsRect(10, 10, 120, 40, 220, 60, 60, 255, 8;
                     border_width=2, border_color=(0, 0, 0, 255)),
        GraphicsCircle(180, 30, 20, 60, 120, 220, 200),
        GraphicsLine(10, 70, 200, 70, 0, 0, 0, 255; width=2),
        GraphicsText("Hello PDF — café", 12, 80, fnt, 20, 20, 20, 255),
    ])
    filename = tempname() * ".pdf"
    write_pdf(canvas, filename; width=240, height=120)
    @test _is_pdf(filename)
    # The embedded TrueType font dwarfs the operator stream, so a real file is
    # large; an empty/garbage write would be tiny.
    @test filesize(filename) > 50_000
    rm(filename)
end

@testset "GraphicsCanvasToPdfFile projection" begin
    doc  = make_json_document_example()
    filename = tempname() * ".pdf"
    proj = SequentialProjection(
        make_graphics_image_projection_example(measure=pdf_measure_text),
        GraphicsCanvasToPdfFile(filename; width=400, height=300),
    )
    iomap = projection_print(proj, doc)
    @test iomap.output isa ImageFile
    @test isfile(filename)
    @test _is_pdf(filename)
    rm(filename)
end

@testset "unsupported format raises error" begin
    canvas = GraphicsCanvas()
    @test_throws ErrorException write_pdf(canvas, tempname() * ".png"; width=10, height=10)
end

end # test_write_pdf
