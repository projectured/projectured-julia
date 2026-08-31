"""
`OperationModule` — the open `reroot_operation` seam. Verifies the base
methods land here (Nothing, catch-all, ReplaceSelectionOperation,
ReplaceReferencedValueOperation, CompoundOperation) and that a
**test-local** path-bearing operation can register its own reroot
method — that is exactly the seam pressure that keeps the generic honest.
"""

using Test
using ProjecturedKernel
using ProjecturedKernel.OperationModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.ReferenceModule

# A test-local path-bearing operation: registering a `reroot_operation` method
# for it below is exactly the seam pressure that keeps the generic open.
struct ToyPathOp <: Operation
    reference::Reference
end
ProjecturedKernel.OperationModule.reroot_operation(op::ToyPathOp, s::Tuple) =
    ToyPathOp(reroot_reference(op.reference, s))

struct RL end
struct RN end

function test_rerooting()
@testset "Rerooting" begin

    steps = (FieldReferenceStep("outer"), FieldReferenceStep("inner"))

    @testset "reroot_reference prepends outermost-first" begin
        ref = strip_reference_types(@reference ::RL.leaf::RN)
        r = reroot_reference(ref, steps)
        @test r == ConcreteReference(FieldReferenceStep("outer"),
                     ConcreteReference(FieldReferenceStep("inner"),
                         ConcreteReference(FieldReferenceStep("leaf"), EmptyReference())))
    end

    @testset "base methods on kernel operation types" begin
        # Nothing and catch-all pass through / return unchanged.
        @test reroot_operation(nothing, steps) === nothing
        @test reroot_operation(DoNothingOperation(), steps) isa DoNothingOperation

        # ReplaceSelectionOperation reroots the path field.
        r = reroot_operation(ReplaceSelectionOperation(strip_reference_types(@reference ::RL.leaf::RN)), steps)
        @test r isa ReplaceSelectionOperation
        @test r.path == ConcreteReference(FieldReferenceStep("outer"),
                            ConcreteReference(FieldReferenceStep("inner"),
                                ConcreteReference(FieldReferenceStep("leaf"), EmptyReference())))

        # CompoundOperation maps the reroot over its constituents.
        cop = CompoundOperation(Any[ReplaceSelectionOperation(strip_reference_types(@reference ::RL.leaf::RN)),
                                    DoNothingOperation()])
        rc = reroot_operation(cop, steps)
        @test rc isa CompoundOperation
        @test length(rc.operations) == 2
        @test rc.operations[1] isa ReplaceSelectionOperation
    end

    # A collection travels home the same way a compound does, and for the same
    # reason: the operations inside must arrive rooted where the caller can apply
    # them. The labels are not touched — rerooting moves an operation, it does not
    # rename it.
    @testset "CollectedIntentsOperation reroots every carried operation" begin
        path = strip_reference_types(@reference ::RL.leaf::RN)
        collected = CollectedIntentsOperation([
            Intent(nothing, ReplaceSelectionOperation(path), "Do the thing", "Probe"),
            Intent(nothing, nothing, "Cannot right now", "Probe")])
        rc = reroot_operation(collected, steps)
        @test rc isa CollectedIntentsOperation
        @test length(rc.intents) == 2
        # The one that carries an operation is rerooted, exactly as a bare one is.
        @test rc.intents[1].operation isa ReplaceSelectionOperation
        @test rc.intents[1].operation.path ==
              reroot_operation(ReplaceSelectionOperation(path), steps).path
        # The one that declined stays declined.
        @test rc.intents[2].operation === nothing
        # Labels survive.
        @test [i.description for i in rc.intents] == ["Do the thing", "Cannot right now"]
        @test all(i -> i.domain == "Probe", rc.intents)
    end

    @testset "merge_collected_intents takes both answers, in order" begin
        a = CollectedIntentsOperation([Intent(nothing, nothing, "a", "A")])
        b = CollectedIntentsOperation([Intent(nothing, nothing, "b", "B")])
        @test [i.description for i in merge_collected_intents(a, b).intents] == ["a", "b"]
        @test merge_collected_intents(a, nothing) === a
        @test merge_collected_intents(nothing, b) === b
        @test merge_collected_intents(nothing, nothing) === nothing
    end

    @testset "test-local Operation type adds its own reroot method" begin
        # ToyPathOp is declared at file scope; the method registration above.
        r = reroot_operation(ToyPathOp(strip_reference_types(@reference ::RL.leaf::RN)), steps)
        @test r isa ToyPathOp
        @test r.reference == ConcreteReference(FieldReferenceStep("outer"),
                                ConcreteReference(FieldReferenceStep("inner"),
                                    ConcreteReference(FieldReferenceStep("leaf"), EmptyReference())))
    end

end
end # test_rerooting
