# The pattern of a highlight or a filter, from the fields that a person edits:
# literal text, a regular expression, the flag for case, an empty pattern, and a
# pattern that does not compile.

function test_text_pattern()
@testset "TextPattern" begin

    @testset "literal text matches as written" begin
        dot = make_text_pattern("a.b", false, false)
        @test occursin(dot, "a.b")
        @test !occursin(dot, "axb")
        call = make_text_pattern("f(x) [1] {2} ^\$|?*+\\", false, false)
        @test occursin(call, "say f(x) [1] {2} ^\$|?*+\\ now")
    end

    @testset "a regular expression matches as an expression" begin
        dot = make_text_pattern("a.b", true, false)
        @test occursin(dot, "axb")
        lines = make_text_pattern("^do", true, false)
        @test occursin(lines, "dolor")
        @test !occursin(lines, "a dolor")
    end

    @testset "case matters unless the flag says otherwise" begin
        @test !occursin(make_text_pattern("Dolor", false, false), "dolor")
        @test occursin(make_text_pattern("Dolor", false, true), "dolor")
        @test occursin(make_text_pattern("D.lor", true, true), "dolor")
    end

    @testset "an empty pattern and a pattern that does not compile give nothing" begin
        @test make_text_pattern("", false, false) === nothing
        @test make_text_pattern("", true, true) === nothing
        @test make_text_pattern("dolor(", true, false) === nothing
        @test make_text_pattern("[a-", true, false) === nothing
        # The same text as literal text compiles, because it is escaped.
        @test occursin(make_text_pattern("dolor(", false, false), "dolor(")
    end

end
end # test_text_pattern
