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
registered type, whatever the order of the registrations.
"""
function test_natural_notation()
    # The root is registered first: a lookup that takes the first match fails.
    register_natural_notation!(NaturalNotationTestRoot, :syntax, () -> NaturalNotationTestRootProjection())
    register_natural_notation!(NaturalNotationTestLeaf, :syntax, () -> NaturalNotationTestLeafProjection())
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
end
