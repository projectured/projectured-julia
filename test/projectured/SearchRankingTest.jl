"""
Rankings of a search compared on the same questions: the shapes that score, the
shapes that choose before they score, and the counts the measurement prints.

The classifiers are replaced here by functions that answer from the names, so
the test reads no model and no server.
"""

using Test

_make_ranking_entry(qualname, summary = "") =
    ToolModule._ApiEntry("function", qualname, last(split(qualname, '.')) * "()", summary,
                         summary, summary)

function test_search_ranking()
@testset "rankings of a search compared" begin
    entries = [_make_ranking_entry("Panes.open_pane!", "Put a document in a new tab."),
               _make_ranking_entry("Panes.close_pane!", "Close a pane."),
               _make_ranking_entry("Studies.open_study!", "Open the study of the folder."),
               _make_ranking_entry("Studies.save_study!", "Write the study as a folder.")]
    question = SearchQuestion(("open it", "A plot is in a variable.", ["open_pane!"], :api, :pair))
    # A score that likes the texts that name a tab, and that reads the context.
    seen = SearchQuestion[]
    score(asked, texts) = (push!(seen, asked);
                           ([occursin("tab", text) ? 0.9 : 0.1 for text in texts], 10 * length(texts)))

    @testset "a classifier ranks what its first stage offers" begin
        ranked, tokens = make_classifier_ranker("all", score).rank(question, entries)
        @test ranked[1].qualname == "Panes.open_pane!"
        @test tokens == 40
        @test seen[end].context == "A plot is in a variable."
        first_stage = [SearchRanker("two", (q, e) -> (e[3:4], 0))]
        ranked, _ = make_classifier_ranker("pool", score; first_stage = first_stage, depth = 1,
                                           context = false).rank(question, entries)
        @test [entry.qualname for entry in ranked] == ["Studies.open_study!"]
        @test seen[end].context == ""
    end

    @testset "a candidate shows its name, its documentation and its calls" begin
        text = make_candidate_text(entries[1]; call_sites = "- A.jl:3: `open_pane!(e, d)`")
        @test startswith(text, "name: Panes.open_pane!\nkind: function\nsignature: open_pane!()")
        @test endswith(text, "calls:\n- A.jl:3: `open_pane!(e, d)`")
    end

    # A choice that likes the options whose line names what the sentence names.
    choose(asked, options) = ([occursin("open", last(option)) ? 0.8 : 0.2 for option in options],
                              length(options))

    @testset "a cascade keeps the best of each group and scores them" begin
        ranked, tokens = make_cascade_ranker("cascade", choose, score; keep = 2).rank(question, entries)
        @test Set(entry.qualname for entry in ranked) == Set(["Panes.open_pane!", "Studies.open_study!"])
        @test ranked[1].qualname == "Panes.open_pane!"
        @test tokens == 4 + 20
    end

    @testset "a tree chooses a package, a module, then names" begin
        package_of = Dict("Panes" => "Window", "Studies" => "Study")
        descriptions = Dict("Window" => "the window: open and close panes",
                            "Study" => "the study", "Panes" => "open a pane",
                            "Studies" => "a study")
        ranked, _ = make_tree_ranker("tree", choose, score; package_of = package_of,
                                     descriptions = descriptions, beam = 1,
                                     keep = 2).rank(question, entries)
        # The beam of one keeps the package whose line says "open", and only
        # its names are scored.
        @test [entry.qualname for entry in ranked] == ["Panes.open_pane!", "Panes.close_pane!"]
    end

    @testset "the measurement counts places per question and per ranker" begin
        by_score = make_classifier_ranker("score", score)
        reversed = SearchRanker("reversed", (q, e) -> (reverse(e), 0))
        io = IOBuffer()
        rows = measure_search_rankings(; entries = entries, questions = [question],
                                       rankers = [by_score, reversed], io = io)
        @test [row.best for row in rows] == [1, 4]
        printed = String(take!(io))
        @test occursin("1 / 1 / 1 / 1 of 1", printed)
        @test occursin("0 / 1 / 0", printed)
    end
end
end
