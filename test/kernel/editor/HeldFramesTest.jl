# Code units and held frames — the work that runs on a thread of its own while the
# loop keeps the window alive.
#
# A code unit owns the documents of its editor while it runs, and the loop runs
# held frames: they answer the window system, show that the editor is busy, and
# take a stop or a close. The test task plays the loop. Where the process has no
# second thread of the default pool, a unit runs inline, and the tests check that.

using Test
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.DocumentModule
import ProjecturedKernel.EditorModule
import ProjecturedKernel.EditorModule: Editor, post_operation!, drain_operations!,
                                       run_code_unit!, RunFunctionOperation, run_editor!
import ProjecturedKernel.OperationModule: QuitEditorException, QuitEditorOperation
import ProjecturedKernel.AgentModule: run_on_editor_task!
import ProjecturedKernel.ToolModule: get_current_code_unit, wait_in_code_unit,
                                     execute_julia_code!, CodeUnitWaitException,
                                     start_background_work, is_background_work_done
import ProjecturedKernel.FaultModule: FaultPolicy, get_fault_records
import ProjecturedKernel.BackendModule
import ProjecturedKernel.BackendModule: Backend, HeldFrameState
using ProjecturedKernel.DeviceModule: Device

@document struct HeldFrameProbe
    value::Int = 0
end

struct HeldFrameProbeProjection <: Projection end
ProjectionModule.print_document(::HeldFrameProbeProjection, recursion, input, context) =
    SimpleIoMap(nothing, input, input)
ProjectionModule.read_intent(::HeldFrameProbeProjection, recursion, change::Intent, iomap) =
    change

# A backend that records what its held frames show, answers what the script says,
# and throws `exception` in each held frame when it is not `nothing`.
mutable struct HeldFrameProbeBackend <: Backend
    prepared::Vector{Vector{String}}
    states::Vector{HeldFrameState}
    answers::Vector{Symbol}
    ended::Int
    exception::Any
end
HeldFrameProbeBackend(answers::Vector{Symbol} = Symbol[]; exception = nothing) =
    HeldFrameProbeBackend(Vector{String}[], HeldFrameState[], answers, 0, exception)

BackendModule.initialize_backend!(::HeldFrameProbeBackend) = nothing
BackendModule.quit_backend!(::HeldFrameProbeBackend) = nothing
BackendModule.take_from_devices!(::HeldFrameProbeBackend, devices) = nothing
BackendModule.write_to_devices!(::HeldFrameProbeBackend, devices, output) = nothing
BackendModule.wait_for_input(::HeldFrameProbeBackend, devices, timeout_seconds) = nothing
BackendModule.prepare_held_frames!(backend::HeldFrameProbeBackend, devices, parts) =
    (push!(backend.prepared, copy(parts)); nothing)
function BackendModule.run_held_frame!(backend::HeldFrameProbeBackend, devices,
                                       state::HeldFrameState)
    push!(backend.states, state)
    backend.exception === nothing || throw(backend.exception)
    sleep(0.005)
    isempty(backend.answers) ? :none : popfirst!(backend.answers)
end
BackendModule.end_held_frames!(backend::HeldFrameProbeBackend, devices) =
    (backend.ended += 1; nothing)

# An editor whose loop runs on the calling task, as the loop of `run_editor!` does.
function _held_frame_editor(backend; fault_policy = nothing)
    editor = fault_policy === nothing ?
        Editor(HeldFrameProbe(), HeldFrameProbeProjection(); backend, devices = Device[]) :
        Editor(HeldFrameProbe(), HeldFrameProbeProjection(); backend, devices = Device[],
               fault_policy)
    editor.loop_task = current_task()
    editor
end

# Whether this process can run a unit on a thread other than the one of this task.
_has_code_unit_thread() =
    any(thread -> thread != Threads.threadid(), Threads.threadpooltids(:default))

function test_editor_held_frames()
@testset "code units and held frames" begin
    @testset "a unit runs inline where no loop runs" begin
        editor = Editor(HeldFrameProbe(), HeldFrameProbeProjection();
                        backend = HeldFrameProbeBackend(), devices = Device[])
        value = run_code_unit!(editor; parts = ["inline"]) do
            (current_task(), get_current_code_unit() !== nothing)
        end
        @test value == (current_task(), true)
        @test isempty(editor.backend.states)
    end

    @testset "a unit runs on a thread of its own and owns the editor meanwhile" begin
        backend = HeldFrameProbeBackend()
        editor = _held_frame_editor(backend)
        seen = run_code_unit!(editor; parts = ["the work"]) do
            sleep(0.05)
            (task = current_task(), thread = Threads.threadid(),
             unit = @atomic(editor.code_unit),
             owner = run_on_editor_task!(() -> current_task(), editor))
        end
        @test seen.owner === seen.task               # a call of the owner runs at once
        @test seen.unit !== nothing && seen.unit.task === seen.task
        @test @atomic(editor.code_unit) === nothing  # the loop owns the editor again
        if _has_code_unit_thread()
            @test seen.task !== current_task()
            @test seen.thread != Threads.threadid()
            @test backend.prepared == [["the work"]]
            @test !isempty(backend.states) && backend.ended == 1
            @test all(state -> state.current == 1 && !state.is_quit_asked, backend.states)
        else
            @test seen.task === current_task()
        end
    end

    @testset "an exception of a unit is thrown again on the loop" begin
        editor = _held_frame_editor(HeldFrameProbeBackend())
        @test_throws "the unit failed" run_code_unit!(() -> error("the unit failed"), editor;
                                                      parts = ["failing"])
        @test @atomic(editor.code_unit) === nothing
    end

    if _has_code_unit_thread()
        @testset "a stop ends the stoppable wait of a unit" begin
            backend = HeldFrameProbeBackend([:none, :none, :stop])
            editor = _held_frame_editor(backend)
            started = time()
            answer = run_code_unit!(editor; parts = ["sleep"]) do
                try
                    wait_in_code_unit(10)
                    :slept
                catch exception
                    exception isa InterruptException ? :stopped : rethrow()
                end
            end
            @test answer === :stopped
            @test time() - started < 5
        end

        @testset "a first close stops, a second asks to quit, and the confirm quits" begin
            backend = HeldFrameProbeBackend([:close, :none, :close, :none, :quit])
            editor = _held_frame_editor(backend)
            release = Channel{Nothing}(1)
            # The unit does not see the stop: it waits on a channel, as code that
            # waits on something of its own does.
            @test_throws QuitEditorException run_code_unit!(editor; parts = ["stubborn"]) do
                take!(release)
                :released
            end
            unit = @atomic editor.code_unit
            @test unit !== nothing && unit.stop[]       # stopped, and still running
            @test any(state -> state.is_quit_asked, backend.states)
            put!(release, nothing)
            @test fetch(unit.task) == (true, :released)
        end

        @testset "a fault of a held frame is recorded after the unit" begin
            backend = HeldFrameProbeBackend(; exception = ErrorException("the frame failed"))
            editor = _held_frame_editor(backend; fault_policy = FaultPolicy())
            @test run_code_unit!(() -> (sleep(0.05); :done), editor; parts = ["work"]) === :done
            records = get_fault_records(editor.faults)
            @test any(record -> record.origin === :HeldFrameProbeBackend, records)
            @test isempty(editor.held_faults)
        end

        @testset "under a strict policy a fault of a held frame is thrown after the unit" begin
            backend = HeldFrameProbeBackend(; exception = ErrorException("the frame failed"))
            editor = _held_frame_editor(backend)
            @test_throws "the frame failed" run_code_unit!(() -> (sleep(0.05); :done), editor;
                                                           parts = ["work"])
            @test @atomic(editor.code_unit) === nothing
        end

        @testset "a drain with posted calls runs as one unit that names each call" begin
            backend = HeldFrameProbeBackend()
            editor = _held_frame_editor(backend)
            log = Any[]
            post_operation!(editor, RunFunctionOperation(() -> (sleep(0.05); push!(log, current_task())),
                                                         nothing, "first call"))
            post_operation!(editor, RunFunctionOperation(() -> (sleep(0.05); push!(log, current_task())),
                                                         nothing, "second call"))
            @test drain_operations!(editor) == 2
            @test length(log) == 2 && log[1] === log[2] && log[1] !== current_task()
            @test backend.prepared == [["first call", "second call"]]
            @test Set(state.current for state in backend.states) ⊆ Set([1, 2])
        end

        @testset "a task that the running unit starts posts to the queue of the owner" begin
            editor = _held_frame_editor(HeldFrameProbeBackend())
            queues = run_code_unit!(editor; parts = ["poster"]) do
                child = @async begin
                    post_operation!(editor, RunFunctionOperation(() -> nothing, nothing))
                    (owned = Base.n_avail(editor.owner_posts), inbox = Base.n_avail(editor.inbox))
                end
                fetch(child)
            end
            @test queues == (owned = 1, inbox = 0)
            @test drain_operations!(editor) == 1
        end

        @testset "the time of held frames does not make a slow frame" begin
            editor = Editor(HeldFrameProbe(), HeldFrameProbeProjection();
                            backend = HeldFrameProbeBackend(), devices = Device[])
            post_operation!(editor, RunFunctionOperation(function ()
                sleep(1.2)
                post_operation!(editor, QuitEditorOperation())
            end, nothing, "a long call"))
            @test_logs min_level = Base.CoreLogging.Warn run_editor!(editor)
        end

        @testset "a task that the unit starts can not wait for the editor" begin
            editor = _held_frame_editor(HeldFrameProbeBackend())
            failure = run_code_unit!(editor; parts = ["parent"]) do
                child = @async run_on_editor_task!(() -> 1, editor; description = "child call")
                try
                    fetch(child)
                    nothing
                catch exception
                    exception.task.exception
                end
            end
            @test failure isa CodeUnitWaitException
            @test failure.description == "child call"
        end

        @testset "work that a running unit started waits for the editor only after the unit" begin
            editor = _held_frame_editor(HeldFrameProbeBackend())
            early = Channel{Any}(1)
            go = Channel{Nothing}(1)
            work = run_code_unit!(editor; parts = ["parent"]) do
                work = start_background_work(; editor) do
                    put!(early, try
                        run_on_editor_task!(() -> :ran, editor; description = "early call")
                    catch exception
                        exception
                    end)
                    take!(go)
                    run_on_editor_task!(() -> :late, editor; description = "late call")
                end
                take!(early) isa CodeUnitWaitException || error("the early call did not throw")
                work
            end
            put!(go, nothing)
            deadline = time() + 5.0
            while !is_background_work_done(work) && time() < deadline
                drain_operations!(editor)
                sleep(0.01)
            end
            @test fetch(work) === :late             # a drain of the loop ran the late call
        end

        @testset "a stop of a unit runs the stop step of each posted call" begin
            editor = _held_frame_editor(HeldFrameProbeBackend([:none, :none, :stop]))
            stopped = Threads.Atomic{Bool}(false)
            post_operation!(editor, RunFunctionOperation(function ()
                try
                    wait_in_code_unit(10)
                catch exception
                    exception isa InterruptException || rethrow()
                end
            end, nothing, "a stoppable call", () -> (stopped[] = true)))
            drain_operations!(editor)
            @test timedwait(() -> stopped[], 5.0) === :ok
        end

        @testset "a call that starts after the stop of its unit runs its stop step at once" begin
            editor = _held_frame_editor(HeldFrameProbeBackend([:none, :none, :stop]))
            stopped = Threads.Atomic{Bool}(false)
            post_operation!(editor, RunFunctionOperation(function ()
                try
                    wait_in_code_unit(10)
                catch exception
                    exception isa InterruptException || rethrow()
                end
            end, nothing, "the call that the stop ends"))
            post_operation!(editor, RunFunctionOperation(() -> nothing, nothing, "a later call",
                                                         () -> (stopped[] = true)))
            @test drain_operations!(editor) == 2
            @test timedwait(() -> stopped[], 5.0) === :ok
        end

        @testset "a stop ends the sleep of model code" begin
            backend = HeldFrameProbeBackend([:none, :none, :none, :stop])
            editor = _held_frame_editor(backend)
            started = time()
            answer = execute_julia_code!(editor.tools, editor, "sleep(10); :slept")
            @test occursin("InterruptException", answer)
            @test time() - started < 5
        end

        @testset "the code tool runs its evaluation as a unit" begin
            editor = _held_frame_editor(HeldFrameProbeBackend())
            answer = execute_julia_code!(editor.tools, editor, "Threads.threadid()")
            @test parse(Int, strip(answer)) != Threads.threadid()
        end
    end
end
end

export test_editor_held_frames
