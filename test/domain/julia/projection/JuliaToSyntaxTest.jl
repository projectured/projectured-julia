"""
Tests of the Julia notation, `JuliaToSyntax`, printed through the chain to a string.

An edit of a printed document reaches the output of the same IoMap: a caller
reads `.output` again and does not print again.
"""

using Test

_julia_text_projection() = ChainingProjection(RecursiveProjection(JuliaToSyntax()),
                                              RecursiveProjection(SyntaxToText()),
                                              RecursiveProjection(TextToString()))

"""
    test_julia_to_syntax()

The Julia notation follows each edit of an optional field through the same IoMap.
"""
function test_julia_to_syntax()
@testset "JuliaToSyntax" begin
    @testset "a range shows its step only while it has one" begin
        assignment = parse_julia("x = 1:2:5")
        range = assignment.value
        iomap = print_document(_julia_text_projection(), assignment)
        @test String(iomap.output) == "x = 1:2:5"
        range.step = nothing
        @test String(iomap.output) == "x = 1:5"
        range.step = parse_julia("3")
        @test String(iomap.output) == "x = 1:3:5"
    end
end
end
