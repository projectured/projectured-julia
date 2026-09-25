# A character that the font lacks is a run of its own, in the font that the style
# package names, when SDL measures a text. The run helpers are internal to the
# backend, so they are qualified. `test_sdl_text_pen_positions` tests where SDL
# draws such a character.
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

end
end
