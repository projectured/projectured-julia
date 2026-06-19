"""
    ConsoleBackendModule

Console backend. Renders a **Text-domain** document (`TextText` and its spans)
straight to a terminal (stdout), preserving the spans' colors via ANSI SGR
codes, and (interactively) translates terminal keystrokes into the
backend-agnostic events the projection readers expect. Unlike the SDL backend
it consumes the Text domain directly — the pipeline stops at `SyntaxToText` and
does **not** run `TextToGraphics`, so `write_to_devices` receives a `TextText`,
not a `ScreenDocument`.

## Interactivity (Phase 2) and its limits

Caret/text-level editing in this codebase lives in `TextToGraphics`
(`KeyPress` → `StringReplaceRangeOperation`, backspace/delete, character
left/right/up/down, click-to-position) because it needs the rendered glyph
geometry. The console pipeline deliberately omits `TextToGraphics`, so those
character-level operations are **not** available here. What survives — and what
this backend drives — is:

  - **Structural tree navigation** (handled by `SyntaxToText`): arrows move
    node-to-node once a whole element is selected; `Home` selects the root.
  - **`Ctrl+Space`** toggles structural ⇄ text-cursor selection.
  - **`Ctrl+C`** quits.

The selection is shown by reverse-video highlighting the corresponding span(s).
"""
module ConsoleBackendModule

import ..BackendModule: Backend, init!, quit!, measure_text
import ..DeviceModule: Device, read_from_devices, write_to_devices
import ..TextModule: TextDocument, TextText, TextString, TextNewline, TextSpacing, TextGraphics
import ..ColorModule: StyleColor, color_default, color_equal
import ..FontModule: StyleFont
import ..ModifiersModule: Modifiers
import ..KeyboardModule: KeyDown, KeyPress
import ..ScreenModule: QuitEvent
import ..ScreenDocumentModule: EventEnvelope
import ..ReferenceModule: ConcreteReferencePath, EmptyReferencePath, RangeReference, FieldReference, TextRectangularReference, ReferencePath

export ConsoleBackend, console_render

"""
    ConsoleBackend(; io=stdout, input=stdin, ansi=true, clear=true)

A backend that renders the Text domain to a terminal and (optionally) reads
keystrokes back from it.

  - `io`    — where to write output (default `stdout`).
  - `input` — where to read keystrokes from (default `stdin`). Tests pass an
              `IOBuffer` of bytes here to drive the backend headlessly.
  - `ansi`  — emit ANSI SGR color codes so the spans' colors are preserved
              (default `true`). Set `false` to write plain, uncolored text
              (e.g. when piping to a non-TTY/plain-text sink).
  - `clear` — clear the screen and home the cursor before each frame so the
              document repaints in place rather than scrolling. Only takes
              effect when `ansi` is also on; ignored otherwise.

`inbuf` holds bytes read from `input` but not yet consumed into an event (e.g.
a partial escape sequence). `raw_active` records whether `init!` put the
terminal into raw mode so `quit!` can restore it. `last_frame` caches the bytes
last written so the read-eval-print loop can skip a repaint when nothing
changed — without it the editor's per-tick `print!` would clear and redraw the
screen continuously, flickering the terminal.
"""
mutable struct ConsoleBackend <: Backend
    io::IO
    input::IO
    ansi::Bool
    clear::Bool
    inbuf::Vector{UInt8}
    raw_active::Bool
    last_frame::Union{String,Nothing}
end

ConsoleBackend(; io::IO=stdout, input::IO=stdin, ansi::Bool=true, clear::Bool=true) =
    ConsoleBackend(io, input, ansi, clear, UInt8[], false, nothing)

# ── Backend interface ────────────────────────────────────────────────────

# Put a real terminal into raw mode (no line buffering, no echo) so individual
# keystrokes — including arrows and Ctrl chords — reach `read_from_devices`
# immediately, and start libuv reading on the TTY so `bytesavailable` actually
# reflects incoming bytes (without `start_reading` the internal buffer is never
# filled and the poll always sees zero). No-op (and harmless) when `input` is
# not a TTY, e.g. an `IOBuffer` in tests.
function init!(backend::ConsoleBackend)
    _set_raw!(backend, true)
    io = backend.input
    if io isa Base.TTY
        try
            Base.start_reading(io)
        catch
            # Polling still degrades gracefully; some streams auto-start on read.
        end
    end
    return nothing
end

function quit!(backend::ConsoleBackend)
    io = backend.input
    if io isa Base.TTY
        try
            Base.stop_reading(io)
        catch
        end
    end
    _set_raw!(backend, false)
    return nothing
end

# Toggle raw mode via libuv's tty handle (the same call `REPL.Terminals.raw!`
# makes), guarded so a non-TTY input or an unsupported platform degrades to a
# no-op rather than erroring.
function _set_raw!(backend::ConsoleBackend, on::Bool)
    io = backend.input
    io isa Base.TTY || return
    on == backend.raw_active && return
    try
        ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Cint), io.handle, on ? 1 : 0)
        backend.raw_active = on
    catch
        # Leave raw_active as-is; rendering still works without raw input.
    end
    return
end

"""
    measure_text(::ConsoleBackend, text, font) -> (Int, Int)

The console pipeline never measures text (there is no `TextToGraphics` to lay
out), but the `Backend` interface requires the method. Return a character-cell
estimate: one cell per character, one row tall.
"""
measure_text(::ConsoleBackend, text::AbstractString, font) = (length(text), 1)

# ── ANSI styling ─────────────────────────────────────────────────────────

const _ANSI_RESET = "\e[0m"
const _ANSI_CLEAR_HOME = "\e[2J\e[H"
const _ANSI_REVERSE = "\e[7m"

_component(x::Float64)::Int = clamp(round(Int, x * 255), 0, 255)

_sgr_foreground(c::StyleColor) =
    string("\e[38;2;", _component(c.red), ';', _component(c.green), ';', _component(c.blue), 'm')

_sgr_background(c::StyleColor) =
    string("\e[48;2;", _component(c.red), ';', _component(c.green), ';', _component(c.blue), 'm')

# A foreground color is "meaningful" when it is a real color other than the
# default (black). Default-black is only used for the empty boundary-marker
# spans (zero-length content), and emitting it would paint black-on-dark on a
# typical terminal — so map it to the terminal's own foreground (no code).
_meaningful_foreground(c) = c isa StyleColor && !color_equal(c, color_default)

# ── Selection → flat highlight range ──────────────────────────────────────

# The flat length a span contributes to the rendered character stream, matching
# how the selection's offsets are counted: TextString → its content length,
# TextNewline / TextSpacing → 1, anything else → 0.
_flat_length(span::TextString) = length(span.content::AbstractString)
_flat_length(::TextNewline) = 1
_flat_length(::TextSpacing) = 1
_flat_length(::TextDocument) = 0

# Resolve the output `TextText`'s selection to a flat half-open char range
# `(start, stop)` over the rendered stream, plus an `is_cursor` flag (a
# zero-width caret). Returns `nothing` when there is no renderable selection.
#
# Two shapes occur, both with 0-based offsets:
#   • whole-element: top-level `TextRectangularReference(a, b)`, an already-flat
#     character range over the concatenated text;
#   • text cursor: `.elements[i].content{a:b}` — add the i-th span's base offset.
function _selection_flat(text::TextText)
    sel = text.selection
    sel isa ConcreteReferencePath || return nothing
    h = sel.head
    if h isa TextRectangularReference && sel.tail isa EmptyReferencePath
        return (h.start, h.stop, h.start == h.stop)
    end
    return _text_cursor_flat(text, sel)
end

function _text_cursor_flat(text::TextText, sel::ConcreteReferencePath)
    (sel.head isa FieldReference && sel.head.name == "elements") || return nothing
    t1 = sel.tail
    t1 isa ConcreteReferencePath && t1.head isa RangeReference || return nothing
    span_idx = t1.head.start + 1   # 1-based span index
    t2 = t1.tail
    t2 isa ConcreteReferencePath && t2.head isa FieldReference && t2.head.name == "content" || return nothing
    t3 = t2.tail
    t3 isa ConcreteReferencePath && t3.head isa RangeReference || return nothing
    a, b = t3.head.start, t3.head.stop
    elements = text.elements
    (1 <= span_idx <= length(elements)) || return nothing
    base = 0
    for i in 1:(span_idx - 1)
        base += _flat_length(elements[i])
    end
    return (base + a, base + b, a == b)
end

# ── Rendering ────────────────────────────────────────────────────────────

# Emit a slice of text with the span's colors and, when `reverse` is set, the
# reverse-video attribute (used for the selection highlight). A fresh reset
# closes the slice so attributes don't bleed into the next one.
function _emit_slice!(buf::IO, backend::ConsoleBackend, s::AbstractString,
                      fg, bg, reverse::Bool)
    isempty(s) && return
    if backend.ansi
        styled = false
        if reverse
            print(buf, _ANSI_REVERSE); styled = true
        end
        if _meaningful_foreground(fg)
            print(buf, _sgr_foreground(fg::StyleColor)); styled = true
        end
        if bg isa StyleColor
            print(buf, _sgr_background(bg)); styled = true
        end
        print(buf, s)
        styled && print(buf, _ANSI_RESET)
    else
        print(buf, s)
    end
    return
end

# Render one span starting at flat offset `base`, reverse-highlighting the part
# that overlaps the half-open flat range `hl` (or nothing). Returns the flat
# offset after this span.
function _render_span!(buf::IO, backend::ConsoleBackend, span::TextString,
                       base::Int, hl)
    content = span.content::AbstractString
    L = length(content)
    if isempty(content)
        return base
    end
    fg = span.font_color
    bg = span.fill_color
    if hl === nothing || !backend.ansi
        _emit_slice!(buf, backend, content, fg, bg, false)
        return base + L
    end
    hs, he = hl
    # Overlap of [hs, he) with this span's [base, base+L), in span-local chars.
    lo = clamp(hs - base, 0, L)
    hi = clamp(he - base, 0, L)
    chars = collect(content)
    _emit_slice!(buf, backend, String(chars[1:lo]), fg, bg, false)
    _emit_slice!(buf, backend, String(chars[lo+1:hi]), fg, bg, true)
    _emit_slice!(buf, backend, String(chars[hi+1:end]), fg, bg, false)
    return base + L
end

function _render_span!(buf::IO, ::ConsoleBackend, ::TextNewline, base::Int, hl)
    print(buf, '\n')
    return base + 1
end

function _render_span!(buf::IO, ::ConsoleBackend, ::TextSpacing, base::Int, hl)
    # Span size is in pixels; there is no exact character-cell equivalent.
    # Approximate horizontal spacing with a single space; ignore non-pixel units.
    print(buf, ' ')
    return base + 1
end

# Embedded graphics have no text representation — render nothing.
_render_span!(::IO, ::ConsoleBackend, ::TextGraphics, base::Int, hl) = base
# Fallback for any other span type: ignore it rather than crash.
_render_span!(::IO, ::ConsoleBackend, ::TextDocument, base::Int, hl) = base

"""
    console_render(backend::ConsoleBackend, text::TextText)

Flatten `text`'s spans into a (optionally colored) character stream — with the
current selection reverse-video highlighted — and write it to `backend.io` in a
single flush.
"""
function console_render(backend::ConsoleBackend, text::TextText)
    buf = IOBuffer()
    backend.ansi && backend.clear && print(buf, _ANSI_CLEAR_HOME)
    sel = _selection_flat(text)
    # A zero-width cursor is widened to a one-char block so it is visible.
    hl = sel === nothing ? nothing :
         sel[3] ? (sel[1], sel[1] + 1) : (sel[1], sel[2])
    base = 0
    for span in text.elements
        base = _render_span!(buf, backend, span, base, hl)
    end
    frame = String(take!(buf))
    # Skip the write when the frame is identical to the last one. The editor's
    # loop calls print! every tick; without this the screen would clear+redraw
    # continuously and flicker.
    frame == backend.last_frame && return nothing
    backend.last_frame = frame
    print(backend.io, frame)
    flush(backend.io)
    return nothing
end

# ── Device I/O ───────────────────────────────────────────────────────────

"""
    write_to_devices(::ConsoleBackend, devices, text::TextText)

Render the Text-domain output of the projection pipeline to the terminal.
"""
write_to_devices(backend::ConsoleBackend, devices, text::TextText) =
    console_render(backend, text)

# Fail loud on a miswired pipeline (e.g. one that still ends in `TextToGraphics`
# and so produces a graphics/screen document instead of a `TextText`).
function write_to_devices(::ConsoleBackend, devices, output)
    error("write_to_devices(::ConsoleBackend, …): pipeline output is " *
          "$(typeof(output)), expected a TextText. The console backend renders " *
          "the Text domain directly — drop the TextToGraphics step from the pipeline.")
end

"""
    read_from_devices(::ConsoleBackend, devices) -> EventEnvelope or nothing

Poll `backend.input` (non-blocking) and translate the next keystroke into a
backend-agnostic event wrapped in an `EventEnvelope`. The window id is the
sentinel `:console` (there is no `WindowDocument`). Returns `nothing` when no
complete event is buffered.
"""
function read_from_devices(backend::ConsoleBackend, devices)
    _drain_input!(backend)
    event = _next_event!(backend.inbuf)
    event === nothing && return nothing
    return EventEnvelope(:console, event)
end

# Append all currently-available bytes from `input` to the pending buffer
# without blocking. Works uniformly for an `IOBuffer` (tests) and a TTY.
function _drain_input!(backend::ConsoleBackend)
    io = backend.input
    while bytesavailable(io) > 0
        append!(backend.inbuf, read(io, bytesavailable(io)))
    end
    return
end

# Parse and consume one event from the front of `buf`, or return `nothing`
# (leaving the bytes in place) when the buffer holds only an incomplete escape
# sequence. Pure aside from mutating `buf`, so it is unit-testable.
function _next_event!(buf::Vector{UInt8})
    isempty(buf) && return nothing
    b0 = buf[1]

    if b0 == 0x1b  # ESC — possibly a CSI sequence (arrows, Home/End, Delete)
        if length(buf) >= 2 && buf[2] == UInt8('[')
            length(buf) < 3 && return nothing  # incomplete CSI; wait for more
            final = buf[3]
            if final == UInt8('A'); deleteat!(buf, 1:3); return KeyDown(:up, Modifiers())
            elseif final == UInt8('B'); deleteat!(buf, 1:3); return KeyDown(:down, Modifiers())
            elseif final == UInt8('C'); deleteat!(buf, 1:3); return KeyDown(:right, Modifiers())
            elseif final == UInt8('D'); deleteat!(buf, 1:3); return KeyDown(:left, Modifiers())
            elseif final == UInt8('H'); deleteat!(buf, 1:3); return _home_event()
            elseif final == UInt8('F'); deleteat!(buf, 1:3); return KeyDown(:end, Modifiers())
            elseif final == UInt8('3')  # ESC [ 3 ~  → Delete
                length(buf) < 4 && return nothing
                deleteat!(buf, 1:min(4, length(buf)))
                return KeyDown(:delete, Modifiers())
            elseif final == UInt8('1')  # ESC [ 1 ~  → Home (some terminals)
                length(buf) < 4 && return nothing
                deleteat!(buf, 1:min(4, length(buf)))
                return _home_event()
            else
                deleteat!(buf, 1:3); return nothing  # unknown CSI: ignore
            end
        elseif length(buf) == 1
            return nothing  # lone ESC so far; wait (Ctrl-C is the quit key)
        else
            deleteat!(buf, 1); return QuitEvent()  # ESC + non-'[' → quit
        end
    end

    deleteat!(buf, 1)
    if b0 == 0x03;  return QuitEvent()                                  # Ctrl-C
    elseif b0 == 0x00; return KeyDown(:space, Modifiers(ctrl=true))     # Ctrl-Space
    elseif b0 == 0x0d || b0 == 0x0a; return KeyDown(:return, Modifiers())
    elseif b0 == 0x7f || b0 == 0x08; return KeyDown(:backspace, Modifiers())
    elseif b0 == 0x09; return KeyDown(:tab, Modifiers())
    elseif 0x20 <= b0 < 0x7f; return KeyPress(Char(b0))                 # printable ASCII
    elseif b0 >= 0x80                                                   # UTF-8 lead byte
        nbytes = b0 >= 0xf0 ? 4 : b0 >= 0xe0 ? 3 : 2
        bytes = UInt8[b0]
        while length(bytes) < nbytes && !isempty(buf)
            push!(bytes, popfirst!(buf))
        end
        s = String(bytes)
        isempty(s) && return nothing
        return KeyPress(first(s))
    end
    return nothing  # other C0 control byte: ignore
end

# The terminal Home key maps to the reader's "select the root node" chord
# (Ctrl+Alt+Home). It is the console's entry point into structural navigation
# (there is no mouse to click a starting selection).
_home_event() = KeyDown(:home, Modifiers(ctrl=true, alt=true))

end # module
