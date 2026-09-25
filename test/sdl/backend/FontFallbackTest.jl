# The SDL renderer draws a character that the font lacks in the font that the
# style package names, and measures it in that font. The run helpers are internal
# to the backend, so they are qualified.
function test_sdl_font_fallback()
@testset "SDL font fallback" begin

    font = font_ubuntu_monospace_regular_20
    primary = ProjecturedSdl._get_font(font, 1.0)

    @testset "a character the font lacks is a run of its own" begin
        runs = ProjecturedSdl._font_runs("a→b", font, primary, 1.0)
        @test [text for (_, text) in runs] == ["a", "→", "b"]
        @test runs[1][1] == primary
        @test runs[2][1] != primary
        @test runs[3][1] == primary
        @test ProjecturedSdl._font_runs("abc", font, primary, 1.0) == [(primary, "abc")]
    end

    @testset "SDL measures a line as the layout does" begin
        # SDL rasterizes at the device size and divides back, so the two
        # measurers can differ by the rounding of one pixel.
        with_arrow = measure_sdl_text("a→b", font)[1]
        @test abs(with_arrow - measure_truetype_text("a→b", font)[1]) <= 1
        @test with_arrow > measure_sdl_text("abc", font)[1]
    end

end
end
