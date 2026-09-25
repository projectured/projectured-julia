# The vertical metrics a baseline-aligned layout needs, read from the font's own
# tables. The numbers below are DejaVu's, so a font asset that changes silently
# fails here rather than in a formula.
function test_font_metrics()
@testset "FontMetrics" begin

    font = font_dejavu_sans_regular_20

    @testset "the metrics are ordered and inside the em box" begin
        @test font_ascent(font) > 0
        @test font_descent(font) > 0
        @test font_x_height(font) > 0
        # A lowercase x is shorter than a capital, which is shorter than the
        # ascent. Math leans on that order: the axis is half the x height.
        @test font_x_height(font) < font_cap_height(font) < font_ascent(font)
        @test font_line_height(font) == font_ascent(font) + font_descent(font)
    end

    @testset "DejaVu Sans at size 20" begin
        # ascender 1901, descender −483, sCapHeight 1493, sxHeight 1120,
        # unitsPerEm 2048.
        @test font_ascent(font) == 19
        @test font_descent(font) == 5
        @test font_cap_height(font) == 15
        @test font_x_height(font) == 11
        @test font_line_height(font) == 24
    end

    @testset "the metrics scale with the size" begin
        small = font_dejavu_sans_regular_14
        large = font_dejavu_sans_regular_24
        @test font_ascent(small) < font_ascent(font) < font_ascent(large)
        @test font_x_height(small) < font_x_height(large)
    end

    @testset "an oblique face keeps the metrics of its upright one" begin
        # A variable is set oblique beside upright numbers; they must share a
        # baseline, so the two faces must report the same ascent.
        @test font_ascent(font_dejavu_sans_italic_20) == font_ascent(font)
        @test font_descent(font_dejavu_sans_italic_20) == font_descent(font)
    end

    @testset "the parser reads every vertical metric of the tables" begin
        # Ubuntu: hhea 932 / -189 / 28, OS/2 typo 776 / -185 / 56, win 932 / 189,
        # unitsPerEm 1000, USE_TYPO_METRICS clear.
        ubuntu = load_truetype_font(font_ubuntu_regular_20.filename)
        @test (ubuntu.ascent, ubuntu.descent, ubuntu.line_gap) == (932, -189, 28)
        @test (ubuntu.typo_ascent, ubuntu.typo_descent, ubuntu.typo_line_gap) == (776, -185, 56)
        @test (ubuntu.win_ascent, ubuntu.win_descent) == (932, 189)
        @test !ubuntu.use_typo_metrics
        # FreeType takes the hhea metrics of a font that does not ask for the
        # typographic ones.
        @test get_vertical_metrics(ubuntu) == (932, -189, 28)
        # Lucide sets USE_TYPO_METRICS, and FreeType takes its typographic
        # metrics: 1000 / 0 / 90, where hhea says 1000 / 0 / 0.
        lucide = load_truetype_font(font_lucide_icons_20.filename)
        @test lucide.use_typo_metrics
        @test get_vertical_metrics(lucide) == (1000, 0, 90)
    end

    @testset "the parser reads the kerning pairs of the kern table" begin
        ubuntu = load_truetype_font(font_ubuntu_regular_20.filename)
        pair(font, left, right) =
            get_kerning(font, get_glyph_id(font, left), get_glyph_id(font, right))
        # The pairs as the kern table of Ubuntu holds them, in font units.
        @test pair(ubuntu, 'A', 'V') == -62
        @test pair(ubuntu, 'T', 'o') == -55
        @test pair(ubuntu, 'L', 'T') == -115
        @test pair(ubuntu, 'W', 'W') == 12
        @test pair(ubuntu, 'f', 'i') == 0
        @test length(ubuntu.kern_pairs) == 5264
        # A monospaced font has no kern table, so no pair moves.
        mono = load_truetype_font(font_ubuntu_monospace_regular_20.filename)
        @test isempty(mono.kern_pairs)
        @test pair(mono, 'A', 'V') == 0
    end

end
end
