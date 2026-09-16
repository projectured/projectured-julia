# A character that a font lacks is drawn in a fallback font and measured in the
# same font, so a line is drawn as wide as the layout measured it. Ubuntu Mono
# has no arrow; DejaVu Sans Mono has one.
function test_font_fallback()
@testset "FontFallback" begin

    regular = font_ubuntu_monospace_regular_20
    arrow = UInt32('→')

    @testset "the font that draws a character" begin
        # The font draws what it carries.
        @test find_glyph_font_file(regular.filename, UInt32('a')) == regular.filename
        # DejaVu Sans Mono draws an arrow that Ubuntu Mono lacks, in the weight of
        # the text.
        @test basename(find_glyph_font_file(regular.filename, arrow)) == "DejaVuSansMono.ttf"
        @test basename(find_glyph_font_file(font_ubuntu_monospace_bold_16.filename, arrow)) ==
              "DejaVuSansMono-Bold.ttf"
        # Noto Emoji draws a pictograph, even for a font that carries its own.
        @test basename(find_glyph_font_file(font_dejavu_sans_regular_20.filename, UInt32('😀'))) ==
              "NotoEmoji-Regular.ttf"
        # No font carries a private-use character.
        @test find_glyph_font_file(regular.filename, UInt32(0xE000)) === nothing
    end

    @testset "a fallback glyph is measured in its own font" begin
        plain = measure_truetype_text("ab", regular)[1]
        dejavu_arrow = measure_truetype_text("→", font_dejavu_monospace_regular_20)[1]
        # Ubuntu Mono's box is as wide as a letter; DejaVu's arrow is wider.
        @test dejavu_arrow > plain ÷ 2
        @test measure_truetype_text("a→b", regular)[1] == plain + dejavu_arrow
        # A presentation selector has no width.
        @test measure_truetype_text("☀️", regular) == measure_truetype_text("☀", regular)
        # A text the font carries in full measures as it did.
        @test measure_truetype_text("hello", regular)[1] == 5 * (plain ÷ 2)
    end

end
end
