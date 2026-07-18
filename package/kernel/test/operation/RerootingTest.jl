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
using ProjecturedKernel.ReferenceModule

# A test-local path-bearing operation: registering a `reroot_operation` method
# for it below is exactly the seam pressure that keeps the generic open.
struct ToyPathOp <: Operation
    reference::ReferencePath
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
        @test r == ConcreteReferencePath(FieldReferenceStep("outer"),
                     ConcreteReferencePath(FieldReferenceStep("inner"),
                         ConcreteReferencePath(FieldReferenceStep("leaf"), EmptyReferencePath())))
    end

    @testset "base methods on kernel operation types" begin
        # Nothing and catch-all pass through / return unchanged.
        @test reroot_operation(nothing, steps) === nothing
        @test reroot_operation(DoNothingOperation(), steps) isa DoNothingOperation

        # ReplaceSelectionOperation reroots the path field.
        r = reroot_operation(ReplaceSelectionOperation(strip_reference_types(@reference ::RL.leaf::RN)), steps)
        @test r isa ReplaceSelectionOperation
        @test r.path == ConcreteReferencePath(FieldReferenceStep("outer"),
                            ConcreteReferencePath(FieldReferenceStep("inner"),
                                ConcreteReferencePath(FieldReferenceStep("leaf"), EmptyReferencePath())))

        # CompoundOperation maps the reroot over its constituents.
        cop = CompoundOperation(Any[ReplaceSelectionOperation(strip_reference_types(@reference ::RL.leaf::RN)),
                                    DoNothingOperation()])
        rc = reroot_operation(cop, steps)
        @test rc isa CompoundOperation
        @test length(rc.operations) == 2
        @test rc.operations[1] isa ReplaceSelectionOperation
    end

    @testset "test-local Operation type adds its own reroot method" begin
        # ToyPathOp is declared at file scope; the method registration above.
        r = reroot_operation(ToyPathOp(strip_reference_types(@reference ::RL.leaf::RN)), steps)
        @test r isa ToyPathOp
        @test r.reference == ConcreteReferencePath(FieldReferenceStep("outer"),
                                ConcreteReferencePath(FieldReferenceStep("inner"),
                                    ConcreteReferencePath(FieldReferenceStep("leaf"), EmptyReferencePath())))
    end

end
end # test_rerooting
