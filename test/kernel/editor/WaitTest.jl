# The wait — between frames the editor sleeps in the backend, and three
# things end the sleep: an input event, a wake from any task, or the timeout
# the deadlines answer. The wake-pending flag is the truth; the backend kick
# only ends a wait in progress, so a kick a frame happens to consume is
# never a lost wake.

using Test
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.DeviceModule
using ProjecturedKernel.CellModule
using ProjecturedKernel.ClockModule
using ProjecturedKernel.FeedModule
import ProjecturedKernel.BackendModule
import ProjecturedKernel.BackendModule: Backend, wait_for_input, wake_backend!
import ProjecturedKernel.FeedModule: compute_wake_deadline
import ProjecturedKernel.EditorModule: Editor, post_operation!, wake_editor!,
                                       compute_wait_timeout, FRAME_INTERVAL,
                                       run_editor!, make_editor
import ProjecturedKernel.FaultModule: make_strict_fault_policy, FaultPolicy,
                                      get_fault_records
import ProjecturedKernel.OperationModule: Operation, evaluate_operation,
                                          QuitEditorOperation
using ProjecturedKernelExample

@document struct WaitProbe
    value::Int = 0
end

struct WaitProbeProjection <: Projection end
ProjectionModule.print_document(::WaitProbeProjection, recursion, input, ctx) =
    SimpleIoMap(nothing, input, input)

# A backend whose wait blocks until it is woken. The autoreset event stores a
# notification that arrives before the wait, so a wake can never slip between
# the timeout computation and the block.
mutable struct ProbeWaitBackend <: Backend
    gate::Base.Event
    waits::Vector{Float64}
    wakes::Threads.Atomic{Int}
    writes::Threads.Atomic{Int}
end
ProbeWaitBackend() = ProbeWaitBackend(Base.Event(true), Float64[],
                                      Threads.Atomic{Int}(0), Threads.Atomic{Int}(0))

BackendModule.wait_for_input(backend::ProbeWaitBackend, devices, timeout_seconds) =
    (push!(backend.waits, timeout_seconds); wait(backend.gate); nothing)
BackendModule.wake_backend!(backend::ProbeWaitBackend) =
    (Threads.atomic_add!(backend.wakes, 1); notify(backend.gate); nothing)
BackendModule.read_from_devices(::ProbeWaitBackend, devices) = nothing
BackendModule.write_to_devices(backend::ProbeWaitBackend, devices, output) =
    (Threads.atomic_add!(backend.writes, 1); nothing)
# The loop quits the backend it ran on, and this one has nothing to close.
BackendModule.quit_backend!(::ProbeWaitBackend) = nothing

# A backend that counts how often it starts, draws and quits, and never waits.
mutable struct ProbeLifeBackend <: Backend
    starts::Int
    writes::Int
    quits::Int
end
ProbeLifeBackend() = ProbeLifeBackend(0, 0, 0)
BackendModule.initialize_backend!(backend::ProbeLifeBackend) = (backend.starts += 1; nothing)
BackendModule.quit_backend!(backend::ProbeLifeBackend) = (backend.quits += 1; nothing)
BackendModule.read_from_devices(::ProbeLifeBackend, devices) = nothing
BackendModule.write_to_devices(backend::ProbeLifeBackend, devices, output) =
    (backend.writes += 1; nothing)
BackendModule.wait_for_input(::ProbeLifeBackend, devices, timeout_seconds) = nothing

struct ProbeFailOperation <: Operation end
evaluate_operation(::Editor, ::ProbeFailOperation) = error("the operation failed")

# A feed with nothing to drain and a fixed deadline.
struct DeadlineFeed <: Feed
    deadline::Union{Float64, Nothing}
end
FeedModule.drain_changes!(::DeadlineFeed, editor::Editor) = 0
FeedModule.compute_wake_deadline(feed::DeadlineFeed, editor) = feed.deadline

# A feed whose deadline throws, as a feed whose clock fails does.
struct DeadlineFailingFeed <: Feed end
FeedModule.drain_changes!(::DeadlineFailingFeed, editor::Editor) = 0
FeedModule.compute_wake_deadline(::DeadlineFailingFeed, editor) =
    error("the deadline failed")

# Wakes the editor in every frame, so the loop never waits. It posts a quit once
# another task set `is_done`, or after 100 frames.
mutable struct AlwaysWakingFeed <: Feed
    is_done::Bool
    frames::Int
end
function FeedModule.drain_changes!(feed::AlwaysWakingFeed, editor::Editor)
    feed.frames += 1
    if feed.is_done || feed.frames >= 100
        post_operation!(editor, QuitEditorOperation())
    else
        wake_editor!(editor)
    end
    0
end

# Counts the frames of the loop and posts a quit in the third, so a loop that
# never applies its key still ends.
mutable struct FrameCountFeed <: Feed
    frames::Int
end
function FeedModule.drain_changes!(feed::FrameCountFeed, editor::Editor)
    feed.frames += 1
    feed.frames == 3 && post_operation!(editor, QuitEditorOperation())
    0
end

# Turns every gesture into an operation that records the frame it applies in.
struct WaitKeyProjection <: Projection
    log::Vector{Int}
    feed::FrameCountFeed
end
ProjectionModule.print_document(::WaitKeyProjection, recursion, input, ctx) =
    SimpleIoMap(nothing, input, input)
ProjectionModule.read_intent(p::WaitKeyProjection, recursion, change::Intent, iomap) =
    Intent(change.gesture, WaitKeyOperation(p.log, p.feed))

struct WaitKeyOperation <: Operation
    log::Vector{Int}
    feed::FrameCountFeed
end
evaluate_operation(::Editor, operation::WaitKeyOperation) =
    (push!(operation.log, operation.feed.frames); nothing)

_quiet_wait_policy() = FaultPolicy(is_console_enabled = false, is_sound_enabled = false)

struct ProbeWaitOperation <: Operation
    log::Vector{Any}
    tag::Symbol
end
evaluate_operation(::Editor, operation::ProbeWaitOperation) =
    (push!(operation.log, operation.tag); nothing)

_wait_editor(backend; feeds::Vector{Feed} = Feed[]) =
    Editor(backend, WaitProbe(), WaitProbeProjection(), Device[]; feeds = feeds)

function test_editor_wait()
@testset "the editor's wait" begin
    @testset "an idle editor may sleep forever" begin
        editor = _wait_editor(ProbeWaitBackend())
        @test compute_wait_timeout(editor) == Inf
    end

    @testset "the nearest feed deadline bounds the wait" begin
        editor = _wait_editor(ProbeWaitBackend();
                              feeds = Feed[DeadlineFeed(0.25), DeadlineFeed(nothing),
                                           DeadlineFeed(0.75)])
        @test compute_wait_timeout(editor) == 0.25
    end

    @testset "a deadline that throws is recorded and counts as no deadline" begin
        editor = _wait_editor(ProbeWaitBackend();
                              feeds = Feed[DeadlineFailingFeed(), DeadlineFeed(0.5)])
        editor.fault_policy = _quiet_wait_policy()
        @test compute_wait_timeout(editor) == 0.5
        records = get_fault_records(editor.faults)
        @test length(records) == 1
        @test records[1].origin === :DeadlineFailingFeed
    end

    @testset "a clock subscriber bounds the wait to the animation" begin
        editor = _wait_editor(ProbeWaitBackend())
        subscriber = Cell(@computation get_reactive_clock_time(editor.clock))
        subscriber[]                      # the read forms the downstream edge
        @test compute_wait_timeout(editor) == FRAME_INTERVAL
        # Keep the subscriber alive across the assertion.
        @test subscriber[] isa Float64
    end

    @testset "only the false-to-true transition kicks the backend" begin
        backend = ProbeWaitBackend()
        editor = _wait_editor(backend)
        Threads.atomic_xchg!(editor.wake_pending, false)   # construction leaves it pending
        wake_editor!(editor)
        wake_editor!(editor)
        @test backend.wakes[] == 1        # the second wake found the flag set
        Threads.atomic_xchg!(editor.wake_pending, false)
        wake_editor!(editor)
        @test backend.wakes[] == 2
    end

    @testset "a posted operation ends the wait, and quit ends the loop" begin
        backend = ProbeWaitBackend()
        editor = _wait_editor(backend)
        log = Any[]
        loop = @async run_editor!(editor)
        # The first frame runs before the first wait: by the time the loop
        # blocks, the editor painted once with nothing having happened.
        @test timedwait(() -> !isempty(backend.waits), 5.0) === :ok
        @test backend.writes[] >= 1
        post_operation!(editor, ProbeWaitOperation(log, :posted))
        @test timedwait(() -> length(log) == 1, 5.0) === :ok
        post_operation!(editor, QuitEditorOperation())
        @test timedwait(() -> istaskdone(loop), 5.0) === :ok
        @test !istaskfailed(loop)         # the loop left through the quit path
        # Every wait this loop entered was unbounded: no feed asked for a
        # deadline and nothing subscribed to the clock.
        @test all(timeout -> timeout == Inf, backend.waits)
    end

    @testset "a loop that never waits still gives the other tasks their turn" begin
        # The wait of this backend returns at once and yields to no task.
        feed = AlwaysWakingFeed(false, 0)
        editor = _wait_editor(ProbeLifeBackend(); feeds = Feed[feed])
        @async (feed.is_done = true)
        run_editor!(editor)
        @test feed.frames < 100
    end

    @testset "an editor with no print applies a queued key in its first frame" begin
        feed = FrameCountFeed(0)
        log = Int[]
        backend = HeadlessBackend()
        editor = Editor(backend, WaitProbe(), WaitKeyProjection(log, feed), Device[];
                        feeds = Feed[feed])
        push_event!(backend, :key)
        run_editor!(editor)
        @test log == [1]
    end

    @testset "make_editor prints once and reads nothing, and the loop quits the backend" begin
        backend = ProbeLifeBackend()
        editor = make_editor(backend, WaitProbeProjection(), WaitProbe(); devices = Device[])
        @test backend.starts == 1 && backend.quits == 0
        # Printed once, so a verb that reads through the readers has an iomap.
        @test editor.iomap !== nothing
        @test backend.writes == 1
        post_operation!(editor, QuitEditorOperation())
        run_editor!(editor)
        @test backend.quits == 1
    end

    @testset "the loop quits the backend also when it throws" begin
        backend = ProbeLifeBackend()
        editor = make_editor(backend, WaitProbeProjection(), WaitProbe(); devices = Device[],
                             fault_policy = make_strict_fault_policy())
        post_operation!(editor, ProbeFailOperation())
        @test_throws Exception run_editor!(editor)
        @test backend.quits == 1
    end

    @testset "the default wait is one poll slice" begin
        elapsed = @elapsed wait_for_input(HeadlessBackend(), Device[], 60.0)
        @test elapsed < 2.0               # one 10 ms slice, generous under load
        @test wake_backend!(HeadlessBackend()) === nothing
    end
end
end
