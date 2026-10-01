"""
    test_julia_code_pieces()

A field of code whose language is `:julia` colors the tokens of its text, and the
pieces cover the text.
"""
function test_julia_code_pieces()
@testset "the pieces of Julia code" begin
    widget = ProjecturedPlatform.WidgetModule
    style = ProjecturedPlatform.StyleModule
    pieces_of(text) = widget.compute_code_pieces(Val(:julia), text)
    # The text of each piece, with its color.
    function colored(text)
        characters = collect(text)
        out = Pair{String,Any}[]
        start = 0
        for (count, color) in pieces_of(text)
            push!(out, String(characters[(start + 1):(start + count)]) => color)
            start += count
        end
        out
    end
    text = ":id > 3 && startswith(:name, \"B\") # a note"
    @test sum(first, pieces_of(text)) == length(text)
    found = Dict(colored(text))
    @test found[":id"] == style.color_solarized_violet
    @test found["3"] == style.color_solarized_green
    @test found["&&"] == style.color_solarized_cyan
    @test found["\"B\""] == style.color_solarized_green
    @test found["# a note"] == style.color_solarized_gray
    @test found["startswith"] === nothing
    @test pieces_of("") == [(0, nothing)]
    # The counts are characters, also for a character of more than one byte.
    @test sum(first, pieces_of("é ∈ :x")) == length("é ∈ :x")
end
end
