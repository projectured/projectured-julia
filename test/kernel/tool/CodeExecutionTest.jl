"""
What `execute_julia_code` answers: what the code printed, the value of the last
expression shown or described, "Done." for nothing, and the nearest declared
names for a name nobody defined.
"""

using Test
using ProjecturedKernel.ToolModule

# A declared API with names a guess lands near.
module NearToy
export count_rows, draw_arrow, make_result_plot
"""Count the rows of a table."""
count_rows(table) = 0
"""Draw an arrow."""
draw_arrow(canvas) = nothing
"""A chart of a frame."""
make_result_plot(frame) = nothing
end

function test_code_execution()
@testset "Code execution" begin
    set = ToolSet(; api = Module[NearToy])
    run = code -> execute_julia_code(set, nothing, code)

    @testset "a short value is shown, a long one is described" begin
        @test run("1 + 1") == "2\n"
        @test run("\"a word\"") == "\"a word\"\n"
        # A long string is prose a verb answers to be read: whole, without quotes.
        @test run("repeat(\"word \", 100)") == repeat("word ", 100) * "\n"
        @test run("Text(\"one\\ntwo\\nthree\")") == "one\ntwo\nthree\n"
        # A long vector shows as Julia's own elided line, which is short.
        elided = run("collect(1:1000)")
        @test startswith(elided, "[1, 2, 3") && occursin("…", elided) && !occursin("500", elided)
        # A value whose form is long even limited — a tuple is never elided — is
        # described, not shown.
        long = run("Tuple(1:1000)")
        @test startswith(long, "The last value is NTuple{1000, Int64}.")
        @test occursin("println(first(x, 10))", long)
        @test !occursin("500", long)
        # What the code prints comes first, and is never cut.
        printed = run("for i in 1:300\n  println(i)\nend\nTuple(1:1000)")
        @test startswith(printed, join(string.(1:300), '\n') * "\nThe last value is NTuple")
    end

    @testset "nothing is Done., unless the code printed" begin
        @test run("nothing") == "Done."
        @test run("x = 3; nothing") == "Done."
        @test run("println(\"hi\"); nothing") == "hi\n"
    end

    @testset "a name nobody defined is answered with the nearest declared names" begin
        answer = run("count_row([1])")
        @test occursin("UndefVarError", answer)
        @test occursin("Did you mean: `count_rows`", answer)
        answer = run("plot_result(1)")
        @test occursin("Did you mean: `make_result_plot`", answer)
        @test !occursin("Did you mean", run("zzz_nothing_near(1)"))
        # A name that shares a word comes first; a name an edit or two away comes
        # too; a name that is neither does not.
        near = ProjecturedKernel.ToolModule._find_nearest_names(
            "draw_arrows", ["draw_arrow", "count_rows", "make_result_plot", "draw_arrowz"])
        @test near == ["draw_arrow", "draw_arrowz"]
        @test ProjecturedKernel.ToolModule._find_nearest_names("zzz", ["count_rows"]) == String[]
    end
end
end # test_code_execution
