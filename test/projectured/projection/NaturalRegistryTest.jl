struct NaturalRegistryTestDocument <: Document end
struct NaturalRegistryTestProjection <: Projection
    name::Symbol
end

"""
    test_natural_registry()

A ready-made row of `register_natural_syntax!(pairs...)` is a row of the renderer
table, and it comes before the rows of the syntax factories. The test puts the
table back as it found it, so no test type stays in it.
"""
function test_natural_registry()
    saved = copy(NaturalModule._SYNTAX_PAIRS)
    try
        first_row = NaturalRegistryTestProjection(:first)
        register_natural_syntax!(NaturalRegistryTestDocument => first_row)
        register_natural_syntax!(NaturalRegistryTestDocument => NaturalRegistryTestProjection(:second))
        entries = get_natural_syntax_entries()

        @testset "a type registered twice keeps the first row" begin
            rows = [last(e) for e in entries if first(e) === NaturalRegistryTestDocument]
            @test length(rows) == 1
            @test only(rows) === first_row
        end

        @testset "a ready-made row comes before the factory rows" begin
            # The markdown domain registers a syntax factory for `MarkdownDocument`.
            row = findfirst(e -> first(e) === NaturalRegistryTestDocument, entries)
            factory_row = findfirst(e -> first(e) === MarkdownDocument, entries)
            @test row !== nothing && factory_row !== nothing
            @test row < factory_row
        end
    finally
        copy!(NaturalModule._SYNTAX_PAIRS, saved)
    end

    @testset "the test leaves the natural table as it found it" begin
        @test NaturalModule._SYNTAX_PAIRS == saved
    end
end
