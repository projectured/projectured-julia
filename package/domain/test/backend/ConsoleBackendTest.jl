const _CB = ConsoleBackendModule
const _ED = EditorModule

# Parse one event from a fresh byte buffer (mirrors how `read_from_devices`
# drains the input and consumes one event at a time).
_parse(bytes...) = _CB._next_event!(collect(UInt8, bytes))

# Drive the real editor read-eval-print loop over a script of input bytes,
# returning the document selection after each step.
function _drive_console(bytes::Vector{UInt8}, steps::Int)
    doc = make_json_document_example()
    proj = make_json_console_projection_example()
    backend = ConsoleBackend(; io=IOBuffer(), input=IOBuffer(bytes), ansi=true, clear=false)
    editor = Editor(backend, doc, proj, Device[Keyboard()])
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
            # entries.  strip_reference_types removes TypeReference checkpoints so
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
    editor = Editor(backend, doc, proj, Device[Keyboard()])
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
        @test _parse(0x1b, UInt8('['), UInt8('A')) == KeyDown(:up, ModifierKeys())
        @test _parse(0x1b, UInt8('['), UInt8('B')) == KeyDown(:down, ModifierKeys())
        @test _parse(0x1b, UInt8('['), UInt8('C')) == KeyDown(:right, ModifierKeys())
        @test _parse(0x1b, UInt8('['), UInt8('D')) == KeyDown(:left, ModifierKeys())
        # Home maps to the reader's "select root" chord (Ctrl+Alt+Home).
        @test _parse(0x1b, UInt8('['), UInt8('H')) == KeyDown(:home, ModifierKeys(ctrl=true, alt=true))
        @test _parse(0x1b, UInt8('['), UInt8('F')) == KeyDown(:end, ModifierKeys())
        @test _parse(0x03) isa WindowQuit           # Ctrl-C
        @test _parse(0x00) == KeyDown(:space, ModifierKeys(ctrl=true))  # Ctrl-Space
        @test _parse(0x0d) == KeyDown(:return, ModifierKeys())
        @test _parse(0x7f) == KeyDown(:backspace, ModifierKeys())
        @test _parse(0x09) == KeyDown(:tab, ModifierKeys())
        @test _parse(UInt8('a')) == KeyPress('a')
        # An incomplete CSI (just "ESC [") yields no event and is left buffered.
        @test _parse(0x1b, UInt8('[')) === nothing
    end

    # ── read_from_devices wraps events in a :console WindowInput ─────────
    @testset "read_from_devices" begin
        b = ConsoleBackend(; io=IOBuffer(), input=IOBuffer(UInt8[UInt8('a')]))
        env = read_from_devices(b, Device[])
        @test env isa WindowInput
        @test env.window_id === :console
        @test env.event == KeyPress('a')
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
        plain = IOBuffer(); console_render(ConsoleBackend(; io=plain, ansi=false), out)
        colored = IOBuffer(); console_render(ConsoleBackend(; io=colored, ansi=true, clear=false), out)
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
        console_render(backend, out)
        @test position(io) > 0                       # first frame is written
        truncate(io, 0); seekstart(io)
        console_render(backend, out)                 # identical frame
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

end
end
