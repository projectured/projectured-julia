# One frame applies everything the backend has waiting, then paints once.
#
# Input arrives faster than a frame can paint. A frame that applied one
# operation and repainted made a burst of input cost one frame — plus one
# `sleep` — for each step in it, which is what made a hover highlight fall
# behind a pointer crossing several widgets.

using Test
using ProjecturedKernel.EventModule
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.DocumentModule
import ProjecturedKernel.EditorModule
import ProjecturedKernel.EditorModule: Editor, MAX_OPERATIONS_PER_FRAME, post_operation!,
                                       drain_operations!
import ProjecturedKernel.FaultModule: FaultPolicy, get_fault_records
import ProjecturedKernel.OperationModule: Operation, evaluate_operation, invalidate_projection!,
                                          make_inverse_operation
using ProjecturedKernelExample

@document struct FrameDrainProbe
    value::Int = 0
end

# Records what was applied, in order.
struct DrainFrameOperation <: Operation
    log::Vector{Any}
    tag::Any
end

evaluate_operation(::Editor, op::DrainFrameOperation) = (push!(op.log, op.tag); nothing)

# Stands for a whole-root swap: it drops the editor's cached projection.
struct DrainFrameSwapOperation <: Operation
    log::Vector{Any}
end

evaluate_operation(editor::Editor, op::DrainFrameSwapOperation) =
    (push!(op.log, :swap); invalidate_projection!(editor); nothing)

# Writes the value of the document, then fails: an operation that fails half way.
struct HalfWayFrameOperation <: Operation
    value::Int
end

evaluate_operation(editor::Editor, operation::HalfWayFrameOperation) =
    (editor.document.value = operation.value; error("the operation failed half way"))

# The way back writes the value that the document holds before the change.
make_inverse_operation(document, ::HalfWayFrameOperation) =
    RestoreFrameValueOperation(document.value)

struct RestoreFrameValueOperation <: Operation
    value::Int
end

evaluate_operation(editor::Editor, operation::RestoreFrameValueOperation) =
    (editor.document.value = operation.value; nothing)

_quiet_frame_policy() = FaultPolicy(is_console_enabled = false, is_sound_enabled = false)

# Turns each scripted window input into one operation, so a queue of N events is
# a queue of N operations. It throws on a `MouseUp`, as a broken reader does.
struct FrameDrainProjection <: Projection
    log::Vector{Any}
end
ProjectionModule.print_document(::FrameDrainProjection, recursion, input, ctx) =
    SimpleIoMap(nothing, input, input)
function ProjectionModule.read_intent(p::FrameDrainProjection, recursion, change::Intent,
                                      iomap)
    gesture = change.gesture
    gesture isa WindowInput && gesture.event isa MouseUp && error("the reader failed")
    Intent(gesture,
           gesture === :swap ? DrainFrameSwapOperation(p.log) :
                               DrainFrameOperation(p.log, gesture))
end

function _frame_editor(log)
    backend = HeadlessBackend()
    editor = Editor(FrameDrainProbe(), FrameDrainProjection(log);
                    backend = backend, devices = Device[])
    EditorModule.print!(editor)          # a reader is only reached once an iomap exists
    (editor, backend)
end

function test_editor_frame_drain()
@testset "one frame drains the input of that frame" begin

    @testset "every waiting operation is applied before the paint" begin
        log = Any[]
        editor, backend = _frame_editor(log)
        painted_before = length(rendered_output(backend))
        for tag in (:a, :b, :c, :d)
            push_event!(backend, tag)
        end
        EditorModule.run_frame!(editor)
        @test log == [:a, :b, :c, :d]                       # all four, in order
        @test length(rendered_output(backend)) == painted_before + 1   # one paint
    end

    @testset "an idle frame still paints" begin
        log = Any[]
        editor, backend = _frame_editor(log)
        painted_before = length(rendered_output(backend))
        EditorModule.run_frame!(editor)
        @test isempty(log)
        @test length(rendered_output(backend)) == painted_before + 1
    end

    @testset "the last applied operation stays in `operation`" begin
        # `perf!` reads this field to tell a frame that did something from an
        # idle one, and `read!` clears it when the input runs out.
        log = Any[]
        editor, backend = _frame_editor(log)
        push_event!(backend, :first)
        push_event!(backend, :last)
        EditorModule.run_frame!(editor)
        @test editor.operation isa DrainFrameOperation
        @test editor.operation.tag === :last
        EditorModule.run_frame!(editor)
        @test editor.operation === nothing               # an idle frame reports none
    end

    @testset "an operation that drops the projection ends the frame" begin
        # `read!` discards an input it has no IoMap for. Input behind a whole-root
        # swap therefore has to wait for the repaint that rebuilds the projection.
        log = Any[]
        editor, backend = _frame_editor(log)
        push_event!(backend, :before)
        push_event!(backend, :swap)
        push_event!(backend, :after)
        Threads.atomic_xchg!(editor.wake_pending, false)
        EditorModule.run_frame!(editor)
        @test log == [:before, :swap]        # `:after` is not consumed by this frame
        @test editor.wake_pending[]          # and the next frame runs at once
        EditorModule.run_frame!(editor)
        @test log == [:before, :swap, :after]
    end

    @testset "a frame is bounded, so a paint is never held off" begin
        log = Any[]
        editor, backend = _frame_editor(log)
        for i in 1:(MAX_OPERATIONS_PER_FRAME + 5)
            push_event!(backend, i)
        end
        Threads.atomic_xchg!(editor.wake_pending, false)
        EditorModule.run_frame!(editor)
        @test length(log) == MAX_OPERATIONS_PER_FRAME
        @test editor.wake_pending[]                      # the next frame runs at once
        EditorModule.run_frame!(editor)                  # the rest, on the next frame
        @test length(log) == MAX_OPERATIONS_PER_FRAME + 5
    end

    @testset "a reader that throws ends the reads, and the next frame runs at once" begin
        # The reader throws on the `MouseUp`, so the reads of the frame end there,
        # and the key after it waits for the next frame, which runs at once.
        log = Any[]
        editor, backend = _frame_editor(log)
        editor.fault_policy = _quiet_frame_policy()
        push_event!(backend, WindowInput(:probe, MouseDown(:left, 5, 5; time = 0.0)))
        push_event!(backend, WindowInput(:probe, MouseUp(:left, 5, 5; time = 0.1)))
        push_event!(backend, WindowInput(:probe, KeyDown(:a, ModifierKeys(); time = 0.2)))
        Threads.atomic_xchg!(editor.wake_pending, false)
        EditorModule.run_frame!(editor)
        @test length(log) == 1 && log[1].event isa MouseDown
        @test editor.wake_pending[]
        @test only(get_fault_records(editor.faults)).site === :read
        EditorModule.run_frame!(editor)
        @test length(log) == 2 && log[2].event isa KeyDown
    end

    @testset "a frame that reads all the input leaves the wake alone" begin
        log = Any[]
        editor, backend = _frame_editor(log)
        push_event!(backend, :only)
        Threads.atomic_xchg!(editor.wake_pending, false)
        EditorModule.run_frame!(editor)
        @test log == [:only]
        @test !editor.wake_pending[]
    end

    @testset "a posted operation that fails is taken back, and the next one applies" begin
        log = Any[]
        editor, backend = _frame_editor(log)
        editor.fault_policy = _quiet_frame_policy()
        post_operation!(editor, HalfWayFrameOperation(7))
        post_operation!(editor, DrainFrameOperation(log, :next))
        @test drain_operations!(editor) == 2
        @test editor.document.value == 0             # the inverse took the change back
        @test log == [:next]                         # in the same drain
        @test editor.iomap === nothing               # the next print starts from scratch
        records = get_fault_records(editor.faults)
        @test length(records) == 1
        @test records[1].origin === :HalfWayFrameOperation
    end

end
end # test_editor_frame_drain

export test_editor_frame_drain
