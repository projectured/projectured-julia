const _CB = Projectured.ConsoleBackendModule
const _ED = Projectured.EditorModule

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
    sels = Any[]
    # The editor logs every applied operation via @info; quiet it for the test.
    Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
        _ED.print!(editor)
        for _ in 1:steps
            _ED.read!(editor)
            _ED.evaluate!(editor)
            _ED.print!(editor)
            push!(sels, getfield(doc, :selection)[])
        end
    end
    return sels
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
    out = Projectured.projection_print(proj, doc).output
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
        @test _parse(0x1b, UInt8('['), UInt8('A')) == KeyDown(:up, Modifiers())
        @test _parse(0x1b, UInt8('['), UInt8('B')) == KeyDown(:down, Modifiers())
        @test _parse(0x1b, UInt8('['), UInt8('C')) == KeyDown(:right, Modifiers())
        @test _parse(0x1b, UInt8('['), UInt8('D')) == KeyDown(:left, Modifiers())
        # Home maps to the reader's "select root" chord (Ctrl+Alt+Home).
        @test _parse(0x1b, UInt8('['), UInt8('H')) == KeyDown(:home, Modifiers(ctrl=true, alt=true))
        @test _parse(0x1b, UInt8('['), UInt8('F')) == KeyDown(:end, Modifiers())
        @test _parse(0x03) isa Projectured.QuitEvent           # Ctrl-C
        @test _parse(0x00) == KeyDown(:space, Modifiers(ctrl=true))  # Ctrl-Space
        @test _parse(0x0d) == KeyDown(:return, Modifiers())
        @test _parse(0x7f) == KeyDown(:backspace, Modifiers())
        @test _parse(0x09) == KeyDown(:tab, Modifiers())
        @test _parse(UInt8('a')) == KeyPress('a')
        # An incomplete CSI (just "ESC [") yields no event and is left buffered.
        @test _parse(0x1b, UInt8('[')) === nothing
    end

    # ── read_from_devices wraps events in a :console EventEnvelope ─────────
    @testset "read_from_devices" begin
        b = ConsoleBackend(; io=IOBuffer(), input=IOBuffer(UInt8[UInt8('a')]))
        env = read_from_devices(b, Device[])
        @test env isa Projectured.EventEnvelope
        @test env.window_id === :console
        @test env.event == KeyPress('a')
        # Empty input → nothing.
        @test read_from_devices(ConsoleBackend(; input=IOBuffer(UInt8[])), Device[]) === nothing
    end

    # ── selection highlight rendering ─────────────────────────────────────
    @testset "caret rendering" begin
        # Whole-element selection → the value's text is reverse-highlighted.
        doc = make_json_document_example()
        set_selection!(doc, Projectured.@reference entries[1].value)
        @test _highlighted(doc) == "\"Alice\""
        # Text cursor at offset 2 inside "Alice" → block on the char at index 2.
        doc2 = make_json_document_example()
        set_selection!(doc2, Projectured.@reference entries[1].value.value{2})
        @test _highlighted(doc2) == "i"
    end

    # ── colored vs plain output ───────────────────────────────────────────
    @testset "ansi vs plain" begin
        doc = make_json_document_example()
        proj = make_json_console_projection_example()
        out = Projectured.projection_print(proj, doc).output
        plain = IOBuffer(); console_render(ConsoleBackend(; io=plain, ansi=false), out)
        colored = IOBuffer(); console_render(ConsoleBackend(; io=colored, ansi=true, clear=false), out)
        cs = String(take!(colored))
        @test occursin("\e[38;2;", cs)                                   # truecolor codes present
        @test replace(cs, r"\e\[[0-9;]*m" => "") == String(take!(plain)) # strip ⇒ plain
    end

    # ── frame diffing skips an unchanged repaint ──────────────────────────
    @testset "frame diff" begin
        doc = make_json_document_example()
        out = Projectured.projection_print(make_json_console_projection_example(), doc).output
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
        @test sels[1] isa EmptyReferencePath                              # Home → root ∅
        @test string(sels[2]) == ".entries[1]"                           # Down → first child
        @test string(sels[3]) == ".entries[1].key"                       # Down → descend
        @test string(sels[4]) == ".entries[1].value"                     # Right → sibling
    end

    # ── wrong pipeline output fails loud ──────────────────────────────────
    @testset "output type guard" begin
        @test_throws ErrorException write_to_devices(ConsoleBackend(), Device[], 42)
    end

end
end
