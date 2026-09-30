# The timers of the editor. A reader sets a timer with `SetTimerOperation`, the
# editor keeps its time under its name, the wait ends at the earliest timer, and
# `read!` reads a `TimerExpire` for a timer whose time came, before any device
# input.

using Test
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.DeviceModule
using ProjecturedKernel.EventModule
import ProjecturedKernel.BackendModule
import ProjecturedKernel.BackendModule: Backend
import ProjecturedKernel.EditorModule: Editor, compute_wait_timeout, post_operation!,
                                       run_editor!, read!, evaluate!, print!
import ProjecturedKernel.OperationModule: Operation, SetTimerOperation, QuitEditorOperation,
                                          DoNothingOperation, evaluate_operation,
                                          operation_travels_unchanged,
                                          make_inverse_operation, describe_operation

@document struct TimerProbe
    value::Int = 0
end

# A reader that sets the timer that a key names, `delay` seconds after the key,
# and answers a timer with an operation that records it, so a test sees what
# reached the reader.
struct TimerProbeProjection <: Projection
    log::Vector{Any}
    delay::Float64
end
ProjectionModule.print_document(::TimerProbeProjection, recursion, input, ctx) =
    SimpleIoMap(nothing, input, input)

struct TimerProbeRecordOperation <: Operation
    log::Vector{Any}
    input::Any
end
evaluate_operation(::Editor, operation::TimerProbeRecordOperation) =
    (push!(operation.log, operation.input); nothing)

function ProjectionModule.read_intent(p::TimerProbeProjection, iomap, input)
    input isa WindowInput && input.event isa KeyDown &&
        return SetTimerOperation(input.event.key, input.event.time + p.delay)
    input isa TimerExpire && return TimerProbeRecordOperation(p.log, input)
    nothing
end

# A backend that hands out the inputs of a list, and whose wait sleeps while the
# list is empty, at most a second, so a loop over it wakes for a timer.
mutable struct TimerProbeBackend <: Backend
    inputs::Vector{Any}
    waits::Vector{Float64}
end
TimerProbeBackend(inputs::Vector{Any} = Any[]) = TimerProbeBackend(inputs, Float64[])
BackendModule.read_from_devices(backend::TimerProbeBackend, devices) =
    isempty(backend.inputs) ? nothing : popfirst!(backend.inputs)
BackendModule.write_to_devices(::TimerProbeBackend, devices, output) = nothing
function BackendModule.wait_for_input(backend::TimerProbeBackend, devices, timeout_seconds)
    push!(backend.waits, timeout_seconds)
    isempty(backend.inputs) && sleep(min(timeout_seconds, 1.0))
    nothing
end
BackendModule.quit_backend!(::TimerProbeBackend) = nothing

function _timer_editor(backend::TimerProbeBackend, log::Vector{Any}; delay::Real = 0.1)
    editor = Editor(TimerProbe(), TimerProbeProjection(log, Float64(delay));
                    backend = backend, devices = Device[])
    print!(editor)
    editor
end

function test_editor_timer()
@testset "the editor's timers" begin
    @testset "a timer bounds the wait, and one set again under its name replaces it" begin
        editor = _timer_editor(TimerProbeBackend(), Any[])
        @test compute_wait_timeout(editor) == Inf
        now = time()
        evaluate_operation(editor, SetTimerOperation(:a, now + 10))
        @test editor.timers == Dict(:a => now + 10)
        @test 9 < compute_wait_timeout(editor) <= 10
        evaluate_operation(editor, SetTimerOperation(:a, now + 5))
        @test editor.timers == Dict(:a => now + 5)
        @test 4 < compute_wait_timeout(editor) <= 5
        evaluate_operation(editor, SetTimerOperation(:b, now + 2))
        @test length(editor.timers) == 2
        @test 1 < compute_wait_timeout(editor) <= 2
        # A time that passed does not make the wait negative.
        evaluate_operation(editor, SetTimerOperation(:c, now - 1))
        @test compute_wait_timeout(editor) == 0.0
    end

    @testset "a timer whose time has not come is not read" begin
        log = Any[]
        editor = _timer_editor(TimerProbeBackend(), log)
        evaluate_operation(editor, SetTimerOperation(:a, time() + 10))
        @test read!(editor) == false
        @test isempty(log)
        @test haskey(editor.timers, :a)
    end

    @testset "a timer whose time came is read first, the earliest first, and leaves" begin
        log = Any[]
        key = WindowInput(:main, KeyDown(:x, ModifierKeys(); time = 0.0))
        editor = _timer_editor(TimerProbeBackend(Any[key]), log)
        now = time()
        evaluate_operation(editor, SetTimerOperation(:late, now - 1))
        evaluate_operation(editor, SetTimerOperation(:early, now - 2))
        @test read!(editor) == true
        evaluate!(editor)
        @test log == Any[TimerExpire(:early, now - 2)]
        @test read!(editor) == true
        evaluate!(editor)
        @test log == Any[TimerExpire(:early, now - 2), TimerExpire(:late, now - 1)]
        @test isempty(editor.timers)
        # The device input waited behind the timers, and it sets a timer of its own.
        @test read!(editor) == true
        @test editor.operation == SetTimerOperation(:x, 0.1)
    end

    @testset "the loop wakes at a timer that a reader set" begin
        log = Any[]
        started = time()
        key = WindowInput(:main, KeyDown(:probe, ModifierKeys(); time = started))
        backend = TimerProbeBackend(Any[key])
        editor = _timer_editor(backend, log; delay = 0.5)
        loop = @async run_editor!(editor)
        @test timedwait(() -> !isempty(log), 5.0) === :ok
        @test log == Any[TimerExpire(:probe, started + 0.5)]
        # The event came at its time, not before it.
        @test time() >= started + 0.5
        # The first wait, after the frame that set the timer, was bounded by it.
        # The waits after the event are unbounded, because no timer is left.
        @test first(backend.waits) <= 0.5
        post_operation!(editor, QuitEditorOperation())
        @test timedwait(() -> istaskdone(loop), 5.0) === :ok
        @test !istaskfailed(loop)
    end

    @testset "a timer edits no document and passes every reader" begin
        operation = SetTimerOperation(:a, 1.0)
        @test operation_travels_unchanged(operation)
        @test make_inverse_operation(TimerProbe(), operation) == DoNothingOperation()
        @test describe_operation(operation) == "set the timer a"
        @test SetTimerOperation(:a, 1) == SetTimerOperation(:a, 1.0)
    end
end
end # test_editor_timer
