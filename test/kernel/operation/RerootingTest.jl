"""
`OperationModule` — the open `reroot_operation` seam. Verifies the base
methods land here (Nothing, catch-all, ReplaceSelectionOperation,
CompoundOperation, WrappingOperation) and that a **test-local** path-bearing
operation registers with the pair `operation_reference` / `retarget_operation`
alone, and the catch-all reroots it — that is exactly the seam pressure that
keeps the generic honest. A
test-local wrapper applies the same pressure to the `WrappingOperation`
contract: it declares the two generics and nothing else, and the one base method
must carry it.

It also verifies `operation_reference`, `retarget_operation` and
`is_self_contained_operation` for the kernel operations and their defaults for an
operation that adds no method, and what the default reader of a test-local
projection answers for them.
"""

using Test
using ProjecturedKernel
using ProjecturedKernel.OperationModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.ProjectionModule: Projection, read_intent

# A test-local path-bearing operation. It answers the pair and nothing else, and
# the catch-all `reroot_operation` must reroot it: exactly the seam pressure that
# keeps the generic open.
struct ToyPathOperation <: Operation
    reference::Reference
end
ProjecturedKernel.OperationModule.operation_reference(op::ToyPathOperation) = op.reference
ProjecturedKernel.OperationModule.retarget_operation(op::ToyPathOperation,
                                                      reference::Reference) =
    ToyPathOperation(reference)

# A test-local operation that answers no seam.
struct ToyBareOperation <: Operation
    reference::Reference
end

# A test-local wrapper: it answers the two generics of the `WrappingOperation`
# contract and declares no `reroot_operation` method of its own. The one base
# method is what must reach the operation it holds.
struct ToyWrapperOperation <: WrappingOperation
    operation::Any
    note::String
end
ProjecturedKernel.OperationModule.get_wrapped_operation(op::ToyWrapperOperation) = op.operation
ProjecturedKernel.OperationModule.rewrap_operation(op::ToyWrapperOperation, inner) =
    ToyWrapperOperation(inner, op.note)

struct RL end
struct RN end

# A test-local projection with no reader of its own: it answers what the default
# reader of the kernel answers.
struct RerootProbeProjection <: Projection end

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

    @testset "a document-rooted write is rerooted, and a carried one is not" begin
        path = strip_reference_types(@reference ::RL.leaf::RN)
        write = ReplaceReferencedValueOperation(nothing, path, 1)
        rerooted = reroot_operation(write, steps)
        @test rerooted isa ReplaceReferencedValueOperation
        @test rerooted.document === nothing
        @test rerooted.reference == reroot_reference(path, steps)
        @test rerooted.value == 1
        carried = ReplaceReferencedValueOperation(RN(), path, 1)
        @test reroot_operation(carried, steps) === carried
    end

    # An operation type of a package above names its place through the seams, or
    # takes the defaults: no reference, the same operation, and no travel.
    @testset "the seams answer the defaults for an operation that adds no method" begin
        operation = ToyBareOperation(strip_reference_types(@reference ::RL.leaf::RN))
        @test operation_reference(operation) === nothing
        @test reroot_operation(operation, (FieldReferenceStep("outer"),)) === operation
        @test retarget_operation(operation, Reference(FieldReferenceStep("other"))) ===
              operation
        @test !is_self_contained_operation(operation)
        @test operation_reference(nothing) === nothing
        @test !is_self_contained_operation(nothing)
    end

    @testset "operation_reference answers the place of a selection and of a write" begin
        path = strip_reference_types(@reference ::RL.leaf::RN)
        other = Reference(FieldReferenceStep("other"))
        @test operation_reference(ReplaceSelectionOperation(path)) == path
        @test retarget_operation(ReplaceSelectionOperation(path), other).path == other

        write = ReplaceReferencedValueOperation(nothing, path, 1)
        @test operation_reference(write) == path
        moved = retarget_operation(write, other)
        @test moved isa ReplaceReferencedValueOperation
        @test moved.document === nothing
        @test moved.reference == other
        @test moved.value == 1

        # A carried root is the place of the write, so there is no reference to
        # report and none to replace.
        carried = ReplaceReferencedValueOperation(RN(), path, 1)
        @test operation_reference(carried) === nothing
        @test retarget_operation(carried, other) === carried
    end

    @testset "an operation that names no place travels unchanged" begin
        for operation in (DoNothingOperation(), QuitEditorOperation(),
                          InvalidateProjectionOperation(),
                          ToggleCollapseOperation(),
                          SelectNextInsertionOperation(_ -> false))
            @test operation_reference(operation) === nothing
            @test is_self_contained_operation(operation)
            # The default reader forwards it as it is, so a chain stops at it.
            @test read_intent(RerootProbeProjection(), nothing, operation) === operation
        end
        @test !is_self_contained_operation(ReplaceSelectionOperation(EmptyReference()))
    end

    # Rerooting changes where an operation points, never what it is called.
    @testset "a projection with no reader of its own keeps the labels" begin
        change = Intent(nothing, DoNothingOperation(), "Do nothing", "Probe")
        answer = read_intent(RerootProbeProjection(), nothing, change, nothing)
        @test answer.operation isa DoNothingOperation
        @test answer.description == "Do nothing"
        @test answer.domain == "Probe"
    end

    # A wrapper declares no reroot method of its own. The base method must reach
    # what it holds, and must leave everything else about the wrapper alone.
    @testset "a WrappingOperation reroots what it holds" begin
        path = strip_reference_types(@reference ::RL.leaf::RN)
        wrapped = ToyWrapperOperation(ReplaceSelectionOperation(path), "a note")
        r = reroot_operation(wrapped, steps)
        @test r isa ToyWrapperOperation
        @test r.operation isa ReplaceSelectionOperation
        @test r.operation.path == reroot_operation(ReplaceSelectionOperation(path), steps).path
        # Rerooting moves an operation; it changes nothing else about the wrapper.
        @test r.note == "a note"

        # A wrapper around a wrapper reaches all the way down.
        twice = reroot_operation(ToyWrapperOperation(wrapped, "outer"), steps)
        @test twice.operation.operation.path == r.operation.path

        # A wrapper around an operation that carries no reference is unchanged
        # inside, and still a wrapper outside.
        plain = reroot_operation(ToyWrapperOperation(DoNothingOperation(), "x"), steps)
        @test plain isa ToyWrapperOperation
        @test plain.operation isa DoNothingOperation
    end

    @testset "a test-local operation that answers the pair is rerooted by the catch-all" begin
        # ToyPathOperation is declared at file scope, with the pair and no reroot method.
        r = reroot_operation(ToyPathOperation(strip_reference_types(@reference ::RL.leaf::RN)), steps)
        @test r isa ToyPathOperation
        @test r.reference == ConcreteReference(FieldReferenceStep("outer"),
                                ConcreteReference(FieldReferenceStep("inner"),
                                    ConcreteReference(FieldReferenceStep("leaf"), EmptyReference())))
    end

    @testset "a replace with a value that has no selection selects the value whole" begin
        path = Reference(FieldReferenceStep("steps"), RangeReferenceStep(1, 2))
        write, select = make_replace_document_operation(path, FieldReferenceStep("title")).operations
        @test write isa ReplaceReferencedValueOperation
        @test write.value == FieldReferenceStep("title")
        @test select isa ReplaceSelectionOperation
        @test get_reference_steps(select.path) == get_reference_steps(path)
    end

end
end # test_rerooting
