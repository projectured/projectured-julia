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
using ProjecturedKernel.PerformanceModule: compute_frame_measurement_summary

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

# A backend that shows no held frames, as one that renders a video by its own clock.
struct HeldFrameInlineBackend <: Backend end
BackendModule.shows_held_frames(::HeldFrameInlineBackend) = false

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
_has_code_unit_thread() = EditorModule._find_code_unit_place(Threads.threadid()) !== nothing

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
        @test @atomic(editor.code_unit) === nothing  # the loop owns the editor again
        if _has_code_unit_thread()
            @test seen.unit !== nothing && seen.unit.task === seen.task
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
        @testset "a backend that shows no held frames runs a unit on the thread of the loop" begin
            editor = _held_frame_editor(HeldFrameInlineBackend())
            @test run_code_unit!(() -> current_task(), editor; parts = ["inline"]) === current_task()
        end

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
                                                         nothing; description = "first call"))
            post_operation!(editor, RunFunctionOperation(() -> (sleep(0.05); push!(log, current_task())),
                                                         nothing; description = "second call"))
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
            end, nothing; description = "a long call"))
            @test_logs min_level = Base.CoreLogging.Warn run_editor!(editor)
        end

        @testset "a frame records the time of its held frames as its held time, not as its feed time" begin
            editor = _held_frame_editor(HeldFrameProbeBackend())
            post_operation!(editor, RunFunctionOperation(() -> sleep(0.2), nothing;
                                                         description = "a long call"))
            EditorModule.run_measured_frame!(editor, 0.0)
            store = editor.frame_measurements
            held = compute_frame_measurement_summary(store, :held_time).total
            @test held >= 0.15
            @test compute_frame_measurement_summary(store, :feed_time).total < 0.15
            @test compute_frame_measurement_summary(store, :frame_time).total >= held
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
            end, nothing; description = "a stoppable call", stop = () -> (stopped[] = true)))
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
            end, nothing; description = "the call that the stop ends"))
            post_operation!(editor, RunFunctionOperation(() -> nothing, nothing; description = "a later call",
                                                         stop = () -> (stopped[] = true)))
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

        @testset "a unit does not wait behind a task that computes on the default pool" begin
            place = EditorModule._find_code_unit_place(Threads.threadid())
            if place isa Integer || length(Threads.threadpooltids(:default)) >= 2
                busy = Threads.@spawn :default (started = time(); while time() - started < 3; sum(rand(100)); end)
                editor = _held_frame_editor(HeldFrameProbeBackend())
                started = time()
                # The unit waits once, and goes on on a thread that is free.
                @test run_code_unit!(() -> (sleep(0.05); :done), editor; parts = ["short"]) === :done
                @test time() - started < 1.5
                wait(busy)
            end
        end
    end

    @testset "a unit runs at the first free place of the threads that the process has" begin
        place(loop, interactive, default) = EditorModule._find_code_unit_place(loop, interactive, default)
        # An interactive thread that neither the loop nor the main task uses.
        @test place(1, [1, 2], [3, 4]) == 2           # the application, --threads=auto,2
        @test place(3, [1, 2, 3], [4, 5]) == 2        # a loop that a REPL started, --threads=auto,3
        # A loop on an interactive thread: any free thread of the default pool.
        @test place(1, [1], [2, 3]) === :default      # --threads=auto
        @test place(1, [1], [2]) === :default         # no option
        @test place(2, [1, 2], [3, 4]) === :default   # a loop that a REPL started, --threads=auto,2
        # A loop on a default thread: another default thread, or inline.
        @test place(2, [1], [2, 3]) == 3
        @test place(2, [1], [2]) === nothing
        @test place(1, Int[], [1]) === nothing        # one thread
    end

    @testset "the notice says how to start Julia when a unit has no interactive thread" begin
        notice = find_code_unit_thread_notice(HeldFrameProbeBackend(), 1)
        if length(Threads.threadpooltids(:interactive)) < 2
            @test notice isa String && occursin("--threads=auto,2", notice)
        else
            @test notice === nothing
        end
        @test find_code_unit_thread_notice(HeldFrameInlineBackend(), 1) === nothing
        @test find_code_unit_thread_notice(nothing, 1) === nothing
    end
end
end

export test_editor_held_frames
