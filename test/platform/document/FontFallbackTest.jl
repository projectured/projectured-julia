# A character that a font lacks is drawn in a fallback font and measured in the
# same font, so a line is drawn as wide as the layout measured it. Ubuntu Mono
# has no arrow; DejaVu Sans Mono has one.
function test_font_fallback()
@testset "FontFallback" begin

    regular = StyleFont("Ubuntu Mono", 20)
    arrow = UInt32('→')

    @testset "the font that draws a character" begin
        # The font draws what it carries.
        @test find_glyph_font_file(regular, UInt32('a')) == compute_font_path(regular)
        # DejaVu Sans Mono draws an arrow that Ubuntu Mono lacks, in the weight of
        # the text.
        @test basename(find_glyph_font_file(regular, arrow)) == "DejaVuSansMono.ttf"
        @test basename(find_glyph_font_file(StyleFont("Ubuntu Mono", 16; weight = 700), arrow)) ==
              "DejaVuSansMono-Bold.ttf"
        # Noto Emoji draws a pictograph, even for a font that carries its own.
        @test basename(find_glyph_font_file(StyleFont("DejaVu Sans", 20), UInt32('😀'))) ==
              "NotoEmoji-Regular.ttf"
        # No font carries a private-use character.
        @test find_glyph_font_file(regular, UInt32(0xE000)) === nothing
    end

    @testset "the fallback faces follow the weight and stand upright" begin
        files(font) = basename.(get_fallback_font_files(font))
        regular_chain = ["DejaVuSansMono.ttf", "NotoEmoji-Regular.ttf"]
        bold_chain = ["DejaVuSansMono-Bold.ttf", "DejaVuSansMono.ttf", "NotoEmoji-Regular.ttf"]
        @test files(StyleFont("Ubuntu Mono", 20)) == regular_chain
        @test files(StyleFont("Ubuntu", 20; italic = true)) == regular_chain
        @test files(StyleFont("Inconsolata", 18)) == regular_chain
        @test files(StyleFont("Ubuntu", 20; weight = 700)) == bold_chain
        @test files(StyleFont("Liberation Sans", 20; weight = 700, italic = true)) == bold_chain
    end

    @testset "a fallback glyph is measured in its own font" begin
        plain = first(compute_text_extent("ab", regular))
        dejavu_arrow = first(compute_text_extent("→", StyleFont("DejaVu Sans Mono", 20)))
        # Ubuntu Mono's box is as wide as a letter; DejaVu's arrow is wider.
        @test dejavu_arrow > plain ÷ 2
        @test first(compute_text_extent("a→b", regular)) == plain + dejavu_arrow
        # A presentation selector has no width.
        @test measure_string(FontFileMeasure(), "☀️", regular) == measure_string(FontFileMeasure(), "☀", regular)
        # A text the font carries in full measures as it did.
        @test first(compute_text_extent("hello", regular)) == 5 * (plain ÷ 2)
    end

end
end
