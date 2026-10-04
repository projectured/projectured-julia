# The fault barriers of the editor loop, `editor/FaultBarriers.jl`: the barrier of
# each stage of a frame, the repairs after an operation that failed half way, the
# two breakers of the device seam, and the barriers of the loop around a frame.
#
# Every editor here runs under a policy that catches, over a backend that throws
# on demand. The property under test is that a fault costs its stage and not the
# editor, and that the fault is recorded.

using Test
using ProjecturedKernel.DeviceModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.FeedModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.SelectionModule
import ProjecturedKernel.BackendModule
import ProjecturedKernel.BackendModule: Backend
import ProjecturedKernel.ClockModule: get_clock_time
import ProjecturedKernel.EditorModule
import ProjecturedKernel.EditorModule: Editor, run_editor!, run_frame!, post_operation!,
                                       get_consecutive_fault_limit, is_editor_degraded,
                                       RunFunctionOperation
import ProjecturedKernel.FaultModule: FaultPolicy, get_fault_records
import ProjecturedKernel.OperationModule: Operation, evaluate_operation,
                                          make_inverse_operation, QuitEditorOperation
using ProjecturedKernelExample

@document struct BarrierProbe
    value::Int = 0
end

# A backend that throws on demand: in `take_from_devices!`, in `write_to_devices!`
# or in `get_frame_clock_time`, while the switch of that call is on. It counts
# the calls of each half of the device seam, and its wait returns at once.
mutable struct BarrierProbeBackend <: Backend
    events::Vector{Any}
    is_read_broken::Bool
    is_write_broken::Bool
    is_clock_broken::Bool
    reads::Int
    writes::Int
end
BarrierProbeBackend() = BarrierProbeBackend(Any[], false, false, false, 0, 0)

function BackendModule.take_from_devices!(backend::BarrierProbeBackend, devices)
    backend.reads += 1
    backend.is_read_broken && error("the read failed")
    isempty(backend.events) ? nothing : popfirst!(backend.events)
end
function BackendModule.write_to_devices!(backend::BarrierProbeBackend, devices, output)
    backend.writes += 1
    backend.is_write_broken && error("the write failed")
    nothing
end
BackendModule.wait_for_input(::BarrierProbeBackend, devices, timeout_seconds) = nothing
BackendModule.quit_backend!(::BarrierProbeBackend) = nothing
EditorModule.get_frame_clock_time(backend::BarrierProbeBackend, wall_time) =
    backend.is_clock_broken ? error("the clock failed") : wall_time

# Turns a scripted symbol into an operation that records it, and throws on the
# symbol `:throw`. Every other gesture passes through, so a key reaches the keys
# of the loop.
struct BarrierProbeProjection <: Projection
    log::Vector{Any}
end
ProjectionModule.print_document(::BarrierProbeProjection, recursion, input, ctx) =
    SimpleIoMap(nothing, input, input)
function ProjectionModule.read_intent(p::BarrierProbeProjection, recursion,
                                      change::Intent, iomap)
    gesture = change.gesture
    gesture === :throw && error("the reader failed")
    gesture isa Symbol || return change
    Intent(gesture, BarrierLogOperation(p.log, gesture))
end

struct BarrierLogOperation <: Operation
    log::Vector{Any}
    tag::Any
end
evaluate_operation(::Editor, operation::BarrierLogOperation) =
    (push!(operation.log, operation.tag); nothing)

# Writes the value of the document, then fails: an operation that fails half way.
# Its way back writes the value that the document holds before the change.
struct HalfWayBarrierOperation <: Operation
    value::Int
end
evaluate_operation(editor::Editor, operation::HalfWayBarrierOperation) =
    (editor.document.value = operation.value; error("the operation failed half way"))
make_inverse_operation(document, ::HalfWayBarrierOperation) =
    SetBarrierValueOperation(document.value)

struct SetBarrierValueOperation <: Operation
    value::Int
end
evaluate_operation(editor::Editor, operation::SetBarrierValueOperation) =
    (editor.document.value = operation.value; nothing)

# Selects a place that the document does not have, then fails.
struct LoseSelectionBarrierOperation <: Operation end
function evaluate_operation(editor::Editor, ::LoseSelectionBarrierOperation)
    editor.document.selection = Reference(FieldReferenceStep("missing"))
    error("the operation failed")
end

# Applies, but its way back can not be made.
struct UninvertibleBarrierOperation <: Operation
    log::Vector{Any}
end
evaluate_operation(::Editor, operation::UninvertibleBarrierOperation) =
    (push!(operation.log, :applied); nothing)
make_inverse_operation(document, ::UninvertibleBarrierOperation) = error("no way back")

# Fails, and its way back throws `exception`.
struct BrokenWayBackBarrierOperation <: Operation
    exception::Exception
end
evaluate_operation(::Editor, ::BrokenWayBackBarrierOperation) =
    error("the operation failed")
make_inverse_operation(document, operation::BrokenWayBackBarrierOperation) =
    ThrowBarrierOperation(operation.exception)

struct ThrowBarrierOperation <: Operation
    exception::Exception
end
evaluate_operation(::Editor, operation::ThrowBarrierOperation) =
    throw(operation.exception)

# Throws in every drain.
struct FailingBarrierFeed <: Feed end
FeedModule.drain_changes!(::FailingBarrierFeed, editor::Editor) = error("the feed failed")

# Counts its drains, and posts a quit in the drain `quit_drain`.
mutable struct QuittingBarrierFeed <: Feed
    drains::Int
    quit_drain::Int
end
function FeedModule.drain_changes!(feed::QuittingBarrierFeed, editor::Editor)
    feed.drains += 1
    feed.drains == feed.quit_drain && post_operation!(editor, QuitEditorOperation())
    0
end

_quiet_barrier_policy() =
    FaultPolicy(is_console_enabled = false, is_sound_enabled = false)

# An editor under a policy that catches, printed once, so a reader has an IoMap.
function _barrier_editor(; feeds::Vector{Feed} = Feed[])
    backend = BarrierProbeBackend()
    log = Any[]
    editor = Editor(BarrierProbe(), BarrierProbeProjection(log);
                    backend = backend, devices = Device[],
                    fault_policy = _quiet_barrier_policy(), feeds = feeds)
    EditorModule.run_print_stage!(editor)
    (editor, backend, log)
end

function test_editor_fault_barriers()
@testset "the fault barriers of the editor loop" begin

    @testset "repairs 0 and 1: a failed operation is taken back and prints again" begin
        editor, backend, log = _barrier_editor()
        editor.operation = HalfWayBarrierOperation(7)
        EditorModule.run_evaluate_stage!(editor)
        @test editor.document.value == 0             # the way back
        @test editor.iomap === nothing               # the next print starts from scratch
        record = only(get_fault_records(editor.faults))
        @test record.site === :evaluate
        @test record.origin === :HalfWayBarrierOperation
    end

    @testset "repair 2: a selection that no longer resolves is cleared" begin
        editor, backend, log = _barrier_editor()
        editor.operation = LoseSelectionBarrierOperation()
        @test_logs (:warn, r"selection") match_mode = :any (
            EditorModule.run_evaluate_stage!(editor))
        @test get_selection(editor.document) === nothing
    end

    @testset "an inverse that can not be made is recorded, and the operation runs" begin
        editor, backend, log = _barrier_editor()
        editor.operation = UninvertibleBarrierOperation(log)
        EditorModule.run_evaluate_stage!(editor)
        @test log == [:applied]
        record = only(get_fault_records(editor.faults))
        @test record.site === :evaluate
        @test record.origin === :UninvertibleBarrierOperation
    end

    @testset "a way back that fails is recorded, and the other repairs still run" begin
        editor, backend, log = _barrier_editor()
        editor.operation = BrokenWayBackBarrierOperation(ArgumentError("no way back"))
        EditorModule.run_evaluate_stage!(editor)
        @test editor.iomap === nothing
        origins = Set(record.origin for record in get_fault_records(editor.faults))
        @test origins == Set([:BrokenWayBackBarrierOperation, :ThrowBarrierOperation])
    end

    @testset "an interrupt from the way back goes through the repair" begin
        editor, backend, log = _barrier_editor()
        editor.operation = BrokenWayBackBarrierOperation(InterruptException())
        @test_throws InterruptException EditorModule.run_evaluate_stage!(editor)
    end

    @testset "the input breaker stops the reads at its limit, and the editor paints" begin
        editor, backend, log = _barrier_editor()
        backend.is_read_broken = true
        limit = get_consecutive_fault_limit(:device_read)
        writes = backend.writes
        for _ in 1:limit
            run_frame!(editor)
        end
        @test backend.reads == limit
        @test is_editor_degraded(editor, :device_read)
        run_frame!(editor)
        @test backend.reads == limit                 # no read past the limit
        @test backend.writes == writes + limit + 1   # a paint in every frame
    end

    @testset "the output breaker stops the writes at its limit" begin
        editor, backend, log = _barrier_editor()
        backend.is_write_broken = true
        limit = get_consecutive_fault_limit(:device_write)
        writes = backend.writes
        for _ in 1:limit
            run_frame!(editor)
        end
        @test backend.writes == writes + limit
        @test is_editor_degraded(editor, :device_write)
        run_frame!(editor)
        @test backend.writes == writes + limit       # no write past the limit
    end

    @testset "a reader that throws costs its gesture, and the next frame reads on" begin
        editor, backend, log = _barrier_editor()
        push!(backend.events, :throw, :after)
        run_frame!(editor)
        @test isempty(log)
        @test only(get_fault_records(editor.faults)).site === :read
        run_frame!(editor)
        @test log == [:after]
    end

    @testset "a feed that throws in each frame stops neither the loop nor a feed" begin
        # The first feed ends the loop in its tenth drain, so a failing feed that
        # stops the feeds after it fails the test and does not hang it.
        bound = QuittingBarrierFeed(0, 10)
        quitting = QuittingBarrierFeed(0, 2)
        editor, backend, log =
            _barrier_editor(feeds = Feed[bound, FailingBarrierFeed(), quitting])
        run_editor!(editor)
        @test quitting.drains == 2
        record = only(get_fault_records(editor.faults))
        @test record.origin === :FailingBarrierFeed
        @test record.count == 2
    end

    @testset "a call that throws at the end of the loop is recorded or answered" begin
        editor, backend, log = _barrier_editor()
        answer = Channel{Any}(1)
        post_operation!(editor, QuitEditorOperation())
        failing_call = () -> error("the call failed")
        post_operation!(editor, RunFunctionOperation(failing_call, nothing))
        post_operation!(editor, RunFunctionOperation(failing_call, answer))
        run_editor!(editor)
        @test !isready(editor.inbox)
        # The call that no task waits for is recorded.
        @test only(get_fault_records(editor.faults)).origin === :RunFunctionOperation
        # The call that a task waits for answers the exception to that task.
        succeeded, value = take!(answer)
        @test !succeeded && value isa ErrorException
    end

    @testset "a frame clock that throws is recorded, and the frame shows wall time" begin
        editor, backend, log = _barrier_editor()
        backend.is_clock_broken = true
        post_operation!(editor, QuitEditorOperation())
        run_editor!(editor)
        record = only(get_fault_records(editor.faults))
        @test record.site === :device
        @test record.origin === :BarrierProbeBackend
        # The wall time since the loop started: more than no time, less than a
        # generous bound.
        @test 0 < get_clock_time(editor.clock) < 5
    end
end
end

export test_editor_fault_barriers
