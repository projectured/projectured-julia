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
    proj = make_json_projection_example(measure=FontFileMeasure())
    filename = tempname() * ".pdf"
    img = write_pdf(doc, proj, filename; width=400, height=300)
    @test img isa ImageFile
    @test isfile(filename)
    @test filesize(filename) > 0
    @test _is_pdf(filename)
    rm(filename)
end

@testset "write_pdf content-fit sizing (omitted axes)" begin
    doc  = make_json_document_example()
    proj = make_json_projection_example(measure=FontFileMeasure())
    filename = tempname() * ".pdf"
    img = write_pdf(doc, proj, filename)   # no width/height
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
    fnt = StyleModule.StyleFont("DejaVu Sans", 18)
    canvas = GraphicsCanvas([
        GraphicsRect(10, 10, 120, 40; color = StyleColor(220 / 255, 60 / 255, 60 / 255, 1.0), radius = 8,
                     border_width=2, border_color=color_black),
        GraphicsCircle(180, 30, 20; color = StyleColor(60 / 255, 120 / 255, 220 / 255, 200 / 255)),
        GraphicsLine(10, 70, 200, 70; color = color_black, width=2),
        GraphicsArc(220, 30, 15; width = 4, start_angle = 30, sweep_angle = 200, color = color_black),
        GraphicsText("Hello PDF — café", 12, 80; font = fnt, color = StyleColor(20 / 255, 20 / 255, 20 / 255, 1.0)),
    ])
    filename = tempname() * ".pdf"
    write_pdf(canvas, filename; width=240, height=120)
    @test _is_pdf(filename)
    # The embedded TrueType font dwarfs the operator stream, so a real file is
    # large; an empty/garbage write would be tiny.
    @test filesize(filename) > 50_000
    rm(filename)
end

@testset "an arc is a Bézier path at the middle of its band, with flat ends" begin
    # The operators that one arc writes on a page 100 high.
    function write_arc(arc)
        ctx = PdfModule.PageContext(100)
        PdfModule.paint_arc!(ctx, arc, 0, 0)
        String(take!(ctx.buf))
    end
    # A quarter from the top to the right of (50, 50), stroked at radius 35: the
    # page y grows upward, so the top is (50, 85) and the end is (85, 50). The
    # control points are KAPPA · 35 = 19.33 along the tangents.
    quarter = write_arc(GraphicsArc(50, 50, 40; width = 10, start_angle = 0, sweep_angle = 90, color = color_black))
    @test occursin("10 w 0 J [] 0 d 50 85 m 69.33 85 85 69.33 85 50 c S", quarter)
    # A sweep of 200 degrees is three segments of at most 90 each.
    @test count("c ", write_arc(GraphicsArc(50, 50, 40; width = 10, sweep_angle = 200, color = color_black))) == 3
    # A whole sweep is the ring of a circle; an empty sweep writes nothing.
    @test occursin("h S", write_arc(GraphicsArc(50, 50, 40; width = 10, color = color_black)))
    @test write_arc(GraphicsArc(50, 50, 40; width = 10, sweep_angle = 0, color = color_black)) == ""
end

@testset "GraphicsCanvasToPdfFile projection" begin
    doc  = make_json_document_example()
    filename = tempname() * ".pdf"
    proj = ChainingProjection(
        make_json_projection_example(measure=FontFileMeasure()),
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
    fnt = StyleModule.StyleFont("DejaVu Sans", 18)
    GraphicsCanvas(Any[GraphicsText("paginated line $(i+1)", 10, 10 + 20i; font = fnt, color = StyleColor(20 / 255, 20 / 255, 20 / 255, 1.0))
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
    proj = make_json_projection_example(measure=FontFileMeasure())
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

# The content stream of the first page. The writer numbers the page contents
# first, so the first stream of the file is that of page 1.
function _first_content_stream(filename)
    bytes = read(filename)
    text = String(copy(bytes))
    start = last(findfirst("stream\n", text)) + 1
    stop = first(findnext("\nendstream", text, start)) - 1
    String(bytes[start:stop])
end

@testset "a text is written at the size that the layout measured" begin
    font = StyleModule.StyleFont("Ubuntu Mono", 20)
    # A font's size already holds the font scale of the appearance by the time a
    # printer sees it, so a larger font here is a font scaled by an `Appearance`.
    appearance = Appearance(font_scale = 1.5)
    scaled_font = scale_theme_value(font, appearance)
    canvas = GraphicsCanvas([GraphicsText("zoom", 10, 10; font = scaled_font, color = color_black)])
    filename = tempname() * ".pdf"
    try
        size = font_logical_size(scaled_font)
        @test size != font.size
        write_pdf(canvas, filename; width=200, height=80)
        content = _first_content_stream(filename)
        @test [parse(Int, m.captures[1]) for m in eachmatch(r"/F\d+ (\d+) Tf", content)] == [size]
        # The baseline sits the ascent of the text's box at that size below the
        # top of the text, the same whole pixel every backend draws it at.
        m = match(r"1 0 0 1 ([\d.]+) ([\d.]+) Tm", content)
        _, ascent, _ = compute_text_extent("zoom", scaled_font)
        @test parse(Float64, m.captures[2]) ≈ 80 - (10 + ascent) atol=0.01
    finally
        rm(filename; force=true)
    end
end

@testset "a kerned pair is written with its kerning" begin
    # A–V is −62 font units in Ubuntu, so the V moves 62 thousandths of the size
    # to the left: a positive adjustment in the `TJ` array.
    font = StyleModule.StyleFont("Ubuntu", 20)
    ttf = load_truetype_font(compute_font_path(font))
    canvas = GraphicsCanvas([GraphicsText("AV", 10, 10; font, color = color_black)])
    filename = tempname() * ".pdf"
    write_pdf(canvas, filename; width=200, height=80)
    content = _first_content_stream(filename)
    glyph(c) = string(get_glyph_id(ttf, UInt32(c)), base=16, pad=4)
    @test occursin("[<$(glyph('A'))> 62 <$(glyph('V'))>] TJ", content)
    rm(filename)
end

@testset "texts of different fonts share a baseline in the file" begin
    # Two texts placed by the contract of `GraphicsText`: each `y` is the common
    # baseline minus that text's ascent. The file then has one baseline for both.
    baseline = 50
    texts = map((StyleModule.StyleFont("Ubuntu", 20), StyleModule.StyleFont("Ubuntu Mono", 20))) do font
        _, ascent, _ = compute_text_extent("x", font)
        GraphicsText("x", 10, baseline - ascent; font, color = color_black)
    end
    filename = tempname() * ".pdf"
    write_pdf(GraphicsCanvas(collect(texts)), filename; width=200, height=80)
    content = _first_content_stream(filename)
    ys = [parse(Float64, m.captures[1]) for m in eachmatch(r"1 0 0 1 [\d.]+ ([\d.]+) Tm", content)]
    @test length(ys) == 2
    @test ys[1] ≈ ys[2] ≈ 80 - baseline
    rm(filename)
end

@testset "a character that the font lacks is drawn in the font that has it" begin
    font = StyleModule.StyleFont("Ubuntu Mono", 20)
    primary = load_truetype_font(compute_font_path(font))
    check = '✓'
    @test !has_font_glyph(primary, UInt32(check))
    fallback_file = find_glyph_font_file(font, UInt32(check))
    @test fallback_file isa String && fallback_file != compute_font_path(font)
    fallback = load_truetype_font(fallback_file)
    # U+FE0F asks for emoji presentation; it has no width, and the writer drops it.
    canvas = GraphicsCanvas([GraphicsText("ok $(check)️", 10, 10; font, color = color_black)])
    filename = tempname() * ".pdf"
    write_pdf(canvas, filename; width=200, height=80)
    # The file with each byte outside ASCII replaced, so a regular expression can read it.
    text = String(map(b -> b < 0x80 ? b : UInt8('?'), read(filename)))
    content = _first_content_stream(filename)
    runs = [(m.captures[1], m.captures[2]) for m in eachmatch(r"/(F\d+) \d+ Tf \[<([0-9a-f]+)>\] TJ", content)]
    glyphs(ttf, s) = join(string(get_glyph_id(ttf, UInt32(c)), base=16, pad=4) for c in s)
    @test length(runs) == 2
    @test runs[1][2] == glyphs(primary, "ok ")
    @test runs[2][2] == glyphs(fallback, string(check))
    @test runs[1][1] != runs[2][1]
    # Both fonts are embedded, and the resource of the second run is the fallback font.
    @test count("/Subtype /Type0", text) == 2
    @test count("/FontFile2", text) == 2
    number = match(Regex("/$(runs[2][1]) (\\d+) 0 R"), text).captures[1]
    base_font = match(Regex("\\n$(number) 0 obj\\n<< /Type /Font /Subtype /Type0 /BaseFont /(\\w+)"), text)
    @test base_font.captures[1] == replace(splitext(basename(fallback_file))[1], r"[^A-Za-z0-9]" => "")
    rm(filename)
    # The writer embeds a font as `/FontFile2`, which holds TrueType outlines. A
    # CFF font has none, so a fallback font in that form is skipped.
    @test PdfModule._is_embeddable_font(fallback)
    @test !PdfModule._is_embeddable_font(load_truetype_font(compute_font_path(StyleModule.StyleFont("Inconsolata", 18))))
end

end # test_write_pdf
