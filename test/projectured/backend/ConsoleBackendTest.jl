const _CB = ConsoleBackendModule
const _ED = EditorModule

# Parse one event from a fresh byte buffer (mirrors how `read_from_devices`
# drains the input and consumes one event at a time).
_parse(bytes...) = _CB._next_event!(collect(UInt8, bytes); time = 0.0)

# Drive the real editor read-eval-print loop over a script of input bytes,
# returning the document selection after each step.
function _drive_console(bytes::Vector{UInt8}, steps::Int)
    doc = make_json_document_example()
    proj = make_json_console_projection_example()
    backend = ConsoleBackend(; io=IOBuffer(), input=IOBuffer(bytes), ansi=true, clear=false)
    editor = Editor(doc, proj; backend = backend, devices = Device[Keyboard()])
    sels = String[]
    # The editor logs every applied operation via @info; quiet it for the test.
    Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
        _ED.print!(editor)
        for _ in 1:steps
            _ED.read!(editor)
            _ED.evaluate!(editor)
            _ED.print!(editor)
            # Snapshot the selection as a stripped string so later replace_selection!
            # mutations (which reuse cells in-place) do not change already-recorded
            # entries.  strip_reference_types removes TypeReferenceStep checkpoints so
            # the string matches the plain navigation skeleton the tests assert on.
            push!(sels, string(strip_reference_types(getfield(doc, :selection)[])))
        end
    end
    return sels
end

# Like `_drive_console` but also returns the document, so tests can inspect the
# edited content (character insert / delete) in addition to the selection path.
function _drive_console_doc(bytes::Vector{UInt8}, steps::Int)
    doc = make_json_document_example()
    proj = make_json_console_projection_example()
    backend = ConsoleBackend(; io=IOBuffer(), input=IOBuffer(bytes), ansi=true, clear=false)
    editor = Editor(doc, proj; backend = backend, devices = Device[Keyboard()])
    sels = String[]
    Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
        _ED.print!(editor)
        for _ in 1:steps
            _ED.read!(editor)
            _ED.evaluate!(editor)
            _ED.print!(editor)
            # Snapshot stripped string (see _drive_console comment above).
            push!(sels, string(strip_reference_types(getfield(doc, :selection)[])))
        end
    end
    return doc, sels
end

# Render `doc` (with whatever selection it carries) and return the concatenated
# text inside selection-highlight regions, SGR codes stripped. The selection is
# now baked in as inverse video by `SelectionInverting`: the highlighted slice
# carries an explicit background color (`\e[48;2;…m`), which the plain JSON spans
# (font color only, no fill) do not, so a background-coded run marks the
# selection.
function _highlighted(doc)
    proj = make_json_console_projection_example()
    io = IOBuffer()
    backend = ConsoleBackend(; io=io, ansi=true, clear=false)
    out = print_document(proj, doc).output
    write_to_devices(backend, Device[], out)
    s = String(take!(io))
    rev = ""
    # Each styled slice is `<sgr codes>text\e[0m`; keep the ones whose codes
    # include a background color.
    for m in eachmatch(r"((?:\e\[[0-9;]*m)+)(.*?)\e\[0m"s, s)
        occursin(r"\e\[48;2;", m.captures[1]) || continue
        rev *= replace(m.captures[2], r"\e\[[0-9;]*m" => "")
    end
    return rev
end

function test_console_backend()
@testset "ConsoleBackend" begin

    # ── byte → event translation ─────────────────────────────────────────
    @testset "input parsing" begin
        @test _parse(0x1b, UInt8('['), UInt8('A')) == KeyDown(:up, ModifierKeys(); time = 0.0)
        @test _parse(0x1b, UInt8('['), UInt8('B')) == KeyDown(:down, ModifierKeys(); time = 0.0)
        @test _parse(0x1b, UInt8('['), UInt8('C')) == KeyDown(:right, ModifierKeys(); time = 0.0)
        @test _parse(0x1b, UInt8('['), UInt8('D')) == KeyDown(:left, ModifierKeys(); time = 0.0)
        # Home maps to the reader's "select root" chord (Ctrl+Alt+Home).
        @test _parse(0x1b, UInt8('['), UInt8('H')) == KeyDown(:home, ModifierKeys(ctrl=true, alt=true); time = 0.0)
        @test _parse(0x1b, UInt8('['), UInt8('F')) == KeyDown(:end, ModifierKeys(); time = 0.0)
        @test _parse(0x03) isa WindowQuit           # Ctrl-C
        @test _parse(0x00) == KeyDown(:space, ModifierKeys(ctrl=true); time = 0.0)  # Ctrl-Space
        @test _parse(0x0d) == KeyDown(:return, ModifierKeys(); time = 0.0)
        @test _parse(0x7f) == KeyDown(:backspace, ModifierKeys(); time = 0.0)
        @test _parse(0x09) == KeyDown(:tab, ModifierKeys(); time = 0.0)
        # A Ctrl byte that no row above reads is its letter with Ctrl: 0x1A is Ctrl+Z.
        @test _parse(0x1a) == KeyDown(:z, ModifierKeys(ctrl=true); time = 0.0)
        @test _parse(0x01) == KeyDown(:a, ModifierKeys(ctrl=true); time = 0.0)
        @test _parse(UInt8('a')) == KeyPress('a'; time = 0.0)
        # An incomplete CSI (just "ESC [") yields no event and is left buffered.
        @test _parse(0x1b, UInt8('[')) === nothing
    end

    # ── the letters ──────────────────────────────────────────────────────
    @testset "each letter has the name of its lower-case letter" begin
        # A letter byte is a KeyPress of the letter. A Ctrl byte that no other row
        # reads is a KeyDown of its letter with Ctrl: 0x01 is Ctrl+A. The console
        # reads no mouse, so the table holds no button and no wheel.
        read_already = (0x03, 0x08, 0x09, 0x0a, 0x0d)
        for (index, letter) in enumerate('a':'z')
            @test _parse(UInt8(letter)) == KeyPress(letter; time = 0.0)
            byte = UInt8(index)
            byte in read_already && continue
            @test _parse(byte) ==
                  KeyDown(Symbol(letter), ModifierKeys(ctrl = true); time = 0.0)
        end
    end

    # ── Escape, Alt chords and the modifiers of a CSI sequence ───────────
    @testset "escape and modifiers" begin
        ESC = 0x1b
        csi(text) = _parse(ESC, collect(UInt8, "[" * text)...)
        # A lone ESC waits for the next byte. When no byte follows, it is Escape.
        @test _parse(ESC) === nothing
        @test _CB._next_event!(UInt8[ESC]; settled = true, time = 0.0) == KeyDown(:escape, ModifierKeys(); time = 0.0)
        # A second ESC starts a new key, so the first ESC is Escape.
        buffer = UInt8[ESC, ESC]
        @test _CB._next_event!(buffer; time = 0.0) == KeyDown(:escape, ModifierKeys(); time = 0.0)
        @test buffer == UInt8[ESC]
        # ESC and another key is that key with Alt.
        @test _parse(ESC, UInt8('x')) == KeyPress('x', ModifierKeys(alt = true); time = 0.0)
        @test _parse(ESC, 0x7f) == KeyDown(:backspace, ModifierKeys(alt = true); time = 0.0)
        @test _parse(ESC, codeunits("é")...) == KeyPress('é', ModifierKeys(alt = true); time = 0.0)
        # ESC [ with no more bytes is Alt and `[`.
        @test _CB._next_event!(UInt8[ESC, UInt8('[')]; settled = true, time = 0.0) ==
              KeyPress('[', ModifierKeys(alt = true); time = 0.0)
        # The modifier parameter m of xterm is 1 + the sum of 1 Shift, 2 Alt, 4 Ctrl.
        @test csi("1;5D") == KeyDown(:left, ModifierKeys(ctrl = true); time = 0.0)
        @test csi("1;2A") == KeyDown(:up, ModifierKeys(shift = true); time = 0.0)
        @test csi("1;3C") == KeyDown(:right, ModifierKeys(alt = true); time = 0.0)
        @test csi("1;6B") == KeyDown(:down, ModifierKeys(ctrl = true, shift = true); time = 0.0)
        @test csi("1;7D") == KeyDown(:left, ModifierKeys(ctrl = true, alt = true); time = 0.0)
        @test csi("1;5H") == KeyDown(:home, ModifierKeys(ctrl = true); time = 0.0)
        @test csi("1;2F") == KeyDown(:end, ModifierKeys(shift = true); time = 0.0)
        @test csi("3~") == KeyDown(:delete, ModifierKeys(); time = 0.0)
        @test csi("3;5~") == KeyDown(:delete, ModifierKeys(ctrl = true); time = 0.0)
        @test csi("5;2~") == KeyDown(:page_up, ModifierKeys(shift = true); time = 0.0)
        @test csi("6~") == KeyDown(:page_down, ModifierKeys(); time = 0.0)
        @test csi("2~") == KeyDown(:insert, ModifierKeys(); time = 0.0)
        @test csi("15;5~") == KeyDown(:f5, ModifierKeys(ctrl = true); time = 0.0)
        @test csi("1;2P") == KeyDown(:f1, ModifierKeys(shift = true); time = 0.0)
        @test csi("Z") == KeyDown(:tab, ModifierKeys(shift = true); time = 0.0)
        @test _parse(ESC, UInt8('O'), UInt8('Q')) == KeyDown(:f2, ModifierKeys(); time = 0.0)
        # The parser takes the whole sequence, so no stray character follows it.
        buffer = collect(UInt8, "\e[1;5Dx")
        @test _CB._next_event!(buffer; time = 0.0) == KeyDown(:left, ModifierKeys(ctrl = true); time = 0.0)
        @test buffer == UInt8['x']
        # An unknown sequence is dropped whole.
        buffer = collect(UInt8, "\e[200~y")
        @test _CB._next_event!(buffer; time = 0.0) === nothing
        @test buffer == UInt8['y']
        # A sequence whose final byte has not arrived waits for it.
        @test csi("1;5") === nothing
        # Ctrl+C quits.
        @test _parse(0x03) isa WindowQuit
    end

    # ── read_from_devices settles a lone ESC when no byte follows ─────────
    @testset "lone escape" begin
        b = ConsoleBackend(; io=IOBuffer(), input=IOBuffer(UInt8[0x1b]))
        window_input = read_from_devices(b, Device[])
        @test window_input isa WindowInput
        # The terminal gives no time, so an event has the time of the read.
        escape = window_input.event
        @test escape == KeyDown(:escape, ModifierKeys(); time = escape.time)
        @test isempty(b.inbuf)
        b = ConsoleBackend(; io=IOBuffer(), input=IOBuffer(UInt8[0x1b, UInt8('x')]))
        alt_x = read_from_devices(b, Device[]).event
        @test alt_x == KeyPress('x', ModifierKeys(alt = true); time = alt_x.time)
        @test read_from_devices(b, Device[]) === nothing
        # Bytes that make no event are skipped, and the next key is read.
        b = ConsoleBackend(; io=IOBuffer(), input=IOBuffer(collect(UInt8, "\e[200~q")))
        q = read_from_devices(b, Device[]).event
        @test q == KeyPress('q'; time = q.time)
    end

    # ── the editor quits on Escape, and an Alt chord does not quit ────────
    @testset "escape quits the editor" begin
        function read_operation(bytes)
            backend = ConsoleBackend(; io=IOBuffer(), input=IOBuffer(bytes), ansi=true, clear=false)
            editor = Editor(make_json_document_example(),
                            make_json_console_projection_example();
                            backend = backend, devices = Device[Keyboard()])
            Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
                _ED.print!(editor)
                _ED.read!(editor)
            end
            return editor.operation
        end
        @test read_operation(UInt8[0x1b]) isa QuitEditorOperation
        @test read_operation(UInt8[0x03]) isa QuitEditorOperation
        @test !(read_operation(UInt8[0x1b, UInt8('x')]) isa QuitEditorOperation)
        @test !(read_operation(collect(UInt8, "\e[1;5D")) isa QuitEditorOperation)
    end

    # ── read_from_devices wraps events in a :console WindowInput ─────────
    @testset "read_from_devices" begin
        b = ConsoleBackend(; io=IOBuffer(), input=IOBuffer(UInt8[UInt8('a')]))
        before = time()
        window_input = read_from_devices(b, Device[])
        after = time()
        @test window_input isa WindowInput
        @test window_input.window_id === :console
        typed = window_input.event
        @test typed == KeyPress('a'; time = typed.time)
        @test before <= typed.time <= after
        # Empty input → nothing.
        @test read_from_devices(ConsoleBackend(; input=IOBuffer(UInt8[])), Device[]) === nothing
    end

    # ── selection highlight rendering ─────────────────────────────────────
    @testset "caret rendering" begin
        # Whole-element selection → the value's text is reverse-highlighted.
        doc = make_json_document_example()
        set_selection!(doc, @reference(doc, entries[1].value))
        @test _highlighted(doc) == "\"Alice\""
        # Text cursor at offset 2 inside "Alice" → block on the char at index 2.
        doc2 = make_json_document_example()
        set_selection!(doc2, @reference(doc2, entries[1].value.value{2}))
        @test _highlighted(doc2) == "i"
    end

    # ── colored vs plain output ───────────────────────────────────────────
    @testset "ansi vs plain" begin
        doc = make_json_document_example()
        proj = make_json_console_projection_example()
        out = print_document(proj, doc).output
        plain = IOBuffer(); render_console(ConsoleBackend(; io=plain, ansi=false), out)
        colored = IOBuffer(); render_console(ConsoleBackend(; io=colored, ansi=true, clear=false), out)
        cs = String(take!(colored))
        @test occursin("\e[38;2;", cs)                                   # truecolor codes present
        @test replace(cs, r"\e\[[0-9;]*m" => "") == String(take!(plain)) # strip ⇒ plain
    end

    # ── frame diffing skips an unchanged repaint ──────────────────────────
    @testset "frame diff" begin
        doc = make_json_document_example()
        out = print_document(make_json_console_projection_example(), doc).output
        io = IOBuffer()
        backend = ConsoleBackend(; io=io, ansi=true, clear=true)
        render_console(backend, out)
        @test position(io) > 0                       # first frame is written
        truncate(io, 0); seekstart(io)
        render_console(backend, out)                 # identical frame
        @test position(io) == 0                      # …is skipped (no flicker)
    end

    # ── structural navigation through the editor loop ─────────────────────
    @testset "navigation" begin
        # Home (ESC[H), Down (ESC[B), Down, Right (ESC[C).
        bytes = UInt8[0x1b,0x5b,0x48, 0x1b,0x5b,0x42, 0x1b,0x5b,0x42, 0x1b,0x5b,0x43]
        sels = _drive_console(bytes, 4)
        @test sels[1] == "∅"                                              # Home → root ∅
        @test sels[2] == ".entries[1]"                                   # Down → first child
        @test sels[3] == ".entries[1].key"                               # Down → descend
        @test sels[4] == ".entries[1].value"                             # Right → sibling
    end

    # ── character-level text editing through the console pipeline ──────────
    # This is the payoff of moving the geometry-free Text-domain gesture mapping
    # onto the document (`read_gesture(::TextBlock, …)`): the console pipeline,
    # which omits `TextToGraphics`, now gets character cursor movement and
    # insert/delete via `SyntaxToText`'s fallback to `read_gesture(iomap.output,
    # gesture)`. None of these gestures need pixel geometry.
    @testset "character editing" begin
        ESC = 0x1b; LB = 0x5b
        HOME  = UInt8[ESC, LB, UInt8('H')]   # Ctrl+Alt+Home → root
        DOWN  = UInt8[ESC, LB, UInt8('B')]
        RIGHT = UInt8[ESC, LB, UInt8('C')]
        LEFT  = UInt8[ESC, LB, UInt8('D')]
        CTRL_SPACE = UInt8[0x00]
        BACKSPACE  = UInt8[0x7f]

        # Navigate Home → Down → Down → Right to land on entry 1's value
        # (the JSON string "Alice"), then Ctrl+Space to enter text-cursor mode.
        nav = vcat(HOME, DOWN, DOWN, RIGHT, CTRL_SPACE)

        # Cross-span / character cursor movement (Right then Left) drives the
        # text-domain `read_gesture` left/right arms through the fallback.
        _, sels = _drive_console_doc(vcat(nav, RIGHT, LEFT), 7)
        @test sels[4] == ".entries[1].value"              # on the value
        @test sels[5] == ".entries[1].value.value{0}"     # Ctrl+Space → text cursor
        @test sels[6] == ".entries[1].value.value{1}"     # Right → +1
        @test sels[7] == ".entries[1].value.value{0}"     # Left  → back

        # Character insert: type 'X' at the text cursor (offset 0) inside "Alice".
        doc, sels = _drive_console_doc(vcat(nav, UInt8[UInt8('X')]), 6)
        @test doc.entries[1].value.value == "XAlice"             # inserted at the cursor
        @test sels[6] == ".entries[1].value.value{1}"             # cursor advanced past insert

        # Backspace: move the cursor right by one, then delete the char before it —
        # the value's first char. Its flat delete range starts on the open-quote
        # boundary; `_lower_text_range` snaps the range's start into the value span it
        # enters (rather than the quote it leaves), so the range stays within the value
        # and the first character deletes cleanly.
        doc, sels = _drive_console_doc(vcat(nav, RIGHT, BACKSPACE), 7)
        @test doc.entries[1].value.value == "lice"               # "Alice" → delete 'A'
        @test sels[7] == ".entries[1].value.value{0}"
    end

    # ── wrong pipeline output fails loud ──────────────────────────────────
    @testset "output type guard" begin
        @test_throws ErrorException write_to_devices(ConsoleBackend(), Device[], 42)
    end

    # ── the wait and the wake ─────────────────────────────────────────────
    # Timing assertions are one-sided and generous: a bound says "far less
    # than the full timeout", never "exactly this fast".
    @testset "wait and wake" begin
        # An IOBuffer input has no watcher: the wait is one poll slice.
        buffered = ConsoleBackend(; io=IOBuffer(), input=IOBuffer())
        elapsed = @elapsed wait_for_input(buffered, Device[], 30.0)
        @test elapsed < 5.0
        @test wake_backend!(buffered) === nothing

        # Buffered bytes end the wait before it starts.
        fed = ConsoleBackend(; io=IOBuffer(), input=IOBuffer(UInt8['x']))
        @test wait_for_input(fed, Device[], 30.0) === nothing

        # With a watcher present the wait blocks on the gate. The watcher
        # here never fires (a dummy task): only the gate ends the wait.
        gated = ConsoleBackend(; io=IOBuffer(), input=IOBuffer())
        gated.watcher = @async nothing

        # A wake stored before the wait is not lost.
        wake_backend!(gated)
        elapsed = @elapsed wait_for_input(gated, Device[], 30.0)
        @test elapsed < 5.0

        # A wake from another task ends a long wait.
        waker = @async (sleep(0.05); wake_backend!(gated))
        elapsed = @elapsed wait_for_input(gated, Device[], 30.0)
        wait(waker)
        @test elapsed < 5.0

        # The timeout ends the wait when nothing else does.
        elapsed = @elapsed wait_for_input(gated, Device[], 0.05)
        @test elapsed >= 0.04
        @test elapsed < 5.0
    end

end
end
