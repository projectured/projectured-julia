"""
The scale corpus of this repository: the modules it declares, the questions
asked of it, and the measurement that answers them.

A question names a verb or a guide, and a name that is renamed or a guide that
moves makes the question a lie. That is what this holds: every expected name is
declared, every expected guide is there, and the measurement answers a row per
question. It reads no clock and needs no server; the numbers come from
`measure_projectured_search_scale!` on a machine that is not busy.
"""

using Test

function test_search_scale()
@testset "the scale corpus and its questions" begin
    modules = get_scale_search_modules()
    set = ToolModule.declare_api!(ToolModule.ToolSet(), modules)
    declared = Set(String(name) for entry in set.api for name in ToolModule.get_api_entry_names(entry))
    guides = Set(section.guide for section in ToolModule._guide_index())

    @testset "the corpus is large, and every question names something that is there" begin
        @test length(modules) == length(SCALE_SEARCH_MODULE_NAMES)
        # The size is the point of this corpus: a window's own declaration is
        # about a hundred names. The generated schema variants are not in it,
        # because they are not hits.
        @test length(ToolModule._api_index(set.api)) > 1200
        @test length(guides) > 50
        @test count(question -> question.kind === :api, SCALE_SEARCH_QUESTIONS) >= 20
        @test count(question -> question.kind === :guide, SCALE_SEARCH_QUESTIONS) >= 5
        for question in SCALE_SEARCH_QUESTIONS
            if question.kind === :api
                @test question.expected in declared
            else
                @test question.expected in guides
            end
        end
    end

    @testset "the measurement answers a row per question" begin
        # The build of the vectors reads the folder on a task of its own, so the
        # store is made here, while this folder is the one that is set.
        folder = mktempdir()
        ToolModule._MEANING_FOLDER[] = folder
        try
            store = ToolModule._get_meaning_store("fake/scale")
            @test dirname(store.path) == folder
            io = IOBuffer()
            rows = measure_projectured_search_scale!(;
                backend = FakeLlm("ok"; meaning_model = "scale"), io = io)
            @test length(rows) == length(SCALE_SEARCH_QUESTIONS)
            @test all(row -> row.word_rank >= 0 && row.meaning_rank >= 0, rows)
            # The words find what they spell: a sentence that holds no word of
            # its name is the hard case, and the numbers say how many there are.
            printed = String(take!(io))
            @test occursin("declared entries", printed)
            @test occursin("api by words: ", printed)
            @test occursin("guide by description: ", printed)
            @test occursin("mean reciprocal rank", printed)
            @test occursin("A search by words: mean ", printed)
        finally
            ToolModule._MEANING_FOLDER[] = ""
        end
    end
end
end # test_search_scale
