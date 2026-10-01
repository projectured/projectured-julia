struct NaturalRegistryTestDocument <: Document end
struct NaturalRegistryTestProjection <: Projection
    name::Symbol
    appearance::Appearance
end

"""
    test_natural_registry()

A syntax row is registered as a factory, which runs on every table build with
the `Appearance` that the build is given, so two editors get two projections,
each with the appearance of its editor. A key registered twice keeps the first
factory. The test puts the table back as it found it, so no test row stays in it.
"""
function test_natural_registry()
    saved = copy(NaturalModule._SYNTAX_FACTORIES)
    try
        register_natural_syntax!(:natural_registry_test, (; appearance) ->
            Pair{Type,Any}[NaturalRegistryTestDocument =>
                           NaturalRegistryTestProjection(:first, appearance)])
        register_natural_syntax!(:natural_registry_test, (; appearance) ->
            Pair{Type,Any}[NaturalRegistryTestDocument =>
                           NaturalRegistryTestProjection(:second, appearance)])
        rows_of(entries) = [last(e) for e in entries if first(e) === NaturalRegistryTestDocument]

        @testset "a key registered twice keeps the first factory" begin
            rows = rows_of(get_natural_syntax_entries(appearance = Appearance()))
            @test length(rows) == 1
            @test only(rows).name === :first
        end

        @testset "each build gets its own row, with the appearance it is given" begin
            one, two = Appearance(), Appearance()
            first_row = only(rows_of(get_natural_syntax_entries(appearance = one)))
            second_row = only(rows_of(get_natural_syntax_entries(appearance = two)))
            @test first_row !== second_row
            @test first_row.appearance === one
            @test second_row.appearance === two
        end
    finally
        copy!(NaturalModule._SYNTAX_FACTORIES, saved)
    end

    @testset "the test leaves the natural table as it found it" begin
        @test NaturalModule._SYNTAX_FACTORIES == saved
    end
end
