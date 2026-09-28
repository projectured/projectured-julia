"""
The call sites of a search corpus: which nodes of a file are calls of a name, the
function each is in, and the order in which a search shows them.

A call site is text a ranking reads, so a definition read as a call, or a field
read as a name, puts words in front of the ranking that no caller wrote.
"""

using Test

function test_call_site()
@testset "the call sites of a search corpus" begin
    folder = mktempdir()
    source = """
        function make_card(title)
            card = WidgetCard(; title = title)
            open_pane!(editor, card)
            PaneModule.focus_pane!(editor)
            editor.tools.search(x)
            Dict{String,Int}()
            round.(values)
        end
        short_form(x) = open_pane!(x, nothing)
        open_pane!(nothing, nothing)
        """
    write(joinpath(folder, "Calls.jl"), source)
    write(joinpath(folder, "Guide.md"), """
        # A guide

        Text that names open_pane!(x) is prose, not code.

        ```julia
        julia> focus_pane!(editor)
        ```
        """)
    write(joinpath(folder, "Excluded.jl"), "open_pane!(1, 2)\n")
    sites = collect_call_sites([folder]; excluded = ("Excluded.jl",))

    @testset "a call is found, and a definition is not" begin
        @test sort([site.line for site in sites["open_pane!"]]) == [3, 9, 10]
        @test !haskey(sites, "make_card")
        @test !haskey(sites, "short_form")
        @test length(sites["WidgetCard"]) == 1
    end

    @testset "a qualified call is the name, and a call of a field is nothing" begin
        @test length(sites["focus_pane!"]) == 2
        @test !haskey(sites, "search")
        @test haskey(sites, "Dict")
        @test haskey(sites, "round")
    end

    @testset "a call site knows its function and its line" begin
        inside = only(site for site in sites["WidgetCard"])
        @test inside.caller == "make_card(title)"
        @test inside.text == "card = WidgetCard(; title = title)"
        @test only(site for site in sites["open_pane!"] if site.line == 9).caller ==
              "short_form(x)"
        @test only(site for site in sites["open_pane!"] if site.line == 10).caller == ""
    end

    @testset "a Julia block of a guide is read, and its prose is not" begin
        from_guide = [site for site in sites["focus_pane!"] if endswith(site.file, ".md")]
        @test length(from_guide) == 1
        @test only(from_guide).line == 6
        @test only(from_guide).text == "focus_pane!(editor)"
    end

    @testset "an outside call comes first, one per function, one per file first" begin
        home = joinpath(folder, "home")
        at(file, line, caller) = CallSite("f", file, line, "f()", caller)
        ranked = rank_call_sites([at(joinpath(home, "A.jl"), 1, "g()"),
                                  at(joinpath(home, "A.jl"), 5, "g()"),
                                  at(joinpath(folder, "B.jl"), 3, "h()"),
                                  at(joinpath(folder, "B.jl"), 9, "k()"),
                                  at(joinpath(folder, "C.jl"), 2, "")], home)
        @test [(basename(site.file), site.line) for site in ranked] ==
              [("B.jl", 3), ("C.jl", 2), ("A.jl", 1), ("B.jl", 9)]
        text = format_call_sites(ranked[1:1]; root = folder)
        @test text == "- B.jl:3 in `h()`: `f()`"
    end
end
end
