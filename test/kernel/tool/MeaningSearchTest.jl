"""
The search by description: the meaning model a backend gives a `ToolSet`, and
how the vectors it computes rank what a description finds.
"""

using Test
using ProjecturedKernel.ToolModule
using ProjecturedKernel.LlmModule: has_meaning_model, get_meaning_model_name,
                                   compute_meaning_vectors, bind_meaning_model!
using ProjecturedKernelExample: FakeLlm

function test_meaning_search()
@testset "Meaning search" begin

    @testset "a backend with a meaning model gives it to a tool set" begin
        llm = FakeLlm("ok"; meaning_model = "bag-of-words")
        @test has_meaning_model(llm)
        @test get_meaning_model_name(llm) == "fake/bag-of-words"
        vectors = compute_meaning_vectors(llm, ["plot a vector", "draw the vector", "x"])
        @test size(vectors) == (64, 3)
        @test eltype(vectors) == Float32
        # Two texts that share a word share a place; a text of no word is zero.
        @test sum(vectors[:, 1] .* vectors[:, 2]) > 0
        @test all(iszero, vectors[:, 3])

        set = ToolSet()
        @test set.meaning_model === nothing
        @test bind_meaning_model!(set, llm) === set
        @test set.meaning_model isa MeaningModel
        @test set.meaning_model.name == "fake/bag-of-words"
        @test size(set.meaning_model.compute(["plot"], :query)) == (64, 1)
    end

    @testset "a backend without one leaves the tool set as it is" begin
        plain = FakeLlm("ok")
        @test !has_meaning_model(plain)
        @test_throws ErrorException compute_meaning_vectors(plain, ["plot"])
        @test_throws ErrorException get_meaning_model_name(plain)

        fresh = ToolSet()
        bind_meaning_model!(fresh, plain)
        @test fresh.meaning_model === nothing

        bound = ToolSet()
        bind_meaning_model!(bound, FakeLlm("ok"; meaning_model = "bag-of-words"))
        bind_meaning_model!(bound, plain)
        @test bound.meaning_model.name == "fake/bag-of-words"

        # `set_meaning_model!` is how one is taken away.
        @test set_meaning_model!(bound, nothing).meaning_model === nothing
    end

end
end # test_meaning_search
