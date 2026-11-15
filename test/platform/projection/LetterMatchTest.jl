# The match of a typed query by its letters in order, and the order of the texts
# that match.

function test_letter_match()
@testset "a query matches by its letters in order" begin

@testset "the letters come in order, need not touch, and have any case" begin
    @test find_letter_match("panprog", "PaneProgram.jl") !== nothing
    @test find_letter_match("PANE", "pane.md") !== nothing
    @test find_letter_match("gorp", "PaneProgram.jl") === nothing
    @test find_letter_match("panes", "pane") === nothing
    @test find_letter_match("", "anything") == 0
end

# Paths with the index of the first character of their name.
_name_start(path) = something(findlast(==('/'), collect(path)), 0) + 1

@testset "a match at the start of a word ranks higher" begin
    texts = ["source/kopp.jl", "source/PaneProgram.jl"]
    @test find_letter_matches("pp", texts; name_start = _name_start) == [2, 1]
end

@testset "a match in the name ranks higher than a match in the folder" begin
    texts = ["pane/notes.md", "notes/pane.md"]
    @test find_letter_matches("pane", texts; name_start = _name_start) == [2, 1]
end

@testset "of equal matches, the shorter text comes first, then the given order" begin
    texts = ["test/platform/pane/PaneProgramTest.jl", "source/platform/pane/PaneProgram.jl",
             "b/PaneProgram.jl", "a/PaneProgram.jl"]
    @test find_letter_matches("panprog", texts; name_start = _name_start) == [3, 4, 2, 1]
end

@testset "an empty query keeps every text in its order" begin
    @test find_letter_matches("", ["b", "a", "c"]) == [1, 2, 3]
end

@testset "a query over 100,000 paths" begin
    paths = ["source/platform/folder$(index ÷ 100)/File$(index)Name.jl" for index in 1:100_000]
    find_letter_matches("fnj", paths[1:10]; name_start = _name_start)
    seconds = @elapsed find_letter_matches("fnj", paths; name_start = _name_start)
    @info "letters in order over 100,000 paths" seconds
    @test seconds < 5
end

end
end # test_letter_match
