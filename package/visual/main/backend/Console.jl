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

The **geometry-free** half of caret/text editing now lives on the Text domain
(`read_gesture(::TextText, gesture)` in `TextModule`), so the console pipeline
gets it even though it omits `TextToGraphics`: `SyntaxToText` falls back to the
output `TextText`'s `read_gesture` when its operation slot is empty (the console
case). What this backend drives is therefore:

  - **Structural tree navigation** (handled by `SyntaxToText`): arrows move
    node-to-node once a whole element is selected; `Home` selects the root.
  - **`Ctrl+Space`** toggles structural ⇄ text-cursor selection.
  - **Character editing** (via the Text domain's `read_gesture`): character
    insert (`KeyPress`), `Backspace`/`Delete`, and character left/right cursor
    movement — none of which need pixel geometry.
  - **`Ctrl+C`** quits.

Still SDL-only (they need the laid-out glyph geometry): visual up/down line
movement, plain (non-Ctrl) `Home`/`End` to the visual line edges, and
click-to-position.

The selection is shown as inverse-video span colors, baked into the spans by the
`SelectionInverting` projection at the end of the console pipeline (the backend
itself does not resolve the selection or emit a reverse-video attribute).
"""
module ConsoleBackendModule

# The alias is how visual reaches the kernel's backend contract; a bare
# `using` binds the module's *real* name, so extensions qualify BackendModule.
using ..BackendApiModule
using ..DeviceModule
using ..TextModule
using ..ColorModule
using ..FontModule
using ..EventModule

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
a partial escape sequence). `raw_active` records whether `initialize_backend!` put the
terminal into raw mode so `quit_backend!` can restore it. `last_frame` caches the bytes
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
function BackendModule.initialize_backend!(backend::ConsoleBackend)
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

function BackendModule.quit_backend!(backend::ConsoleBackend)
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
BackendModule.measure_text(::ConsoleBackend, text::AbstractString, font) = (length(text), 1)

# ── ANSI styling ─────────────────────────────────────────────────────────

const _ANSI_RESET = "\e[0m"
const _ANSI_CLEAR_HOME = "\e[2J\e[H"

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

# ── Rendering ────────────────────────────────────────────────────────────
#
# The console backend is "dumb": it emits each span's foreground + background
# colors and nothing else. The selection highlight (inverse-video over the
# selected range, plus the widened block caret) is baked into the span colors
# upstream by the `SelectionInverting` projection at the end of the console
# pipeline, so there is no selection-resolution or reverse-video logic here.

# Emit a slice of text with the span's colors. A fresh reset closes the slice
# so attributes don't bleed into the next one.
function _emit_slice!(buf::IO, backend::ConsoleBackend, s::AbstractString, fg, bg)
    isempty(s) && return
    if backend.ansi
        styled = false
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

# Render one span: emit its content with its own foreground/background colors.
function _render_span!(buf::IO, backend::ConsoleBackend, span::TextString)
    content = span.content::AbstractString
    isempty(content) && return
    _emit_slice!(buf, backend, content, span.font_color, span.fill_color)
    return
end

_render_span!(buf::IO, ::ConsoleBackend, ::TextNewline) = (print(buf, '\n'); nothing)

# Span size is in pixels; there is no exact character-cell equivalent.
# Approximate horizontal spacing with a single space; ignore non-pixel units.
_render_span!(buf::IO, ::ConsoleBackend, ::TextSpacing) = (print(buf, ' '); nothing)

# Embedded graphics have no text representation — render nothing.
_render_span!(::IO, ::ConsoleBackend, ::TextGraphics) = nothing
# Fallback for any other span type: ignore it rather than crash.
_render_span!(::IO, ::ConsoleBackend, ::TextDocument) = nothing

"""
    console_render(backend::ConsoleBackend, text::TextText)

Flatten `text`'s spans into a (optionally colored) character stream and write it
to `backend.io` in a single flush. The selection highlight is expected to be
already encoded in the span colors (by `SelectionInverting`).
"""
function console_render(backend::ConsoleBackend, text::TextText)
    buf = IOBuffer()
    backend.ansi && backend.clear && print(buf, _ANSI_CLEAR_HOME)
    for span in text.elements
        _render_span!(buf, backend, span)
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
DeviceModule.write_to_devices(backend::ConsoleBackend, devices, text::TextText) =
    console_render(backend, text)

# Fail loud on a miswired pipeline (e.g. one that still ends in `TextToGraphics`
# and so produces a graphics/screen document instead of a `TextText`).
function DeviceModule.write_to_devices(::ConsoleBackend, devices, output)
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
function DeviceModule.read_from_devices(backend::ConsoleBackend, devices)
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
            deleteat!(buf, 1); return WindowQuit()  # ESC + non-'[' → quit
        end
    end

    deleteat!(buf, 1)
    if b0 == 0x03;  return WindowQuit()                                  # Ctrl-C
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
