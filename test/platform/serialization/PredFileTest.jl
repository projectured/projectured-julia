"""
Tests for the `.pred` notation: a document written as the call that builds it,
and read back from that text.
"""

using Test
using ProjecturedPlatform.SerializationModule
using ProjecturedPlatform.StyleModule: StyleFont, StyleColor
using ProjecturedPlatform.TextModule: TextBlock, TextString
using ProjecturedKernel.DocumentModule: @document

"""
A document that holds an operator, as a document of Julia code holds `:+` or
`:(=)`.
"""
@document struct PredFileOperator
    operator::Symbol
end

"""
A document that holds a name and the folds of a view of it, which are state of
the view and no part of what it says.
"""
@document struct PredFileFolds
    name::String = ""
    folded::Any = String[]
end

ProjecturedKernel.DocumentModule.get_view_state_fields(::Type{<:PredFileFolds}) = (:folded,)

function test_pred_file()
@testset "PredFile: a document as the call that builds it" begin

    @testset "a field of view state stays out of the file" begin
        document = PredFileFolds(name = "outline", folded = ["Q1"])
        text = print_pred_text(document)
        @test occursin("outline", text)
        @test !occursin("folded", text) && !occursin("Q1", text)
        loaded = parse_pred_text(text)
        @test loaded.name == "outline" && isempty(loaded.folded)
        @test is_view_state_field(PredFileFolds, :folded)
        @test !is_view_state_field(PredFileFolds, :name)
        @test is_view_state_field(PredFileFolds, :selection)
    end

    @testset "a value document with no keyword form reads back from its fields" begin
        font = StyleFont("DejaVu Sans", 14; weight = 700, italic = true)
        text = print_pred_text(font)
        loaded = parse_pred_text(text)
        @test loaded isa StyleFont
        @test (loaded.family, loaded.size, loaded.weight, loaded.italic) == ("DejaVu Sans", 14, 700, true)
        @test print_pred_text(loaded) == text
    end

    @testset "a symbol reads back, an operator too, and one that can not is refused" begin
        for symbol in (:name, :+, :(=), :(==), :(::), :&&, :->)
            text = sprint(io -> SerializationModule._print_pred_value(io, symbol, "", 0))
            @test SerializationModule._evaluate_pred(Meta.parse(text)) === symbol
        end
        @test_throws FileCutException sprint(io -> SerializationModule._print_pred_value(io, Symbol("a b"), "", 0))
        @test parse_pred_text(print_pred_text(PredFileOperator(:(=)))).operator === :(=)
    end

    @testset "a styled text reads back with its font and its colour" begin
        block = TextBlock(TextLine([TextString("hello", StyleFont("DejaVu Sans", 14), StyleColor(1.0, 0.0, 0.0, 1.0))]))
        text = print_pred_text(block)
        loaded = parse_pred_text(text)
        string = only(only(loaded.elements).elements)
        @test string.content == "hello"
        @test string.font.family == "DejaVu Sans"
        @test string.font_color.red == 1.0
        @test print_pred_text(loaded) == text
    end

end
end
