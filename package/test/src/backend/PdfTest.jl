function test_write_pdf()

# Helper: a well-formed PDF starts with "%PDF-" and ends near "%%EOF".
function _is_pdf(filename)
    bytes = read(filename)
    length(bytes) > 16 &&
        String(bytes[1:5]) == "%PDF-" &&
        occursin("%%EOF", String(bytes[max(1, end - 32):end]))
end

# Count page objects: each Page dict is "<< /Type /Page /Parent …"; the single
# Pages node is "/Type /Pages", which this prefix does not match.
function _page_count(filename)
    s = String(read(filename))
    n = 0; i = firstindex(s)
    while true
        j = findnext("/Type /Page /Parent", s, i)
        j === nothing && break
        n += 1; i = last(j) + 1
    end
    n
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
        GraphicsRect(10, 10, 120, 40, StyleColor(220 / 255, 60 / 255, 60 / 255, 1.0), 8;
                     border_width=2, border_color=color_black),
        GraphicsCircle(180, 30, 20, StyleColor(60 / 255, 120 / 255, 220 / 255, 200 / 255)),
        GraphicsLine(10, 70, 200, 70, color_black; width=2),
        GraphicsText("Hello PDF — café", 12, 80, fnt, StyleColor(20 / 255, 20 / 255, 20 / 255, 1.0)),
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
    proj = ChainingProjection(
        make_graphics_image_projection_example(measure=pdf_measure_text),
        GraphicsCanvasToPdfFile(filename; width=400, height=300),
    )
    iomap = print_document(proj, doc)
    @test iomap.output isa ImageFile
    @test isfile(filename)
    @test _is_pdf(filename)
    rm(filename)
end

@testset "unsupported format raises error" begin
    canvas = GraphicsCanvas()
    @test_throws ErrorException write_pdf(canvas, tempname() * ".png"; width=10, height=10)
end

# A tall stack of text lines used by the pagination tests.
function _tall_canvas(nlines)
    fnt = Projectured.FontModule.font_dejavu_sans_regular_18
    GraphicsCanvas(Any[GraphicsText("paginated line $(i+1)", 10, 10 + 20i, fnt, StyleColor(20 / 255, 20 / 255, 20 / 255, 1.0))
                       for i in 0:(nlines - 1)])
end

@testset "paginate=false is single page (default unchanged)" begin
    canvas = _tall_canvas(60)               # ~1210 tall, far taller than the page
    filename = tempname() * ".pdf"
    write_pdf(canvas, filename; width=300, height=400)
    @test _is_pdf(filename)
    @test _page_count(filename) == 1
    rm(filename)
end

@testset "paginate=true flows a tall canvas onto multiple pages" begin
    canvas = _tall_canvas(60)               # content height ~1210; 400-tall pages → ⌈1210/400⌉ = 4
    filename = tempname() * ".pdf"
    write_pdf(canvas, filename; width=300, height=400, paginate=true)
    @test _is_pdf(filename)
    @test _page_count(filename) == 4
    rm(filename)
end

@testset "paginate=true short content stays one page" begin
    canvas = _tall_canvas(3)
    filename = tempname() * ".pdf"
    write_pdf(canvas, filename; width=300, height=400, paginate=true)
    @test _page_count(filename) == 1
    rm(filename)
end

@testset "paginate=true document/projection overload" begin
    doc  = make_json_document_example()
    proj = make_graphics_image_projection_example(measure=pdf_measure_text)
    filename = tempname() * ".pdf"
    img = write_pdf(doc, proj, filename; paginate=true, width=300, height=120)
    @test img isa ImageFile
    @test _is_pdf(filename)
    @test _page_count(filename) > 1         # the JSON example is taller than 120 pt
    rm(filename)
end

@testset "GraphicsCanvasToPdfFile paginate=true" begin
    canvas = _tall_canvas(40)               # ~810 tall; 300-tall pages → ⌈810/300⌉ = 3
    filename = tempname() * ".pdf"
    proj = GraphicsCanvasToPdfFile(filename; width=300, height=300, paginate=true)
    iomap = print_document(proj, canvas)
    @test iomap.output isa ImageFile
    @test _page_count(filename) == 3
    rm(filename)
end

end # test_write_pdf
