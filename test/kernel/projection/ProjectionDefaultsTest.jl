"""
`ProjectionModule` — the fallback method of each generic, for a projection with
no method of its own.

Confirms that:
- the default backward map of a place that the projection printed answers the
  canonical introduced caret: the caret that `make_introduced_reference` builds,
  whose terminal records `Position`;
- the default 4-argument reader and the reader of a template keep the
  description and the domain of the change, and answer no operation for a change
  whose route names a place below the input.
"""

using Test
using ProjecturedKernel.DocumentModule: @document, Document
using ProjecturedKernel.IntentModule: Intent
using ProjecturedKernel.IoMapModule: SimpleIoMap
using ProjecturedKernel.OperationModule: DoNothingOperation
using ProjecturedKernel.ProjectionModule: Projection, make_introduced_reference,
    map_reference_backward, read_intent, read_template_intent
using ProjecturedKernel.ReferenceModule: Reference, FieldReferenceStep,
    RangeReferenceStep, Position

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

    # Rerooting changes where an operation points, never what it is called.
    @testset "a reader keeps the labels of the change" begin
        change = Intent(nothing, DoNothingOperation(), "Do nothing", "Probe")
        for reader in (read_intent, read_template_intent)
            answer = reader(DefaultsProbeProjection(), nothing, change, nothing)
            @test answer.operation isa DoNothingOperation
            @test (answer.description, answer.domain) == ("Do nothing", "Probe")
        end
    end

    # These readers read an operation as one of their own output domain, so an
    # operation for a place below the input is not theirs to read.
    @testset "a reader that follows no route answers nothing for a route" begin
        route = Reference(FieldReferenceStep("items"))
        change = Intent(nothing, DoNothingOperation(), "Do nothing", "Probe", route)
        for reader in (read_intent, read_template_intent)
            answer = reader(DefaultsProbeProjection(), nothing, change, nothing)
            @test answer.operation === nothing
        end
    end

end
end # test_projection_defaults
