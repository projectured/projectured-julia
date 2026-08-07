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
    left = KeyDown(:left, none)
    comma = KeyDown(:comma, none)

    _force(value) = value isa Cell ? value[] : value

    # A real content pipeline, and the same pipeline down to graphics.
    inner_syntax() = RecursiveProjection(JsonToSyntax())
    inner_graphics() = ChainingProjection(RecursiveProjection(JsonToSyntax()),
                                          RecursiveProjection(SyntaxToText()),
                                          TextToGraphics(measure = truetype_measure_text))
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

    @testset "an entry renders the gesture and the operation" begin
        log = GestureLog()
        record_gesture!(log, KeyDown(:c, ModifierKeys(ctrl=true)), ToggleCollapseOperation())
        record_gesture!(log, MousePress(:left, 412, 88), DoNothingOperation())
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
        recorder = GestureLogRecordingProjection(inner = inner, log = log,
                                                 filter = (gesture, operation) -> true)
        iomap = print_document(recorder, array)

        operation = read_intent(recorder, iomap, comma)          # the array insert
        direct = read_intent(inner, iomap.inner_iomap, comma)
        @test typeof(operation) === typeof(direct)               # nothing is consumed
        @test length(log.entries) == 1
        @test log.entries[1].gesture == "," || log.entries[1].gesture == "Comma"
    end

    @testset "the recorder records nothing when the inner reader declines" begin
        log = GestureLog()
        array = mkarray()
        inner = inner_syntax()
        recorder = GestureLogRecordingProjection(inner = inner, log = log,
                                                 filter = (gesture, operation) -> true)
        iomap = print_document(recorder, array)

        @test read_intent(recorder, iomap, KeyDown(:f9, none)) === nothing
        @test length(log.entries) == 0
    end

    @testset "the recorder obeys its filter" begin
        log = GestureLog()
        array = mkarray()
        recorder = GestureLogRecordingProjection(inner = inner_syntax(), log = log)
        iomap = print_document(recorder, array)

        # The insert passes the default filter; a selection does not.
        read_intent(recorder, iomap, comma)
        kept = length(log.entries)
        @test kept == 1
        read_intent(recorder, iomap, KeyDown(:home, none))        # selects the root
        @test length(log.entries) == kept
    end

    @testset "the overlay draws the panel over the content" begin
        log = GestureLog()
        array = mkarray()
        overlay = GestureLogOverlayProjection(inner = inner_graphics(), log = log)
        ctx = with_available_size(PrinterContext(); width = Cell(1000), height = Cell(600))
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
        ctx = with_available_size(PrinterContext(); width = Cell(1000), height = Cell(600))
        iomap = print_document(overlay, nothing, array, ctx)

        panel = _force(iomap.output).elements[2]
        empty_height = panel.h
        record_gesture!(log, left, ToggleCollapseOperation())
        one_height = panel.h
        record_gesture!(log, left, ToggleCollapseOperation())
        two_height = panel.h

        @test one_height > 0
        @test two_height > one_height                             # a second line made it taller
        @test one_height != empty_height
        # The panel object is stable; only its cells re-derive.
        @test _force(iomap.output).elements[2] === panel
    end

    @testset "the overlay reader is a pass-through" begin
        log = GestureLog()
        array = mkarray()
        inner = inner_graphics()
        overlay = GestureLogOverlayProjection(inner = inner, log = log)
        iomap = print_document(overlay, array)

        operation = read_intent(overlay, iomap, comma)
        direct = read_intent(inner, iomap.inner_iomap, comma)
        @test typeof(operation) === typeof(direct)
        @test length(log.entries) == 0                            # the overlay records nothing
    end

    @testset "the printer renders one line per entry, newest first" begin
        log = GestureLog(; capacity = 3)
        text = ChainingProjection(GestureLogToSyntax(),
                                  RecursiveProjection(SyntaxToText()),
                                  RecursiveProjection(TextToString()))
        iomap = print_document(text, log)
        @test _force(iomap.output) == "no gesture yet"

        record_gesture!(log, KeyDown(:c, ModifierKeys(ctrl=true)), ToggleCollapseOperation())
        record_gesture!(log, left, DoNothingOperation())
        lines = split(_force(iomap.output), "\n")
        @test length(lines) == 2
        @test occursin("←", lines[1])                             # the newest line is first
        @test occursin("Ctrl+C", lines[2])
    end
end
end
