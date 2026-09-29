"""
`ProjectionModule` — the fallback method of each generic, for a projection with
no method of its own.

Confirms that the default backward map of a place that the projection printed
answers the canonical introduced caret: the caret that
`make_introduced_reference` builds, whose terminal records `Position`.
"""

using Test
using ProjecturedKernel.DocumentModule: @document, Document
using ProjecturedKernel.IoMapModule: SimpleIoMap
using ProjecturedKernel.ProjectionModule: Projection, make_introduced_reference,
    map_reference_backward
using ProjecturedKernel.ReferenceModule: Reference, FieldReferenceStep, RangeReferenceStep,
    Position

# A test-local projection with no method of its own: it answers what the defaults
# of the kernel answer.
struct DefaultsProbeProjection <: Projection end

@document struct DefaultsProbeLeaf
    text::String
end

function test_projection_defaults()
@testset "Projection defaults" begin

    @testset "the backward map of a printed place is the canonical introduced caret" begin
        projection = DefaultsProbeProjection()
        leaf = DefaultsProbeLeaf("text", nothing)
        iomap = SimpleIoMap(projection, leaf, nothing)
        printed = Reference(FieldReferenceStep("close"), RangeReferenceStep(0, 0))
        caret = map_reference_backward(projection, iomap, printed)
        @test caret == make_introduced_reference(projection, leaf, printed)
        @test caret.tail.type === Position
    end

end
end # test_projection_defaults
