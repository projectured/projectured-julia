# Escape closes the editor, but only when no reader wanted it.
#
# A backend reports what happened and decides no meaning, so Escape arrives as an
# ordinary `KeyDown(:escape, …)`. If a backend turned it into a `WindowQuit`, the
# quit could not be declined and every reader that binds Escape — a dialog, an
# insertion, the command palette — would be unreachable. The editor loop makes the
# decision instead, after the pipeline has had its say.

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
    editor = Editor(HeadlessBackend(), EscapeProbe(), projection, Device[])
    EditorModule.print!(editor)                       # the loop skips the pipeline with no iomap
    editor
end

_press!(editor, event) = push_event!(editor.backend, WindowInput(:probe, event))

function test_escape_quit()
@testset "Escape quits only when nothing handled it" begin
    none = ModifierKeys()

    @testset "an Escape no reader wanted closes the editor" begin
        editor = _escape_editor(EscapeDecliningProjection())
        _press!(editor, KeyDown(:escape, none))
        @test EditorModule.read!(editor)
        @test editor.operation isa QuitEditorOperation
    end

    @testset "an Escape a reader claimed does not" begin
        editor = _escape_editor(EscapeClaimingProjection())
        _press!(editor, KeyDown(:escape, none))
        @test EditorModule.read!(editor)
        @test editor.operation isa DoNothingOperation
        @test !(editor.operation isa QuitEditorOperation)
    end

    @testset "a modified Escape is left to the projections" begin
        editor = _escape_editor(EscapeDecliningProjection())
        _press!(editor, KeyDown(:escape, ModifierKeys(ctrl=true)))
        @test !EditorModule.read!(editor)                        # drained, nothing produced
        @test editor.operation === nothing
    end

    @testset "a real quit still closes the editor whatever the readers say" begin
        editor = _escape_editor(EscapeClaimingProjection())
        _press!(editor, WindowQuit())
        @test EditorModule.read!(editor)
        @test editor.operation isa QuitEditorOperation
    end

    @testset "another key is not a quit" begin
        editor = _escape_editor(EscapeDecliningProjection())
        _press!(editor, KeyDown(:home, none))
        @test !EditorModule.read!(editor)
        @test editor.operation === nothing
    end
end
end

export test_escape_quit
