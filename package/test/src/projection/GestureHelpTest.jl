# Tests for GestureHelpProjection — the content-level decorator that opens the
# gesture-help window on F1. Proves the mechanism without the full screen
# pipeline: the help gesture collects every binding reachable from the
# decorator's own inner iomap (collect_gestures, the projection-form collector)
# and emits an OpenWindowOperation carrying that GestureMap; a second F1 closes
# it (toggle); every other gesture passes straight through to the wrapped editor.

function test_gesture_help()
@testset "GestureHelpProjection" begin
    none = Modifiers()
    f1   = KeyDown(:f1, none)

    # A real content pipeline whose collector yields reified gestures.
    inner = RecursiveProjection(JsonToSyntax())
    mkarr() = (a = JsonArray([JsonNumber(1)]); set_selection!(a, EmptyReferencePath()); a)

    @testset "F1 opens a window carrying the collected GestureMap" begin
        arr = mkarr()
        state = GestureHelpState()
        help = GestureHelpProjection(inner = inner, state = state)
        iomap = projection_print(help, arr)

        # What the window must show == what collect yields over the same iomap.
        expected = gesture_map(collect_gestures(inner, nothing, iomap.inner_iomap), arr)
        @test length(expected.rows) == 9          # the array's full reified set

        op = projection_read(help, iomap, f1)
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
        iomap = projection_print(help, arr)

        @test projection_read(help, iomap, f1) isa OpenWindowOperation
        op = projection_read(help, iomap, f1)
        @test op isa CloseWindowOperation
        @test op.id === :gesture_help
        @test !state.open
    end

    @testset "non-help gestures pass through; help is not triggered" begin
        arr = mkarr()
        state = GestureHelpState()
        help = GestureHelpProjection(inner = inner, state = state)
        iomap = projection_print(help, arr)

        op = projection_read(help, iomap, KeyDown(:comma, none))  # array insert
        @test !(op isa OpenWindowOperation)
        @test !state.open
        # The decorator returns exactly what the wrapped editor returned.
        direct = projection_read(inner, iomap.inner_iomap, KeyDown(:comma, none))
        @test typeof(op) === typeof(direct)
    end

    @testset "transparent printer: output is the inner's own output" begin
        arr = mkarr()
        help = GestureHelpProjection(inner = inner)
        io = projection_print(help, arr)
        @test io.output === io.inner_iomap.output
    end
end
end

export test_gesture_help
