# The inbox — the one door into a running editor from outside its own task.
#
# A frame reads the document, evaluates against it and paints it, so anything
# that writes it from another task races the frame. An operation posted to the
# inbox is applied by the editor's own task, at a defined point in the frame,
# which is the same guarantee an operation from the reader already has.

using Test
using ProjecturedKernel.EventModule
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.DocumentModule
import ProjecturedKernel.EditorModule
import ProjecturedKernel.EditorModule: Editor, post_operation!, drain_operations!
import ProjecturedKernel.OperationModule: Operation, evaluate_operation
using ProjecturedKernelExample

@document struct InboxProbe
    value::Int = 0
end

struct InboxProbeProjection <: Projection end
ProjectionModule.print_document(::InboxProbeProjection, recursion, input, ctx) =
    SimpleIoMap(nothing, input, input)
ProjectionModule.read_intent(::InboxProbeProjection, recursion, change::Intent, iomap) =
    change

# Records the task it was applied on, which is the property under test: a posted
# operation must run on the editor's task and not on the poster's.
struct ProbeInboxOperation <: Operation
    log::Vector{Any}
    tag::Any
end

evaluate_operation(::Editor, op::ProbeInboxOperation) =
    (push!(op.log, (op.tag, current_task())); nothing)

_inbox_editor() = Editor(HeadlessBackend(), InboxProbe(), InboxProbeProjection(), Device[])

function test_editor_inbox()
@testset "the editor's operation inbox" begin
    @testset "an empty inbox drains to nothing" begin
        editor = _inbox_editor()
        @test drain_operations!(editor) == 0
    end

    @testset "posted operations are applied, in the order posted" begin
        editor = _inbox_editor()
        log = Any[]
        post_operation!(editor, ProbeInboxOperation(log, :first))
        post_operation!(editor, ProbeInboxOperation(log, :second))
        @test isempty(log)                       # nothing runs at post time
        @test drain_operations!(editor) == 2
        @test [tag for (tag, _) in log] == [:first, :second]
        @test drain_operations!(editor) == 0     # and the inbox is empty again
    end

    @testset "an operation posted from another task runs on the drainer's" begin
        editor = _inbox_editor()
        log = Any[]
        producer = @async post_operation!(editor, ProbeInboxOperation(log, :posted))
        wait(producer)
        @test isempty(log)
        drain_operations!(editor)
        @test length(log) == 1
        _, ran_on = log[1]
        @test ran_on === current_task()          # here, not on the producer
        @test ran_on !== producer
    end

    @testset "draining leaves `operation` alone" begin
        # `editor.operation` means "what the reader made of this frame's input";
        # `perf!` uses it to tell a frame the user acted in from an idle one, and
        # `evaluate!` logs it. A sync arriving ten times a second is neither.
        editor = _inbox_editor()
        post_operation!(editor, ProbeInboxOperation(Any[], :quiet))
        drain_operations!(editor)
        @test editor.operation === nothing
    end

    @testset "a frame applies what was posted before it reads" begin
        editor = _inbox_editor()
        log = Any[]
        EditorModule.print!(editor)              # the loop skips a pipeline with no iomap
        post_operation!(editor, ProbeInboxOperation(log, :before_frame))
        drain_operations!(editor)
        EditorModule.run_frame!(editor)
        @test [tag for (tag, _) in log] == [:before_frame]
    end
end
end

export test_editor_inbox
