"""
    ConsoleBackendModule

Console backend. Renders a **Text-domain** document (`TextText` and its spans)
straight to a terminal (stdout), preserving the spans' colors via ANSI SGR
codes. Unlike the SDL backend it consumes the Text domain directly — the
pipeline stops at `SyntaxToText` and does **not** run `TextToGraphics`, so
`write_to_devices` receives a `TextText`, not a `ScreenDocument`.
"""
module ConsoleBackendModule

import ..BackendModule: Backend, init!, quit!, measure_text
import ..DeviceModule: Device, read_from_devices, write_to_devices
import ..TextModule: TextDocument, TextText, TextString, TextNewline, TextSpacing, TextGraphics
import ..ColorModule: StyleColor, color_default, color_equal
import ..FontModule: StyleFont

export ConsoleBackend, console_render

"""
    ConsoleBackend(; io=stdout, ansi=true, clear=true)

A backend that renders the Text domain to a terminal.

  - `io`    — where to write (default `stdout`).
  - `ansi`  — emit ANSI SGR color codes so the spans' colors are preserved
              (default `true`). Set `false` to write plain, uncolored text
              (e.g. when piping to a non-TTY/plain-text sink).
  - `clear` — clear the screen and home the cursor before each frame so the
              document repaints in place rather than scrolling. Only takes
              effect when `ansi` is also on; ignored otherwise.
"""
mutable struct ConsoleBackend <: Backend
    io::IO
    ansi::Bool
    clear::Bool
end

ConsoleBackend(; io::IO=stdout, ansi::Bool=true, clear::Bool=true) =
    ConsoleBackend(io, ansi, clear)

# ── Backend interface ────────────────────────────────────────────────────

# No library/terminal setup for the render-only milestone. Raw-mode stdin for
# interactive input is a later phase.
init!(::ConsoleBackend) = nothing
quit!(::ConsoleBackend) = nothing

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

# Write one span's contribution into `buf`. `TextString` content (with its
# colors) is the only visible output; `TextNewline` is a line break;
# `TextSpacing` approximates as spaces; `TextGraphics` is skipped (a text
# console can't render embedded graphics).
function _render_span!(buf::IO, backend::ConsoleBackend, span::TextString)
    content = span.content::AbstractString
    isempty(content) && return
    if backend.ansi
        fg = span.font_color
        bg = span.fill_color
        styled = false
        if _meaningful_foreground(fg)
            print(buf, _sgr_foreground(fg::StyleColor)); styled = true
        end
        if bg isa StyleColor
            print(buf, _sgr_background(bg)); styled = true
        end
        print(buf, content)
        styled && print(buf, _ANSI_RESET)
    else
        print(buf, content)
    end
    return
end

_render_span!(buf::IO, ::ConsoleBackend, ::TextNewline) = print(buf, '\n')

function _render_span!(buf::IO, ::ConsoleBackend, span::TextSpacing)
    # Span size is in pixels; there is no exact character-cell equivalent.
    # Approximate horizontal spacing with a single space; ignore non-pixel units.
    print(buf, ' ')
    return
end

# Embedded graphics have no text representation — render nothing.
_render_span!(::IO, ::ConsoleBackend, ::TextGraphics) = nothing

# Fallback for any other span type: ignore it rather than crash.
_render_span!(::IO, ::ConsoleBackend, ::TextDocument) = nothing

"""
    console_render(backend::ConsoleBackend, text::TextText)

Flatten `text`'s spans into a (optionally colored) character stream and write
it to `backend.io` in a single flush.
"""
function console_render(backend::ConsoleBackend, text::TextText)
    buf = IOBuffer()
    backend.ansi && backend.clear && print(buf, _ANSI_CLEAR_HOME)
    for span in text.elements
        _render_span!(buf, backend, span)
    end
    print(backend.io, String(take!(buf)))
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

# Render-only milestone: no input devices yet, so there is nothing to poll.
read_from_devices(::ConsoleBackend, devices) = nothing

end # module
