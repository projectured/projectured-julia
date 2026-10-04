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
                                       make_editor, RunFunctionOperation
import ProjecturedKernel.OperationModule: Operation, evaluate_operation, QuitEditorOperation
import ProjecturedKernel.AgentModule: run_on_editor_task!
import ProjecturedKernel.BackendModule
import ProjecturedKernel.BackendModule: Backend
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

# An operation whose evaluation gives the other tasks their turn, so a producer
# posts while the drain runs.
struct YieldingInboxOperation <: Operation
    log::Vector{Any}
end

evaluate_operation(::Editor, operation::YieldingInboxOperation) =
    (push!(operation.log, :applied); yield(); nothing)

# A backend that counts its quits, and never waits. The open of its windows
# throws `open_exception` and its quit throws `quit_exception`, each when it is
# not `nothing`.
mutable struct InboxQuitBackend <: Backend
    quits::Int
    open_exception::Any
    quit_exception::Any
end
BackendModule.initialize_backend!(::InboxQuitBackend) = nothing
function BackendModule.open_native_windows!(backend::InboxQuitBackend, document)
    backend.open_exception === nothing || throw(backend.open_exception)
    nothing
end
function BackendModule.quit_backend!(backend::InboxQuitBackend)
    backend.quits += 1
    backend.quit_exception === nothing || throw(backend.quit_exception)
    nothing
end
BackendModule.read_from_devices(::InboxQuitBackend, devices) = nothing
BackendModule.write_to_devices(::InboxQuitBackend, devices, output) = nothing
BackendModule.wait_for_input(::InboxQuitBackend, devices, timeout_seconds) = nothing

_inbox_editor() =
    Editor(InboxProbe(), InboxProbeProjection();
           backend = HeadlessBackend(), devices = Device[])

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

    @testset "a drain takes what was ready when it started, and wakes for the rest" begin
        editor = _inbox_editor()
        log = Any[]
        for _ in 1:3
            post_operation!(editor, YieldingInboxOperation(log))
        end
        Threads.atomic_xchg!(editor.wake_pending, false)
        # The producer puts with no wake, so the flag after the drain is the
        # drain's own.
        producer = @async for _ in 1:20
            put!(editor.inbox, YieldingInboxOperation(log))
            yield()
        end
        @test drain_operations!(editor) == 3
        @test length(log) == 3
        @test isready(editor.inbox)
        @test editor.wake_pending[]
        wait(producer)
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
        # `_log_performance_counters!` uses it to tell a frame the user acted in from
        # an idle one, and `run_evaluate_stage!` logs it. A sync arriving ten times a
        # second is neither.
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

    @testset "the loop quits its backend when a call at its end throws an interrupt" begin
        backend = InboxQuitBackend(0, nothing, nothing)
        editor = Editor(InboxProbe(), InboxProbeProjection();
                        backend = backend, devices = Device[])
        post_operation!(editor, QuitEditorOperation())
        # A call that no task waits for, still in the inbox when the loop ends.
        post_operation!(editor, RunFunctionOperation(() -> throw(InterruptException()),
                                                     nothing))
        @test_throws InterruptException run_editor!(editor)
        @test backend.quits == 1
        @test editor.loop_task === nothing
    end

    # The first exception goes on: an exception of the loop, or else the first
    # exception of a step at its end. Every step runs.
    @testset "an exception of the loop goes on when the quit of the backend throws" begin
        backend = InboxQuitBackend(0, nothing, ErrorException("the quit failed"))
        editor = Editor(InboxProbe(), InboxProbeProjection();
                        backend = backend, devices = Device[])
        post_operation!(editor, RunFunctionOperation(() -> throw(InterruptException()),
                                                     nothing))
        @test_throws InterruptException run_editor!(editor)
        @test backend.quits == 1

        backend = InboxQuitBackend(0, nothing, ErrorException("the quit failed"))
        editor = Editor(InboxProbe(), InboxProbeProjection();
                        backend = backend, devices = Device[])
        post_operation!(editor, QuitEditorOperation())
        @test_throws "the quit failed" run_editor!(editor)
        @test backend.quits == 1
    end

    @testset "an error of the build goes on when the quit of the backend throws" begin
        backend = InboxQuitBackend(0, ErrorException("the windows did not open"),
                                   ErrorException("the quit failed"))
        @test_throws "the windows did not open" make_editor(
            InboxProbe(), InboxProbeProjection(); backend, devices = Device[])
        @test backend.quits == 1
    end

    @testset "a frame applies what was posted before it reads" begin
        editor = _inbox_editor()
        log = Any[]
        # the loop skips a pipeline with no iomap
        EditorModule.run_print_stage!(editor)
        post_operation!(editor, ProbeInboxOperation(log, :before_frame))
        drain_operations!(editor)
        EditorModule.run_frame!(editor)
        @test [tag for (tag, _) in log] == [:before_frame]
    end
end
end

export test_editor_inbox
