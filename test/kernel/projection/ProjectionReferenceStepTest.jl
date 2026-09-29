"""
`ProjectionReferenceStep` — the step of a caret on an element that a projection
printed.

Confirms that two carets that `make_introduced_reference` builds apart, for one
projection and one output path, are equal, have one hash, and are one key of a
`Set`.
"""

using Test
using ProjecturedKernel.ProjectionModule: Projection, make_introduced_reference
using ProjecturedKernel.ReferenceModule: Reference, FieldReferenceStep, RangeReferenceStep

struct IntroducedCaretProbe <: Projection end
struct IntroducedCaretNode end

function test_projection_reference_step()
@testset "ProjectionReferenceStep" begin

    @testset "two carets on one introduced element are one key" begin
        projection = IntroducedCaretProbe()
        make_caret() = make_introduced_reference(projection, IntroducedCaretNode,
            Reference(FieldReferenceStep("close"), RangeReferenceStep(0, 0)))
        first_caret, second_caret = make_caret(), make_caret()
        @test first_caret == second_caret
        @test hash(first_caret) == hash(second_caret)
        @test length(Set([first_caret, second_caret])) == 1
    end

end
end # test_projection_reference_step
