# The path that an introduced reference names in the output of the projection
# that introduced it. A view that maps no part of its input maps these references,
# and only these, forward, so a part that it printed can be named and no caret
# goes into it.

using Test
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.ReferenceModule

@document struct IntroducedPathProbe
    name::String = ""
end

struct IntroducedPathProbeProjection <: Projection end
struct IntroducedPathOtherProjection <: Projection end

function test_introduced_path()
@testset "an introduced reference names a path in the output of its projection" begin
    projection = IntroducedPathProbeProjection()
    document = IntroducedPathProbe(name = "probe")
    output_path = extend_reference(EmptyReference(), FieldReferenceStep("elements"),
                                   ElementReferenceStep(2))
    iomap = SimpleIoMap(projection, document, nothing)

    # The default backward mapping names an output part by an introduced reference,
    # and the forward half gives the output path back.
    introduced = map_reference_backward(projection, iomap, output_path)
    @test is_introduced_reference(introduced, projection)
    @test find_introduced_path(projection, introduced) == output_path
    @test find_introduced_path(projection, make_introduced_reference(projection, document, output_path)) ==
          output_path

    # A reference that another projection introduced, or a path into the input,
    # names nothing in this output.
    @test find_introduced_path(IntroducedPathOtherProjection(), introduced) === nothing
    @test find_introduced_path(projection, extend_reference(EmptyReference(), FieldReferenceStep("name"))) ===
          nothing
    @test find_introduced_path(projection, EmptyReference()) === nothing
end
@testset "a step of a projection at the end of a path names a path in its output" begin
    projection = IntroducedPathProbeProjection()
    output_path = extend_reference(EmptyReference(), FieldReferenceStep("elements"), ElementReferenceStep(2))
    step = make_introduced_reference(projection, IntroducedPathProbe(name = "probe"), output_path)
    # The step after the path of a document inside the input, and the step alone.
    at_node = concat_references(extend_reference(EmptyReference(), FieldReferenceStep("items"), ElementReferenceStep(1)),
                                step)
    @test find_last_introduced_path(projection, at_node) == output_path
    @test find_last_introduced_path(projection, step) == output_path
    # A step of another projection, a step that is not the last one, and a path
    # with no step name nothing in this output.
    @test find_last_introduced_path(IntroducedPathOtherProjection(), at_node) === nothing
    @test find_last_introduced_path(projection, concat_references(step, extend_reference(EmptyReference(),
                                                                  FieldReferenceStep("name")))) === nothing
    @test find_last_introduced_path(projection, extend_reference(EmptyReference(), FieldReferenceStep("name"))) ===
          nothing
    @test find_last_introduced_path(projection, EmptyReference()) === nothing
end
end # test_introduced_path
