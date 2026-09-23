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
import ProjecturedKernel.EditorModule: Editor, post_operation!, drain_operations!, run_editor!,
                                       RunFunctionOperation
import ProjecturedKernel.OperationModule: Operation, evaluate_operation, QuitEditorOperation
import ProjecturedKernel.AgentModule: run_on_editor_task!
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

    @testset "a call runs at once where no loop runs on another task" begin
        editor = _inbox_editor()
        @test run_on_editor_task!(() -> current_task(), editor) === current_task()
        @test run_on_editor_task!(() -> 1, (document = nothing,)) == 1
        editor.loop_task = current_task()
        @test run_on_editor_task!(() -> current_task(), editor) === current_task()
        @test run_on_editor_task!(() -> 1, editor; wait = false) === nothing
        @test !isready(editor.inbox)
    end

    @testset "a call from another task runs in the drain, and the caller waits" begin
        editor = _inbox_editor()
        editor.loop_task = current_task()          # a loop runs on this task
        log = Any[]
        caller = @async begin
            run_on_editor_task!(editor; wait = false) do
                push!(log, (:posted, current_task()))
            end
            run_on_editor_task!(() -> (push!(log, (:called, current_task())); 42), editor)
        end
        @test timedwait(() -> Base.n_avail(editor.inbox) == 2, 5.0) === :ok
        @test isempty(log) && !istaskdone(caller)
        @test drain_operations!(editor) == 2
        @test [tag for (tag, _) in log] == [:posted, :called]
        @test all(((_, task),) -> task === current_task(), log)
        @test fetch(caller) == 42
        # What the call throws is thrown on the task that waits for it.
        failing = @async run_on_editor_task!(() -> error("the call failed"), editor)
        @test timedwait(() -> isready(editor.inbox), 5.0) === :ok
        drain_operations!(editor)
        @test_throws TaskFailedException fetch(failing)
        @test occursin("the call failed", sprint(showerror, failing.exception))
    end

    @testset "a call that waits when the loop ends gets its answer" begin
        editor = _inbox_editor()
        answer = Ref{Any}(nothing)
        # The loop applies this first, on its own task, so the call below is
        # posted by a task that waits for a running loop.
        post_operation!(editor, RunFunctionOperation(function ()
            @async begin
                answer[] = run_on_editor_task!(() -> current_task(), editor)
            end
            # The quit is applied before the call, which waits in the inbox
            # behind it when the loop ends.
            post_operation!(editor, QuitEditorOperation())
            yield()
        end, nothing))
        run_editor!(editor)
        @test timedwait(() -> answer[] !== nothing, 5.0) === :ok
        @test answer[] === current_task()
        @test editor.loop_task === nothing
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
