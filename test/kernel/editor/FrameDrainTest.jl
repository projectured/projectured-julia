# One frame applies everything the backend has waiting, then paints once.
#
# Input arrives faster than a frame can paint. A frame that applied one
# operation and repainted made a burst of input cost one frame — plus one
# `sleep` — for each step in it, which is what made a hover highlight fall
# behind a pointer crossing several widgets.

using Test
using ProjecturedKernel.EventModule
using ProjecturedKernel.ProjectionApiModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.DocumentModule
import ProjecturedKernel.EditorModule
import ProjecturedKernel.EditorModule: Editor, MAX_OPERATIONS_PER_FRAME
import ProjecturedKernel.OperationModule: Operation, evaluate_operation, invalidate_projection!
using ProjecturedKernelExample

@document struct FrameDrainProbe
    value::Int = 0
end

# Records what was applied, in order.
struct FrameDrainOperation <: Operation
    log::Vector{Any}
    tag::Any
end

evaluate_operation(::Editor, op::FrameDrainOperation) = (push!(op.log, op.tag); nothing)

# Stands for a whole-root swap: it drops the editor's cached projection.
struct FrameDrainSwapOperation <: Operation
    log::Vector{Any}
end

evaluate_operation(editor::Editor, op::FrameDrainSwapOperation) =
    (push!(op.log, :swap); invalidate_projection!(editor); nothing)

# Turns each scripted window input into one operation, so a queue of N events is
# a queue of N operations.
struct FrameDrainProjection <: Projection
    log::Vector{Any}
end
ProjectionApiModule.print_document(::FrameDrainProjection, recursion, input, ctx) =
    SimpleIoMap(nothing, input, input)
ProjectionApiModule.read_intent(p::FrameDrainProjection, recursion, change::Intent, iomap) =
    Intent(change.gesture,
           change.gesture === :swap ? FrameDrainSwapOperation(p.log) :
                                      FrameDrainOperation(p.log, change.gesture))

function _frame_editor(log)
    backend = HeadlessBackend()
    editor = Editor(backend, FrameDrainProbe(), FrameDrainProjection(log), Device[])
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
        @test editor.operation isa FrameDrainOperation
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
        EditorModule.run_frame!(editor)
        @test log == [:before, :swap]        # `:after` is not consumed by this frame
        EditorModule.run_frame!(editor)
        @test log == [:before, :swap, :after]
    end

    @testset "a frame is bounded, so a paint is never held off" begin
        log = Any[]
        editor, backend = _frame_editor(log)
        for i in 1:(MAX_OPERATIONS_PER_FRAME + 5)
            push_event!(backend, i)
        end
        EditorModule.run_frame!(editor)
        @test length(log) == MAX_OPERATIONS_PER_FRAME
        EditorModule.run_frame!(editor)                  # the rest, on the next frame
        @test length(log) == MAX_OPERATIONS_PER_FRAME + 5
    end

end
end # test_editor_frame_drain

export test_editor_frame_drain
