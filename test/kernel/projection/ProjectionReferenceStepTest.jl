"""
`ProjectionReferenceStep` — the step of a caret on an element that a projection
printed.

Confirms that two carets that `make_introduced_reference` builds apart, for one
projection and one output path, are equal, have one hash, and are one key of a
`Set`. Also confirms when two steps are equal, the short form that a log shows,
the `.proj` step of the reference literal and its match, and what an introduced
caret names.
"""

using Test
using ProjecturedKernel.DocumentModule: @document
using ProjecturedKernel.ProjectionModule: Projection, ProjectionReferenceStep,
    make_introduced_reference, is_introduced_reference, normalize_named_node_reference
using ProjecturedKernel.ReferenceModule: Reference, EmptyReference, FieldReferenceStep,
    RangeReferenceStep, strip_reference_types, evaluate_reference_step,
    @reference, @reference_case

struct IntroducedCaretProbe <: Projection end
struct IntroducedCaretNode end

# A test-local projection with a name, so that two of them are two projections.
struct NamedCaretProbe <: Projection
    name::String
end

@document struct NamedCaretLeaf
    text::String
end

# The place of a closing bracket that a projection printed.
_make_close_path() = Reference(FieldReferenceStep("close"), RangeReferenceStep(0, 0))

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

    @testset "two steps are equal for one projection and equal output paths" begin
        projection = NamedCaretProbe("a")
        step = ProjectionReferenceStep(projection, _make_close_path())
        @test step == ProjectionReferenceStep(projection, _make_close_path())
        @test step != ProjectionReferenceStep(NamedCaretProbe("b"), _make_close_path())
        @test step != ProjectionReferenceStep(projection,
                                              Reference(FieldReferenceStep("open")))
        # A step stands for the place in the output of the projection.
        @test evaluate_reference_step(step, nothing) == _make_close_path()
    end

    # A log of operations asks for the short form: the printed part between marks,
    # with no second pair of marks for a step inside the output path of another.
    @testset "a short line shows the printed part between marks" begin
        step = ProjectionReferenceStep(NamedCaretProbe("a"), _make_close_path())
        @test sprint(show, step; context = :compact => true) == "‹.close{0}›"
        caret = Reference(FieldReferenceStep("entries"), step)
        @test sprint(show, caret; context = :compact => true) == ".entries‹.close{0}›"
        nested = ProjectionReferenceStep(NamedCaretProbe("b"),
                                         Reference(FieldReferenceStep("items"), step))
        @test sprint(show, nested; context = :compact => true) == "‹.items.close{0}›"
        @test occursin("ProjectionReferenceStep(", sprint(show, step))
    end

    @testset "the .proj step of the reference literal builds and matches a step" begin
        projection = NamedCaretProbe("a")
        leaf = NamedCaretLeaf("text", nothing)
        printed = _make_close_path()
        built = @reference(leaf, proj(projection, ^(printed)))
        @test built.head isa ProjectionReferenceStep
        @test built.head.projection === projection
        @test strip_reference_types(built.head.output_path) == printed
        matched = @reference_case built begin
            proj(^(projection), inner) => inner
        end
        @test strip_reference_types(matched) == printed
        other = NamedCaretProbe("b")
        missed = @reference_case built begin
            proj(^(other), inner) => inner
        end
        @test missed === nothing
    end

    # A caret on a bracket names the whole node that the bracket was printed for.
    @testset "an introduced caret names the node that it was printed for" begin
        projection = NamedCaretProbe("a")
        caret = make_introduced_reference(projection, IntroducedCaretNode,
                                          _make_close_path())
        @test is_introduced_reference(caret)
        @test is_introduced_reference(caret, projection)
        @test !is_introduced_reference(caret, NamedCaretProbe("b"))
        @test !is_introduced_reference(_make_close_path())
        @test normalize_named_node_reference(caret) == EmptyReference()
        plain = _make_close_path()
        @test normalize_named_node_reference(plain) === plain
    end

end
end # test_projection_reference_step
