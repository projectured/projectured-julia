"""
Tests for the `.pred` notation: a document written as the call that builds it,
and read back from that text.
"""

using Test
using ProjecturedPlatform.SerializationModule
using ProjecturedPlatform.StyleModule: StyleFont, StyleColor
using ProjecturedPlatform.TextModule: TextBlock, TextString

function test_pred_file()
@testset "PredFile: a document as the call that builds it" begin

    @testset "a value document with no keyword form reads back from its fields" begin
        font = StyleFont("DejaVu Sans", 14; weight = 700, italic = true)
        text = print_pred_text(font)
        loaded = parse_pred_text(text)
        @test loaded isa StyleFont
        @test (loaded.family, loaded.size, loaded.weight, loaded.italic) == ("DejaVu Sans", 14, 700, true)
        @test print_pred_text(loaded) == text
    end

    @testset "a styled text reads back with its font and its colour" begin
        block = TextBlock([TextString("hello", StyleFont("DejaVu Sans", 14), StyleColor(1.0, 0.0, 0.0, 1.0))])
        text = print_pred_text(block)
        loaded = parse_pred_text(text)
        string = only(loaded.elements)
        @test string.content == "hello"
        @test string.font.family == "DejaVu Sans"
        @test string.font_color.red == 1.0
        @test print_pred_text(loaded) == text
    end

end
end
