# Tests for the gesture log: the bounded buffer, the default filter, the
# recording decorator that fills the log at the root of a pipeline, and the
# overlay decorator that draws the log over the content of a window.
#
# The test that matters most is the reactive one: the overlay prints the log
# chain one time, so the panel only follows the buffer while every stage reads
# the entries inside a cell.

function test_gesture_log()
@testset "GestureLog" begin
    none = ModifierKeys()
    left = KeyDown(:left, none; time = 0.0)
    typed = KeyPress('7'; time = 0.0)

    _force(value) = value isa Cell ? value[] : value

    # A real content pipeline, and the same pipeline down to graphics.
    inner_syntax() = RecursiveProjection(JsonToSyntax())
    inner_graphics() = ChainingProjection(RecursiveProjection(JsonToSyntax()),
                                          RecursiveProjection(SyntaxToText()),
                                          TextToGraphics(measure = FontFileMeasure()))
    mkarray() = (a = JsonArray([JsonNumber(1)]); set_selection!(a, EmptyReference()); a)

    @testset "the buffer keeps the newest entries and counts every record" begin
        log = GestureLog(; capacity = 20)
        for index in 1:25
            record_gesture!(log, left, ToggleCollapseOperation())
        end
        @test length(log.entries) == 20
        @test log.count == 25
        @test log.entries[1].index == 6            # the first five were dropped
        @test log.entries[20].index == 25
    end

    @testset "a run of typed characters folds into one entry" begin
        log = GestureLog()
        for character in "abc"
            record_gesture!(log, KeyPress(character; time = 0.0), ToggleCollapseOperation();
                            fold_typing = true)
        end
        @test length(log.entries) == 1
        @test log.entries[1].gesture == "typed \"abc\""
        record_gesture!(log, left, ToggleCollapseOperation(); fold_typing = true)
        record_gesture!(log, KeyPress('d'; time = 0.0), ToggleCollapseOperation(); fold_typing = true)
        @test [entry.gesture for entry in log.entries][[1, 3]] == ["typed \"abc\"", "typed \"d\""]
        @test log.count == 3
    end

    @testset "a reference is written from the titled document on it" begin
        log = GestureLog()
        record_gesture!(log, left, ToggleCollapseOperation())
        reference = extend_reference(EmptyReference(), FieldReferenceStep("entries"), ElementReferenceStep(1))
        @test describe_reference(reference, log) == "Gestures › .entries[1]"
        @test describe_operation(ReplaceSelectionOperation(reference), log) == "select Gestures › .entries[1]"
        @test describe_operation(ReplaceSelectionOperation(reference)) == "select .entries[1]"
    end

    @testset "an entry renders the gesture and the operation" begin
        log = GestureLog()
        record_gesture!(log, KeyDown(:c, ModifierKeys(ctrl=true); time = 0.0), ToggleCollapseOperation())
        record_gesture!(log, MousePress(:left, 412, 88; time = 0.0), DoNothingOperation())
        @test log.entries[1].gesture == "Ctrl+C"
        @test log.entries[1].operation == "toggle collapse"
        @test log.entries[1].kind === :ToggleCollapseOperation
        @test log.entries[2].gesture == "Left click (412,88)"
        # A window input records the event it wraps, not the wrapper.
        record_gesture!(log, WindowInput(:json, left), ToggleCollapseOperation())
        @test log.entries[3].gesture == "←"
    end

    @testset "the reference of an operation is rendered without its types" begin
        log = GestureLog()
        array = mkarray()
        record_gesture!(log, left, ReplaceSelectionOperation(@reference array elements[1]))
        @test log.entries[1].operation == "select .elements[1]"
    end

    @testset "a part that a projection printed is rendered short" begin
        log = GestureLog()
        array = mkarray()
        close = ConcreteReference(FieldReferenceStep("close"),
                                  ConcreteReference(RangeReferenceStep(0, 0), EmptyReference()))
        on_close = make_introduced_reference(JsonArrayToSyntaxNode(), array, close)
        record_gesture!(log, left, ReplaceSelectionOperation(on_close))
        @test log.entries[1].operation == "select ‹.close{0}›"
        # Below a path of the document, as a caret on a nested container is.
        nested = ConcreteReference(FieldReferenceStep("elements"),
                                   ConcreteReference(RangeReferenceStep(0, 1), on_close))
        record_gesture!(log, left, ReplaceSelectionOperation(nested))
        @test log.entries[2].operation == "select .elements[1]‹.close{0}›"
        # A step inside the output path of another step adds no second pair of marks.
        flat = ConcreteReference(RangeReferenceStep(12, 12), EmptyReference())
        layout = make_introduced_reference(JsonArrayToSyntaxNode(), array,
                                           make_introduced_reference(SyntaxToText(), SyntaxNode, flat))
        record_gesture!(log, left, ReplaceSelectionOperation(layout))
        @test log.entries[3].operation == "select ‹{12}›"
    end

    @testset "a line cuts an operation longer than its width" begin
        log = GestureLog()
        text = ChainingProjection(GestureLogToSyntax(operation_width = 8),
                                  RecursiveProjection(SyntaxToText()),
                                  RecursiveProjection(TextToString()))
        iomap = print_document(text, log)
        record_gesture!(log, left, ToggleCollapseOperation())      # "toggle collapse"
        @test endswith(only(split(_force(iomap.output), "\n")), "toggle …")
    end

    @testset "the default filter drops the selection operations" begin
        @test !default_gesture_log_filter(left, ReplaceSelectionOperation(EmptyReference()))
        @test !default_gesture_log_filter(left, DoNothingOperation())
        @test !default_gesture_log_filter(left, nothing)
        @test default_gesture_log_filter(left, ToggleCollapseOperation())
    end

    @testset "the recorder passes the operation through and records it" begin
        log = GestureLog()
        array = mkarray()
        inner = inner_syntax()
        recorder = GestureLogRecordingProjection(inner = inner, log = log)
        iomap = print_document(recorder, array)

        # A printable key on a whole-element selection replaces the element, which
        # is a compound operation and not a selection.
        operation = read_intent(recorder, iomap, typed)
        direct = read_intent(inner, iomap.inner_iomap, typed)
        @test operation isa CompoundOperation
        @test typeof(operation) === typeof(direct)               # nothing is consumed
        @test length(log.entries) == 1
        @test log.entries[1].gesture == "7"
        @test log.entries[1].kind === :CompoundOperation
    end

    @testset "the recorder records nothing when the inner reader declines" begin
        log = GestureLog()
        array = mkarray()
        inner = inner_syntax()
        recorder = GestureLogRecordingProjection(inner = inner, log = log,
                                                 filter = (gesture, operation) -> true)
        iomap = print_document(recorder, array)

        @test read_intent(recorder, iomap, KeyDown(:f9, none; time = 0.0)) === nothing
        @test length(log.entries) == 0
    end

    @testset "the recorder obeys its filter" begin
        log = GestureLog()
        array = mkarray()
        recorder = GestureLogRecordingProjection(inner = inner_syntax(), log = log,
                                                 filter = (gesture, operation) -> false)
        iomap = print_document(recorder, array)

        operation = read_intent(recorder, iomap, typed)
        @test operation isa CompoundOperation                     # the reader still fires
        @test length(log.entries) == 0                            # the filter dropped it
    end

    @testset "the overlay draws the panel over the content" begin
        log = GestureLog()
        array = mkarray()
        overlay = GestureLogOverlayProjection(inner = inner_graphics(), log = log)
        ctx = with_exact_size(PrinterContext(); width = Cell(1000), height = Cell(600))
        iomap = print_document(overlay, nothing, array, ctx)

        output = _force(iomap.output)
        @test output isa GraphicsCanvas
        @test length(output.elements) == 2

        content = output.elements[1]
        panel = output.elements[2]
        @test content === _force(iomap.inner_iomap.output)        # the inner output, unchanged
        @test content.x == 0 && content.y == 0                    # the coordinates do not shift
        @test panel isa GraphicsCanvas
        @test length(panel.elements) == 2                         # background + body
        @test panel.elements[1] isa GraphicsRect
        @test panel.elements[1].color.alpha < 1                   # the panel is translucent

        # The top-right anchor: the panel ends one margin from the right edge.
        @test panel.x + panel.w == 1000 - 12
        @test panel.y == 12
    end

    @testset "the panel follows the buffer without a re-print" begin
        log = GestureLog()
        array = mkarray()
        overlay = GestureLogOverlayProjection(inner = inner_graphics(), log = log)
        ctx = with_exact_size(PrinterContext(); width = Cell(1000), height = Cell(600))
        iomap = print_document(overlay, nothing, array, ctx)

        panel = _force(iomap.output).elements[2]
        empty_width = panel.w
        record_gesture!(log, left, ToggleCollapseOperation())
        one_height = panel.h
        one_width = panel.w
        record_gesture!(log, left, ToggleCollapseOperation())
        two_height = panel.h

        @test one_height > 0
        @test two_height > one_height                             # a second line made it taller
        # The empty panel says "no gesture yet", which is one line as well, so
        # the width is what shows that the first entry arrived.
        @test one_width != empty_width
        # The panel object is stable; only its cells re-derive.
        @test _force(iomap.output).elements[2] === panel
    end

    @testset "the overlay reader is a pass-through" begin
        log = GestureLog()
        array = mkarray()
        inner = inner_graphics()
        overlay = GestureLogOverlayProjection(inner = inner, log = log)
        iomap = print_document(overlay, array)

        operation = read_intent(overlay, iomap, typed)
        direct = read_intent(inner, iomap.inner_iomap, typed)
        @test typeof(operation) === typeof(direct)
        @test length(log.entries) == 0                            # the overlay records nothing
    end

    @testset "a click reaches the content under the panel" begin
        # The panel is drawn over the content, so a click on it must give the
        # same operation the pipeline gives without the panel. The anchor puts
        # the panel over the top left corner, where the content is.
        log = GestureLog()
        record_gesture!(log, left, ToggleCollapseOperation())
        plain = inner_graphics()
        overlay = GestureLogOverlayProjection(inner = inner_graphics(), log = log,
                                              anchor = :top_left)
        ctx() = with_exact_size(PrinterContext(); width = Cell(900), height = Cell(400))
        plain_iomap = print_document(plain, nothing, mkarray(), ctx())
        overlay_iomap = print_document(overlay, nothing, mkarray(), ctx())

        for (x, y) in ((4, 4), (12, 8), (30, 6))
            gesture = MousePress(:left, x, y; time = 0.0)
            expected = read_intent(plain, nothing, Intent(gesture, nothing), plain_iomap)
            actual = read_intent(overlay, nothing, Intent(gesture, nothing), overlay_iomap)
            @test string(actual.operation) == string(expected.operation)
        end
    end

    @testset "the printer renders one line per entry, newest first" begin
        log = GestureLog(; capacity = 3)
        text = ChainingProjection(GestureLogToSyntax(),
                                  RecursiveProjection(SyntaxToText()),
                                  RecursiveProjection(TextToString()))
        iomap = print_document(text, log)
        @test _force(iomap.output) == "no gesture yet"

        record_gesture!(log, KeyDown(:c, ModifierKeys(ctrl=true); time = 0.0), ToggleCollapseOperation())
        record_gesture!(log, left, DoNothingOperation())
        lines = split(_force(iomap.output), "\n")
        @test length(lines) == 2
        @test occursin("←", lines[1])                             # the newest line is first
        @test occursin("Ctrl+C", lines[2])
    end
end
end
