# The measure a layout asks: the box of a string, the metrics of a font, and the
# x of each character boundary. The numbers of Ubuntu are its table values:
# unitsPerEm 1000, hhea 932 / -189 / 28, the advances of A 663 and V 656, and
# the kerning of the pair A–V −62. At 20 pixels a font unit is 0.02 pixels.
function test_text_measure()
@testset "the text measure" begin

    measure = FontFileMeasure()
    ubuntu = StyleFont("Ubuntu", 20)

    @testset "the metrics of a font are its tables at its size" begin
        metrics = get_font_metrics(measure, ubuntu)
        @test metrics.ascent ≈ 18.64
        @test metrics.descent ≈ 3.78
        @test metrics.line_gap ≈ 0.56
    end

    @testset "a kerned pair moves the second character" begin
        box = measure_string(measure, "AV", ubuntu)
        @test box.width ≈ (663 - 62 + 656) * 0.02
        offsets = compute_caret_offsets(measure, "AV", ubuntu)
        # The caret after "A" stands where "V" starts: after the kerning, so
        # before the advance of "A" alone (13.26).
        @test offsets ≈ [0.0, (663 - 62) * 0.02, (663 - 62 + 656) * 0.02]
        @test offsets[end] == box.width
        @test box.ascent ≈ 18.64
        @test box.descent ≈ 3.78
        @test box.line_gap ≈ 0.56
    end

    @testset "a pair can also move apart" begin
        # W–W is +12 in Ubuntu: the second W starts later than one advance.
        offsets = compute_caret_offsets(measure, "WW", ubuntu)
        advance = offsets[end] - offsets[2]
        @test offsets[2] ≈ advance + 12 * 0.02
    end

    @testset "a fallback glyph brings the metrics of its own font" begin
        # Ubuntu Mono has no arrow; DejaVu Sans Mono draws it, and DejaVu reaches
        # higher and lower than Ubuntu Mono.
        mono = StyleFont("Ubuntu Mono", 20)
        plain = measure_string(measure, "ab", mono)
        mixed = measure_string(measure, "a→b", mono)
        @test plain.ascent ≈ 16.6
        @test plain.descent ≈ 3.4
        @test mixed.ascent ≈ 1901 * 20 / 2048
        @test mixed.descent ≈ 483 * 20 / 2048
        @test compute_caret_offsets(measure, "a→b", mono)[end] == mixed.width
    end

    @testset "an empty string has the metrics of its font and no width" begin
        box = measure_string(measure, "", ubuntu)
        metrics = get_font_metrics(measure, ubuntu)
        @test box.width == 0
        @test (box.ascent, box.descent, box.line_gap) ==
              (metrics.ascent, metrics.descent, metrics.line_gap)
        @test compute_caret_offsets(measure, "", ubuntu) == [0.0]
    end

    @testset "a presentation selector has no width" begin
        @test measure_string(measure, "☀️", ubuntu).width == measure_string(measure, "☀", ubuntu).width
        @test length(compute_caret_offsets(measure, "☀️", ubuntu)) == 3
    end

    @testset "a fixed measure answers fixed numbers, per font where it is told" begin
        mono = StyleFont("Ubuntu Mono", 20)
        fixed = FixedMeasure(8, 12, 4, 1; fonts = Dict(mono => FontMetrics(10, 3, 0)))
        box = measure_string(fixed, "abc", ubuntu)
        @test (box.width, box.ascent, box.descent, box.line_gap) == (24.0, 12.0, 4.0, 1.0)
        other = measure_string(fixed, "abc", mono)
        @test (other.ascent, other.descent, other.line_gap) == (10.0, 3.0, 0.0)
        @test compute_caret_offsets(fixed, "abc", ubuntu) == [0.0, 8.0, 16.0, 24.0]
        # A font built again with the same face and size is the same font.
        @test get_font_metrics(fixed, StyleFont(mono.family, mono.size)).ascent == 10.0
    end

end
end
