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
                                       run_editor!
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
end
ProbeWaitBackend() = ProbeWaitBackend(Base.Event(true), Float64[], Threads.Atomic{Int}(0))

BackendModule.wait_for_input(backend::ProbeWaitBackend, devices, timeout_seconds) =
    (push!(backend.waits, timeout_seconds); wait(backend.gate); nothing)
BackendModule.wake_backend!(backend::ProbeWaitBackend) =
    (Threads.atomic_add!(backend.wakes, 1); notify(backend.gate); nothing)
BackendModule.read_from_devices(::ProbeWaitBackend, devices) = nothing
BackendModule.write_to_devices(::ProbeWaitBackend, devices, output) = nothing

# A feed with nothing to drain and a fixed deadline.
struct DeadlineFeed <: Feed
    deadline::Union{Float64, Nothing}
end
FeedModule.drain_changes!(::DeadlineFeed, editor::Editor) = 0
FeedModule.compute_wake_deadline(feed::DeadlineFeed) = feed.deadline

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

    @testset "a clock subscriber bounds the wait to the animation" begin
        editor = _wait_editor(ProbeWaitBackend())
        subscriber = ComputedCell(() -> get_reactive_clock_time(editor.clock))
        subscriber[]                      # the read forms the downstream edge
        @test compute_wait_timeout(editor) == FRAME_INTERVAL
        # Keep the subscriber alive across the assertion.
        @test subscriber[] isa Float64
    end

    @testset "only the false-to-true transition kicks the backend" begin
        backend = ProbeWaitBackend()
        editor = _wait_editor(backend)
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
        post_operation!(editor, ProbeWaitOperation(log, :posted))
        @test timedwait(() -> length(log) == 1, 5.0) === :ok
        post_operation!(editor, QuitEditorOperation())
        @test timedwait(() -> istaskdone(loop), 5.0) === :ok
        @test !istaskfailed(loop)         # the loop left through the quit path
        # Every wait this loop entered was unbounded: no feed asked for a
        # deadline and nothing subscribed to the clock.
        @test all(timeout -> timeout == Inf, backend.waits)
    end

    @testset "the default wait is one poll slice" begin
        elapsed = @elapsed wait_for_input(HeadlessBackend(), Device[], 60.0)
        @test elapsed < 2.0               # one 10 ms slice, generous under load
        @test wake_backend!(HeadlessBackend()) === nothing
    end
end
end
