# A family of three documents: a notation on the root answers for every document
# under it, and a notation on a subtype answers for that subtype.
abstract type NaturalNotationTestRoot <: Document end
struct NaturalNotationTestLeaf <: NaturalNotationTestRoot end
struct NaturalNotationTestOther <: NaturalNotationTestRoot end
struct NaturalNotationTestRootProjection <: Projection end
struct NaturalNotationTestLeafProjection <: Projection end

"""
    test_natural_notation()

The lookup of a natural notation and of a natural format takes the most derived
registered type, whatever the order of the registrations. The test puts the
tables back as it found them, so no test type stays in them.
"""
function test_natural_notation()
    tables = (NaturalModule._NOTATIONS, NaturalModule._FORMATS)
    saved = map(copy, tables)
    try
        # The root is registered first: a lookup that takes the first match fails.
        register_natural_notation!(NaturalNotationTestRoot, :syntax, (; appearance) -> NaturalNotationTestRootProjection())
        register_natural_notation!(NaturalNotationTestLeaf, :syntax, (; appearance) -> NaturalNotationTestLeafProjection())
        register_natural_format!(NaturalNotationTestRoot, :natural_notation_test_root, ".nntroot")
        register_natural_format!(NaturalNotationTestLeaf, :natural_notation_test_leaf, ".nntleaf")

        # The one stage of a chain that stops at the rung of the notation.
        get_stage(chain) = only(chain.projections).child

        @testset "the most derived registered type gives the notation" begin
            @test get_stage(make_natural_projection(NaturalNotationTestLeaf(), :syntax)) isa
                  NaturalNotationTestLeafProjection
            @test get_stage(make_natural_projection(NaturalNotationTestOther(), :syntax)) isa
                  NaturalNotationTestRootProjection
        end

        @testset "the most derived registered type gives the format" begin
            @test get_natural_format(NaturalNotationTestLeaf) === :natural_notation_test_leaf
            @test get_natural_format(NaturalNotationTestOther) === :natural_notation_test_root
            @test get_natural_extension(NaturalNotationTestLeaf()) == ".nntleaf"
            @test get_natural_extension(NaturalNotationTestOther()) == ".nntroot"
        end
    finally
        foreach(copy!, tables, saved)
    end

    @testset "the test leaves the natural tables as it found them" begin
        @test all(map(==, tables, saved))
    end

    @testset "a format that is code turns a document into the Expr that runs it" begin
        @test has_natural_expression(:jl)
        @test !has_natural_expression(:json)
        call = parse_natural_text(:jl, "f(1, 2)")
        @test make_natural_expression(:jl, call) == make_julia_expression(call)
        @test_throws ErrorException make_natural_expression(:json, call)
    end
end
