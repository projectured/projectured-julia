# The safe mode — the last guarantee that the editor shows something.
#
# The case is a printer that fails on every frame and that no repair helps. The
# editor keeps running either way; the question this suite answers is whether a
# person is left looking at a window that stopped moving, or at the list of what
# went wrong.

using Test
using ProjecturedKernel.CellModule
using ProjecturedKernel.DeviceModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.FaultModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.EditorModule
import ProjecturedKernel.EditorModule: read!
using ProjecturedKernelExample
using ProjecturedFault.FaultViewModule

@document struct SafeModeProbe
    value::Int = 0
end

struct AlwaysFailingProjection <: Projection end
ProjectionModule.print_document(::AlwaysFailingProjection, recursion, input, ctx) =
    error("this printer never works")
ProjectionModule.read_intent(::AlwaysFailingProjection, recursion, change::Intent, iomap) = change

_tolerant_policy() = FaultPolicy(is_console_enabled = false, is_sound_enabled = false)

function _failing_editor()
    editor = Editor(HeadlessBackend(), SafeModeProbe(), AlwaysFailingProjection(), Device[])
    editor.fault_policy = _tolerant_policy()
    editor
end

_escape() = WindowInput(:main, KeyDown(:escape, ModifierKeys()))

function test_fault_safe_mode()
@testset "the safe mode" begin

    @testset "a printer that always fails takes the editor into the safe mode" begin
        editor = _failing_editor()
        @test !is_editor_in_safe_mode(editor)
        for _ in 1:editor.fault_policy.print_failure_limit
            run_frame!(editor)
        end
        @test is_editor_in_safe_mode(editor)
        @test editor.replaced_projection isa AlwaysFailingProjection
        @test editor.projection isa FaultSafeModeProjection
    end

    @testset "the safe mode draws, where the projection it replaced could not" begin
        editor = _failing_editor()
        for _ in 1:editor.fault_policy.print_failure_limit
            run_frame!(editor)
        end
        # The frame after it entered paints the list rather than nothing.
        run_frame!(editor)
        output = editor.iomap.output
        @test (output isa Cell ? output[] : output) !== nothing
    end

    @testset "the safe mode shows the fault that caused it" begin
        editor = _failing_editor()
        for _ in 1:editor.fault_policy.print_failure_limit
            run_frame!(editor)
        end
        log = editor.projection.log
        @test length(log.entries) >= 1
        @test log.entries[1].origin === :AlwaysFailingProjection
    end

    @testset "Escape leaves the safe mode rather than quitting" begin
        editor = _failing_editor()
        for _ in 1:editor.fault_policy.print_failure_limit
            run_frame!(editor)
        end
        @test is_editor_in_safe_mode(editor)
        # One frame to paint the safe mode. Entering it drops the cached IoMap,
        # and `read!` discards an input it has no IoMap for, so a gesture sent
        # before that paint would be thrown away — which is the documented
        # behaviour of every projection swap, not something the safe mode adds.
        run_frame!(editor)
        push_event!(editor.backend, _escape())
        run_frame!(editor)
        @test !is_editor_in_safe_mode(editor)
        @test editor.projection isa AlwaysFailingProjection
        # Escape did not become a quit while it was doing that.
        @test editor.operation === nothing
    end

    @testset "a strict editor never enters the safe mode" begin
        editor = Editor(HeadlessBackend(), SafeModeProbe(),
                        AlwaysFailingProjection(), Device[])
        @test_throws Exception run_frame!(editor)
        @test !is_editor_in_safe_mode(editor)
    end

    @testset "an editor that prints keeps its own projection" begin
        editor = _failing_editor()
        editor.projection = IdentityProjection()
        for _ in 1:10
            run_frame!(editor)
        end
        @test !is_editor_in_safe_mode(editor)
    end
end
end
