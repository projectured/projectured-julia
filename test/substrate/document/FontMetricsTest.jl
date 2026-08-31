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

end
end
