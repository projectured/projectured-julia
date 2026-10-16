# The read of outside state for a document on a task of its own: a fast read is
# applied in the evaluation that starts it, a slow read is posted and applied at
# the next drain, a read that throws gives its exception to the apply, and an
# editor that is not an `Editor` reads at once.

# An operation that notes the answer of a read that it applies.
struct _DocumentReadProbe <: ProjecturedKernel.OperationModule.Operation
    answers::Vector{Any}
    answer::Any
end

ProjecturedKernel.OperationModule.evaluate_operation(editor, operation::_DocumentReadProbe) =
    (push!(operation.answers, operation.answer); nothing)

function test_document_read()
@testset "the read of a document on a task of its own" begin
    start_read! = ProjecturedPlatform.DomainModule.start_document_read!
    editor = Editor(PrimitiveString("x"), IdentityProjection(); backend = HeadlessBackend(), devices = Device[])
    answers = Any[]
    apply = answer -> _DocumentReadProbe(answers, answer)

    @testset "a read that ends inside the wait is applied at once" begin
        @test start_read!(editor, () -> 42, apply; wait = 5.0) === nothing
        @test answers == Any[42]
    end

    @testset "a slow read is posted, and the next drain applies it" begin
        empty!(answers)
        gate = Channel{Nothing}(1)
        task = start_read!(editor, () -> (take!(gate); 7), apply; wait = 0.01)
        @test task isa Task && isempty(answers)
        put!(gate, nothing)
        wait(task)
        # The post comes from a task that waits for the read, so it follows it.
        deadline = time() + 10
        while isempty(editor.owner_posts) && isempty(editor.inbox) && time() < deadline
            sleep(0.01)
        end
        drain_operations!(editor)
        @test answers == Any[7]
    end

    @testset "a read that throws gives its exception to the apply" begin
        empty!(answers)
        start_read!(editor, () -> error("no access"), apply; wait = 5.0)
        @test only(answers) isa ErrorException && only(answers).msg == "no access"
    end

    @testset "an editor that is not an Editor reads at once" begin
        empty!(answers)
        @test start_read!(nothing, () -> :listing, apply) === nothing
        @test answers == Any[:listing]
    end
end
end
