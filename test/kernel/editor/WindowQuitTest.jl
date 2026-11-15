# The editor quits on a `WindowQuit`, and on no key.
#
# A backend reports what happened and decides no meaning, so Escape arrives as an
# ordinary `KeyDown(:escape, …)`. If a backend turned it into a `WindowQuit`, the
# quit could not be declined and every reader that binds Escape — a dialog, an
# insertion, the command palette — would be unreachable. A projection that wants
# Escape to quit answers it; the editor answers no key itself.

using Test
using ProjecturedKernel.EventModule
using ProjecturedKernel.OperationModule
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.DocumentModule
import ProjecturedKernel.EditorModule
import ProjecturedKernel.EditorModule: Editor
using ProjecturedKernelExample

# A document to hang the pipeline on.
@document struct EscapeProbe
    value::Int = 0
end

# Declines everything: the gesture passes through unchanged, as a reader that has
# no use for it does.
struct EscapeDecliningProjection <: Projection end
ProjectionModule.print_document(::EscapeDecliningProjection, recursion, input, ctx) =
    SimpleIoMap(nothing, input, input)
ProjectionModule.read_intent(::EscapeDecliningProjection, recursion, change::Intent, iomap) =
    change

# Claims Escape, the way an open palette or a modal dialog does.
struct EscapeClaimingProjection <: Projection end
ProjectionModule.print_document(::EscapeClaimingProjection, recursion, input, ctx) =
    SimpleIoMap(nothing, input, input)
function ProjectionModule.read_intent(::EscapeClaimingProjection, recursion, change::Intent, iomap)
    gesture = change.gesture
    event = gesture isa WindowInput ? gesture.event : gesture
    (event isa KeyDown && event.key === :escape) &&
        return Intent(gesture, DoNothingOperation())
    return change
end

function _escape_editor(projection)
    editor = Editor(EscapeProbe(), projection;
                    backend = HeadlessBackend(), devices = Device[])
    EditorModule.run_print_stage!(editor)                       # the loop skips the pipeline with no iomap
    editor
end

_press!(editor, event) = push_event!(editor.backend, WindowInput(:probe, event))

function test_window_quit()
@testset "the editor quits on a WindowQuit and on no key" begin
    none = ModifierKeys()

    @testset "a WindowQuit closes the editor whatever the readers say" begin
        editor = _escape_editor(EscapeClaimingProjection())
        _press!(editor, WindowQuit(; time = 0.0))
        @test EditorModule.run_read_stage!(editor)
        @test editor.operation isa QuitEditorOperation
    end

    @testset "an Escape that no reader wanted is consumed, bare or modified" begin
        for modifiers in (none, ModifierKeys(ctrl=true))
            editor = _escape_editor(EscapeDecliningProjection())
            _press!(editor, KeyDown(:escape, modifiers; time = 0.0))
            @test !EditorModule.run_read_stage!(editor)                    # drained, nothing produced
            @test editor.operation === nothing
        end
    end

    @testset "an Escape a reader claimed gives the answer of the reader" begin
        editor = _escape_editor(EscapeClaimingProjection())
        _press!(editor, KeyDown(:escape, none; time = 0.0))
        @test EditorModule.run_read_stage!(editor)
        @test editor.operation isa DoNothingOperation
    end

    @testset "another key is not a quit" begin
        editor = _escape_editor(EscapeDecliningProjection())
        _press!(editor, KeyDown(:home, none; time = 0.0))
        @test !EditorModule.run_read_stage!(editor)
        @test editor.operation === nothing
    end

    @testset "run_evaluate_stage! logs the operation in the words of describe_operation" begin
        editor = _escape_editor(EscapeDecliningProjection())
        path = annotate_reference_types(editor.document,
                                        Reference(FieldReferenceStep("value")))
        editor.operation = ReplaceSelectionOperation(path)
        line = "[operation] " * describe_operation(editor.operation)
        @test_logs (:info, line) EditorModule.run_evaluate_stage!(editor)
    end
end
end

export test_window_quit
