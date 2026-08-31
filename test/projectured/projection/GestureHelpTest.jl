# Tests for GestureHelpProjection — the content-level decorator that opens the
# gesture-help window on F1. Proves the mechanism without the full screen
# pipeline: the help gesture asks the reader what is available over the decorator's
# own inner iomap and emits an OpenWindowOperation carrying that GestureMap; a second F1 closes
# it (toggle); every other gesture passes straight through to the wrapped editor.

function test_gesture_help()
@testset "GestureHelpProjection" begin
    none = ModifierKeys()
    f1   = KeyDown(:f1, none)

    # A real content pipeline whose collector yields reified gestures.
    inner = RecursiveProjection(JsonToSyntax())
    mkarr() = (a = JsonArray([JsonNumber(1)]); set_selection!(a, EmptyReference()); a)

    @testset "F1 opens a window carrying the collected GestureMap" begin
        arr = mkarr()
        state = GestureHelpState()
        help = GestureHelpProjection(inner = inner, state = state)
        iomap = print_document(help, arr)

        # What the window must show == what the reader answers over the same iomap.
        answer = read_intent(inner, nothing, Intent(CollectIntents()), iomap.inner_iomap)
        expected = gesture_map(answer isa Intent ? answer.operation : answer)
        @test length(expected.rows) == 9          # the array's full reified set

        op = read_intent(help, iomap, f1)
        @test op isa OpenWindowOperation
        @test op.id === :gesture_help
        @test op.content isa GestureMap
        @test length(op.content.rows) == length(expected.rows)
        @test op.style === :normal
        @test state.open                          # toggled open
    end

    @testset "second F1 closes the window (toggle)" begin
        arr = mkarr()
        state = GestureHelpState()
        help = GestureHelpProjection(inner = inner, state = state)
        iomap = print_document(help, arr)

        @test read_intent(help, iomap, f1) isa OpenWindowOperation
        op = read_intent(help, iomap, f1)
        @test op isa CloseWindowOperation
        @test op.id === :gesture_help
        @test !state.open
    end

    @testset "non-help gestures pass through; help is not triggered" begin
        arr = mkarr()
        state = GestureHelpState()
        help = GestureHelpProjection(inner = inner, state = state)
        iomap = print_document(help, arr)

        op = read_intent(help, iomap, KeyDown(:comma, none))  # array insert
        @test !(op isa OpenWindowOperation)
        @test !state.open
        # The decorator returns exactly what the wrapped editor returned.
        direct = read_intent(inner, iomap.inner_iomap, KeyDown(:comma, none))
        @test typeof(op) === typeof(direct)
    end

    @testset "transparent printer: output is the inner's own output" begin
        arr = mkarr()
        help = GestureHelpProjection(inner = inner)
        io = print_document(help, arr)
        @test io.output === io.inner_iomap.output
    end

    # End-to-end through a real screen pipeline, mirroring the example wiring:
    # the content window is help-decorated, and a `GestureMap` type-dispatch arm
    # renders the help window the manager opens. Proves F1 in the focused window
    # opens a real sibling window carrying the collected gestures, and a second
    # F1 closes it — the same OpenWindowOperation rail tooltips ride.
    @testset "F1 opens (and closes) a real help window in a screen pipeline" begin
        arr = mkarr()
        state = GestureHelpState()
        projection = RecursiveProjection(
            TypeDispatchingProjection(
                ScreenDocument => WindowManagingProjection(inner = ScreenToScreen()),
                WindowDocument => ScreenToScreen(),
                GestureMap     => GestureMapToSyntax(),
                JsonArray      => GestureHelpProjection(inner = RecursiveProjection(JsonToSyntax()),
                                                        state = state),
                Any            => IdentityProjection(),
            ),
        )
        screen = ScreenDocument([WindowDocument(; id = :default, content = arr)])
        iomap = print_document(projection, screen)
        @test length(screen.windows) == 1

        # F1 in the focused window → a help window appears beside it.
        op = read_intent(projection, iomap, WindowInput(:default, f1))
        @test !(op isa Operation)                       # consumed by the manager
        @test length(screen.windows) == 2
        @test length(iomap.output.windows) == 2         # output mirrors input
        help_win = screen.windows[2]
        @test help_win.id === :gesture_help
        @test help_win.content isa GestureMap
        @test length(help_win.content.rows) == 9        # the array's collected set
        @test state.open

        # F1 again → the help window closes.
        op2 = read_intent(projection, iomap, WindowInput(:default, f1))
        @test !(op2 isa Operation)
        @test length(screen.windows) == 1
        @test screen.windows[1].id === :default
        @test !state.open
    end

    # Through the *real* editor pipeline (`_multi_window_projection`), rendering
    # the help window all the way to graphics — guards the live wiring (the type
    # seam + content decoration) against drift. The decorator is a `run_example`
    # flag (`gesture_help=true`), which wraps the example's own projection before
    # composing, so this test wraps it the same way.
    @testset "F1 opens a help window through the real editor pipeline" begin
        arr = mkarr()
        decorated = GestureHelpProjection(inner = make_json_projection_example(),
                                          state = GestureHelpState())
        composed = ProjecturedExample._multi_window_projection([decorated])
        screen = ScreenDocument([WindowDocument(; id = :json, content = arr)])
        iomap = print_document(composed, screen)

        op = read_intent(composed, iomap, WindowInput(:json, f1))
        @test !(op isa Operation)
        @test length(screen.windows) == 2
        @test screen.windows[2].id === :gesture_help
        rows = screen.windows[2].content.rows
        @test screen.windows[2].content isa GestureMap
        # The full content pipeline (JsonToSyntax → SyntaxToText → TextToGraphics)
        # contributes across every stage, so the collected set is richer than the
        # JSON document's 9 own gestures — proving the chain-wide collection.
        @test length(rows) > 9
        @test any(r -> occursin("Insert a new element", r.description), rows)
    end

    # The decorator is opt-in. Without it, F1 reaches the content pipeline and no
    # help window opens.
    @testset "an undecorated pipeline opens no help window" begin
        arr = mkarr()
        composed = ProjecturedExample._multi_window_projection([make_json_projection_example()])
        screen = ScreenDocument([WindowDocument(; id = :json, content = arr)])
        iomap = print_document(composed, screen)

        read_intent(composed, iomap, WindowInput(:json, f1))
        @test length(screen.windows) == 1
    end

    # A decorator's reader answers a collection with its own gestures *and* the
    # wrapped content's, merged — where routing one gesture would stop at the first.
    @testset "a collection descends into a clipboard's content" begin
        content = PrimitiveString("hello")
        slice = ClipboardSlice(content)
        p = ClipboardSliceToAnyProjection()
        iomap = print_document(p, IdentityProjection(), slice, PrinterContext())
        answer = read_intent(p, nothing, Intent(CollectIntents()), iomap).operation
        descs = [i.description for i in answer.intents]
        @test "Copy" in descs                # the clipboard's own gesture
        @test "Insert character" in descs    # descended into the PrimitiveString content
    end
end
end

export test_gesture_help
