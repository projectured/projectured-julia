# A bare Escape that nothing took quits an editor whose projection is an
# `EscapeQuittingProjection`. The wrapper `quit_on_escape` of `build_editor` puts
# it around everything, and it is off by default, so the window of a program does
# not close on Escape.

# Takes a bare Escape, as an open popup or a dialog does.
struct EscapeTakingProjection <: Projection end
ProjectionModule.print_document(p::EscapeTakingProjection, recursion, input, ctx) =
    SimpleIoMap(p, input, input)
function ProjectionModule.read_intent(::EscapeTakingProjection, recursion, change::Intent, iomap)
    gesture = change.gesture
    event = gesture isa WindowInput ? gesture.event : gesture
    event isa KeyDown && event.key === :escape ?
        Intent(gesture, DoNothingOperation()) : Intent(gesture, nothing)
end

# Takes nothing.
struct EscapeIgnoringProjection <: Projection end
ProjectionModule.print_document(p::EscapeIgnoringProjection, recursion, input, ctx) =
    SimpleIoMap(p, input, input)
ProjectionModule.read_intent(::EscapeIgnoringProjection, recursion, change::Intent, iomap) =
    Intent(change.gesture, nothing)

# The operation that the wrapper answers to `gesture` around `inner`.
function _eq_answer(inner, gesture)
    projection = EscapeQuittingProjection(inner = inner)
    iomap = print_document(projection, PrimitiveString("x"))
    read_intent(projection, nothing, Intent(gesture), iomap).operation
end

# An editor on a label, on the headless backend, after its first frame.
function _eq_editor(; keywords...)
    editor = build_editor(WidgetLabel("Name"),
        NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
        backend = HeadlessBackend(), devices = Device[Keyboard(), Mouse()],
        tabs = false, keywords...)
    run_frame!(editor)
    editor
end

# The id of the one window of the screen of `editor`.
function _eq_window_id(editor)
    document = editor.document
    while !(document isa ScreenDocument)
        document = document.content
    end
    only(document.windows).id
end

# Whether the editor reads an operation from `event` in its window, and the operation.
function _eq_read!(editor, event)
    push_event!(editor.backend, WindowInput(_eq_window_id(editor), event))
    (EditorModule.run_read_stage!(editor), editor.operation)
end

_eq_escape(; modifiers...) = KeyDown(:escape, ModifierKeys(; modifiers...); time = 0.0)

function test_escape_quitting()
@testset "a bare Escape that nothing took quits" begin
    @testset "the projection answers a bare Escape that its inner projection did not take" begin
        @test _eq_answer(EscapeIgnoringProjection(), _eq_escape()) isa QuitEditorOperation
        @test _eq_answer(EscapeIgnoringProjection(), WindowInput(:W, _eq_escape())) isa
              QuitEditorOperation
        @test _eq_answer(EscapeTakingProjection(), _eq_escape()) isa DoNothingOperation
        @test _eq_answer(EscapeIgnoringProjection(), _eq_escape(ctrl = true)) === nothing
        @test _eq_answer(EscapeIgnoringProjection(), KeyDown(:home, ModifierKeys(); time = 0.0)) ===
              nothing
    end

    @testset "the wrapper is off by default" begin
        editor = _eq_editor()
        @test !(editor.projection isa EscapeQuittingProjection)
        @test _eq_read!(editor, _eq_escape()) == (false, nothing)
    end

    @testset "the wrapper is around everything, and an Escape quits the editor" begin
        editor = _eq_editor(; quit_on_escape = true)
        @test editor.projection isa EscapeQuittingProjection
        (is_read, operation) = _eq_read!(editor, _eq_escape())
        @test is_read
        @test operation isa QuitEditorOperation
    end

    @testset "with the wrapper, a modified Escape and another key pass on" begin
        editor = _eq_editor(; quit_on_escape = true)
        @test _eq_read!(editor, _eq_escape(ctrl = true)) == (false, nothing)
        @test _eq_read!(editor, KeyDown(:f9, ModifierKeys(); time = 0.0)) == (false, nothing)
    end
end
end # test_escape_quitting
