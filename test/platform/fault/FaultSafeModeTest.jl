# The safe mode — the last guarantee that the editor shows something.
#
# The case is a printer that fails on every frame and that no repair helps. The
# editor keeps running either way; the question this suite answers is whether a
# person is left looking at a window that stopped moving, or at the list of what
# went wrong.


@document struct SafeModeProbe
    value::Int = 0
end

struct AlwaysFailingProjection <: Projection end
ProjectionModule.print_document(::AlwaysFailingProjection, recursion, input, ctx) =
    error("this printer never works")
ProjectionModule.read_intent(::AlwaysFailingProjection, recursion, change::Intent, iomap) = change

# Fails to print while `is_broken[]` holds, and turns the key `a` into an
# operation that records it.
struct RecoveringProjection <: Projection
    is_broken::Base.RefValue{Bool}
    log::Vector{Any}
end
ProjectionModule.print_document(p::RecoveringProjection, recursion, input, ctx) =
    p.is_broken[] ? error("this printer does not work yet") :
                    SimpleIoMap(nothing, input, input)
function ProjectionModule.read_intent(p::RecoveringProjection, recursion, change::Intent,
                                      iomap)
    gesture = change.gesture
    event = gesture isa WindowInput ? gesture.event : gesture
    (event isa KeyDown && event.key === :a) || return change
    Intent(gesture, RecordKeyOperation(p.log))
end

struct RecordKeyOperation <: Operation
    log::Vector{Any}
end
OperationModule.evaluate_operation(::Editor, operation::RecordKeyOperation) =
    (push!(operation.log, :a); nothing)

_tolerant_policy() = FaultPolicy(is_console_enabled = false, is_sound_enabled = false)

function _failing_editor()
    editor = Editor(SafeModeProbe(), AlwaysFailingProjection();
                    backend = HeadlessBackend(), devices = Device[])
    editor.fault_policy = _tolerant_policy()
    editor
end

_escape() = WindowInput(:main, KeyDown(:escape, ModifierKeys(); time = 0.0))

function test_fault_safe_mode()
@testset "the safe mode" begin

    @testset "a printer that always fails takes the editor into the safe mode" begin
        editor = _failing_editor()
        @test !is_editor_in_safe_mode(editor)
        for _ in 1:get_consecutive_fault_limit(:print)
            run_frame!(editor)
        end
        @test is_editor_in_safe_mode(editor)
        @test editor.replaced_projection isa AlwaysFailingProjection
        @test editor.projection isa FaultSafeModeProjection
    end

    @testset "the safe mode draws, where the projection it replaced could not" begin
        editor = _failing_editor()
        for _ in 1:get_consecutive_fault_limit(:print)
            run_frame!(editor)
        end
        # The frame after it entered paints the list rather than nothing.
        run_frame!(editor)
        output = editor.iomap.output
        @test (output isa Cell ? output[] : output) !== nothing
    end

    @testset "the safe mode shows the fault that caused it" begin
        editor = _failing_editor()
        for _ in 1:get_consecutive_fault_limit(:print)
            run_frame!(editor)
        end
        log = editor.projection.log
        @test length(log.entries) >= 1
        @test log.entries[1].origin === :AlwaysFailingProjection
    end

    @testset "Escape leaves the safe mode rather than quitting" begin
        editor = _failing_editor()
        for _ in 1:get_consecutive_fault_limit(:print)
            run_frame!(editor)
        end
        @test is_editor_in_safe_mode(editor)
        # One frame to paint the safe mode. Entering it drops the cached IoMap,
        # and `run_read_stage!` discards an input it has no IoMap for, so a gesture sent
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

    @testset "the input behind the Escape out of the safe mode waits for a paint" begin
        is_broken = Ref(true)
        log = Any[]
        editor = Editor(SafeModeProbe(), RecoveringProjection(is_broken, log);
                        backend = HeadlessBackend(), devices = Device[])
        editor.fault_policy = _tolerant_policy()
        for _ in 1:get_consecutive_fault_limit(:print)
            run_frame!(editor)
        end
        @test is_editor_in_safe_mode(editor)
        run_frame!(editor)                   # one frame to paint the safe mode
        is_broken[] = false
        push_event!(editor.backend, _escape())
        push_event!(editor.backend,
                    WindowInput(:main, KeyDown(:a, ModifierKeys(); time = 0.0)))
        Threads.atomic_xchg!(editor.wake_pending, false)
        run_frame!(editor)
        @test !is_editor_in_safe_mode(editor)
        @test isempty(log)                   # the key waits for the paint
        @test editor.wake_pending[]          # which the next frame makes at once
        run_frame!(editor)
        @test log == [:a]
    end

    @testset "a strict editor never enters the safe mode" begin
        editor = Editor(SafeModeProbe(), AlwaysFailingProjection();
                        backend = HeadlessBackend(), devices = Device[])
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

# The one call a program makes. It is the shape the app uses, so a test drives
# it the way the app does: a real editor, real frames, and a pipeline that
# fails.
function test_fault_tolerant_projection()
@testset "the root wiring" begin

    @testset "a program that wires it survives its own broken pipeline" begin
        projection, log = make_fault_tolerant_projection(AlwaysFailingProjection())
        editor = Editor(SafeModeProbe(), projection;
                        backend = HeadlessBackend(), devices = Device[])
        editor.fault_policy = _tolerant_policy()
        attach_fault_target!(editor.faults, log)
        for _ in 1:3
            run_frame!(editor)
        end
        # The frame did not throw, the fault was collected, and it reached the
        # log the panel draws.
        @test length(get_fault_records(editor.faults)) == 1
        @test length(log.entries) == 1
        @test log.entries[1].origin === :AlwaysFailingProjection
    end

    @testset "the panel is not there while nothing has failed" begin
        projection, log = make_fault_tolerant_projection(IdentityProjection())
        editor = Editor(SafeModeProbe(), projection;
                        backend = HeadlessBackend(), devices = Device[])
        editor.fault_policy = _tolerant_policy()
        attach_fault_target!(editor.faults, log)
        run_frame!(editor)
        @test isempty(get_fault_records(editor.faults))
        @test length(log.entries) == 0
    end
end
end
