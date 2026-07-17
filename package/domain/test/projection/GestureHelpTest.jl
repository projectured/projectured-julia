# Tests for GestureHelpProjection — the content-level decorator that opens the
# gesture-help window on F1. Proves the mechanism without the full screen
# pipeline: the help gesture collects every binding reachable from the
# decorator's own inner iomap (collect_gesture_bindings, the projection-form collector)
# and emits an OpenWindowOperation carrying that GestureMap; a second F1 closes
# it (toggle); every other gesture passes straight through to the wrapped editor.

function test_gesture_help()
@testset "GestureHelpProjection" begin
    none = ModifierKeys()
    f1   = KeyDown(:f1, none)

    # A real content pipeline whose collector yields reified gestures.
    inner = RecursiveProjection(JsonToSyntax())
    mkarr() = (a = JsonArray([JsonNumber(1)]); set_selection!(a, EmptyReferencePath()); a)

    @testset "F1 opens a window carrying the collected GestureMap" begin
        arr = mkarr()
        state = GestureHelpState()
        help = GestureHelpProjection(inner = inner, state = state)
        iomap = print_document(help, arr)

        # What the window must show == what collect yields over the same iomap.
        expected = gesture_map(collect_gesture_bindings(inner, nothing, iomap.inner_iomap), arr)
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

    # Through the *real* default editor pipeline (`_multi_window_projection`),
    # rendering the help window all the way to graphics — guards the live wiring
    # (the type seam + content decoration) against drift.
    @testset "F1 opens a help window through the real editor pipeline" begin
        arr = mkarr()
        composed = ProjecturedDomainExample._multi_window_projection([make_json_projection_example()])
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

    # A decorator projection's `collect_gesture_bindings` gathers its own gestures *and*
    # descends into the wrapped content, so the help window shows both. Without the
    # combinator method, only the clipboard's own commands would surface.
    @testset "collect_gesture_bindings descends into a clipboard's content" begin
        content = PrimitiveString("hello")
        slice = ClipboardSlice(content)
        p = ClipboardSliceToAnyProjection()
        iomap = print_document(p, IdentityProjection(), slice, PrinterContext())
        descs = [b.description for b in collect_gesture_bindings(p, nothing, iomap)]
        @test "Copy" in descs                # the clipboard's own gesture
        @test "Insert character" in descs    # descended into the PrimitiveString content
    end
end
end

export test_gesture_help
