# Fragment of `ConsoleModule` — `ConsoleBackend`, the backend that draws
# into a terminal and reads its keyboard.

mutable struct ConsoleBackend <: Backend
    io::IO
    input::IO
    ansi::Bool
    clear::Bool
    inbuf::Vector{UInt8}
    raw_active::Bool
    last_frame::Union{String,Nothing}
    # The wait machinery. `wake_gate` is an autoreset event: a notification
    # that arrives before the wait is stored, not lost. `watcher` is the task
    # that blocks on the TTY and notifies the gate when bytes arrive; it stays
    # `nothing` for an input the watcher cannot block on (an `IOBuffer` in
    # tests), and the wait then degrades to the default poll slice.
    wake_gate::Base.Event
    watcher::Union{Task, Nothing}
    watching::Bool
end

ConsoleBackend(; io::IO=stdout, input::IO=stdin, ansi::Bool=true, clear::Bool=true) =
    ConsoleBackend(io, input, ansi, clear, UInt8[], false, nothing,
                   Base.Event(true), nothing, false)

# The console draws a block of text, so it is chosen only for an editor whose
# output is text, and never beside a backend that draws windows.
get_backend_name(::Type{ConsoleBackend}) = :console
get_backend_output(::Type{ConsoleBackend}) = :text

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
        backend.watching = true
        backend.watcher = @async _watch_console_input!(backend)
    end
    return nothing
end

function BackendModule.quit_backend!(backend::ConsoleBackend)
    # The watcher checks this flag after every block; a watcher stuck on a
    # quiet TTY exits on the next byte, which is harmless.
    backend.watching = false
    notify(backend.wake_gate)
    backend.watcher = nothing
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

# The watcher: block on the TTY until bytes arrive, notify the gate, and hold
# until the editor consumed them — `wait_readnb` answers at once while bytes
# sit unread, so the hold is what keeps this loop from spinning.
function _watch_console_input!(backend::ConsoleBackend)
    io = backend.input
    while backend.watching && isopen(io)
        try
            Base.wait_readnb(io, 1)
        catch
            break                          # the stream closed under the wait
        end
        backend.watching || break
        notify(backend.wake_gate)
        while backend.watching && isopen(io) && bytesavailable(io) > 0
            sleep(0.01)
        end
    end
    nothing
end

"""
    wait_for_input(backend::ConsoleBackend, devices, timeout_seconds) -> Nothing

Block until the watcher reports terminal bytes, [`wake_backend!`](@ref) is
called, or `timeout_seconds` passes. Bytes already buffered — parsed or raw —
end the wait before it starts. Without a watcher (an `IOBuffer` input) the
wait is the default poll slice, so a scripted backend keeps the old cadence.
Everything here is a cooperative Julia wait; no thread blocks.
"""
function BackendModule.wait_for_input(backend::ConsoleBackend, devices, timeout_seconds)
    isempty(backend.inbuf) || return nothing
    bytesavailable(backend.input) > 0 && return nothing
    if backend.watcher === nothing
        sleep(min(timeout_seconds, 0.01))
        return nothing
    end
    _wait_for_gate(backend.wake_gate, timeout_seconds)
    return nothing
end

"""
    wake_backend!(backend::ConsoleBackend) -> Nothing

End a [`wait_for_input`](@ref) in progress. The autoreset gate stores a
notification that arrives before the wait, so a wake can never slip between
the buffer checks and the block.
"""
BackendModule.wake_backend!(backend::ConsoleBackend) =
    (notify(backend.wake_gate); nothing)

# Wait on the gate, at most `timeout_seconds`. The timer notifies the same
# gate; a timer that fires after the gate already opened leaves one stored
# notification behind, which costs one prompt wait later and nothing else.
function _wait_for_gate(gate::Base.Event, timeout_seconds)
    timeout_seconds == Inf && return wait(gate)
    timer = Timer(_ -> notify(gate), timeout_seconds)
    try
        wait(gate)
    finally
        close(timer)
    end
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
_meaningful_foreground(c) = c isa StyleColor && !is_color_equal(c, color_default)

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
    render_console(backend::ConsoleBackend, text::TextBlock)

Flatten `text`'s spans into a (optionally colored) character stream and write it
to `backend.io` in a single flush. The selection highlight is expected to be
already encoded in the span colors (by `SelectionInverting`).
"""
function render_console(backend::ConsoleBackend, text::TextBlock)
    buf = IOBuffer()
    backend.ansi && backend.clear && print(buf, _ANSI_CLEAR_HOME)
    for (i, span) in enumerate(text.elements)
        # A TextLine implies its break: it is a *separator*, so every line but a
        # leading one starts by ending the previous one. Its indentation is a
        # property of the line, printed here rather than carried in a span.
        if span isa TextLine
            i > 1 && print(buf, '\n')
            print(buf, ' '^span.indentation)
            for inner in span.elements
                _render_span!(buf, backend, inner)
            end
            continue
        end
        _render_span!(buf, backend, span)
    end
    frame = String(take!(buf))
    # Skip the write when the frame is identical to the last one. The editor's
    # loop calls run_print_stage! every tick; without this the screen would clear+redraw
    # continuously and flicker.
    frame == backend.last_frame && return nothing
    backend.last_frame = frame
    print(backend.io, frame)
    flush(backend.io)
    return nothing
end

# ── Device I/O ───────────────────────────────────────────────────────────

"""
    write_to_devices(::ConsoleBackend, devices, text::TextBlock)

Render the Text-domain output of the projection pipeline to the terminal.
"""
BackendModule.write_to_devices(backend::ConsoleBackend, devices, text::TextBlock) =
    render_console(backend, text)

# Fail loud on a miswired pipeline (e.g. one that still ends in `TextToGraphics`
# and so produces a graphics/screen document instead of a `TextBlock`).
function BackendModule.write_to_devices(::ConsoleBackend, devices, output)
    error("write_to_devices(::ConsoleBackend, …): pipeline output is " *
          "$(typeof(output)), expected a TextBlock. The console backend renders " *
          "the Text domain directly — drop the TextToGraphics step from the pipeline.")
end

"""
    read_from_devices(::ConsoleBackend, devices) -> WindowInput or nothing

Poll `backend.input` (non-blocking) and translate the next keystroke into a
backend-agnostic event wrapped in an `WindowInput`. The window id is the
sentinel `:console` (there is no `WindowDocument`). Returns `nothing` when no
complete event is buffered.

A buffer that ends in the start of an escape sequence gets
`_ESCAPE_SEQUENCE_TIMEOUT_SECONDS` for the rest of the sequence to arrive.
When no byte arrives in that time, the bytes are the keys that the user typed:
a lone ESC is Escape, and ESC with one more byte is that key with Alt.
"""
function BackendModule.read_from_devices(backend::ConsoleBackend, devices)
    _drain_input!(backend)
    # The terminal gives no time with its bytes, so an event has the time of the read.
    read_time = time()
    buffer = backend.inbuf
    while !isempty(buffer)
        count = length(buffer)
        event = _next_event!(buffer; time = read_time)
        if event === nothing && length(buffer) == count
            _wait_for_input_bytes(backend.input, _ESCAPE_SEQUENCE_TIMEOUT_SECONDS)
            _drain_input!(backend)
            event = _next_event!(buffer; settled = length(buffer) == count,
                                 time = read_time)
        end
        event === nothing || return WindowInput(:console, event)
    end
    return nothing
end

# A terminal writes a whole escape sequence at once, so its bytes normally
# arrive in one read. The timeout covers a sequence that a slow link splits,
# and it is the time that a lone Escape waits before it is read.
const _ESCAPE_SEQUENCE_TIMEOUT_SECONDS = 0.05

# Wait at most `seconds` for a byte on `io`. The short sleeps let the libuv
# loop fill the buffer of a TTY. An `IOBuffer` gets no new byte, so a wait on
# it takes the whole time.
function _wait_for_input_bytes(io::IO, seconds::Real)
    deadline = time() + seconds
    while bytesavailable(io) == 0 && time() < deadline
        sleep(0.005)
    end
    return nothing
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

# Parse and consume one event from the front of `buf`. Return `nothing` and
# leave the bytes in place when the buffer holds only the start of a sequence
# and `settled` is false. With `settled`, no more bytes follow, so the start of
# a sequence is read as the keys that were typed, and at least one byte is
# consumed. A sequence that makes no event is consumed, and `nothing` is
# returned. The event has the time `time`, when the bytes were read. Pure aside
# from mutating `buf`, so it is unit-testable.
function _next_event!(buf::Vector{UInt8}; settled::Bool = false, time::Real)
    isempty(buf) && return nothing
    b0 = buf[1]
    b0 == 0x1b && return _next_escape_event!(buf, settled, time)
    b0 >= 0x80 && !settled && length(buf) < _count_utf8_bytes(b0) && return nothing

    deleteat!(buf, 1)
    if b0 == 0x03;  return WindowQuit(; time)                              # Ctrl-C
    elseif b0 == 0x00; return KeyDown(:space, ModifierKeys(ctrl=true); time) # Ctrl-Space
    elseif b0 == 0x0d || b0 == 0x0a; return KeyDown(:return, ModifierKeys(); time)
    elseif b0 == 0x7f || b0 == 0x08; return KeyDown(:backspace, ModifierKeys(); time)
    elseif b0 == 0x09; return KeyDown(:tab, ModifierKeys(); time)
    elseif 0x01 <= b0 <= 0x1a                                           # Ctrl+A to Ctrl+Z
        return KeyDown(Symbol(Char(b0 + 0x60)), ModifierKeys(ctrl = true); time)
    elseif 0x20 <= b0 < 0x7f; return KeyPress(Char(b0); time)          # printable ASCII
    elseif b0 >= 0x80                                                   # UTF-8 lead byte
        nbytes = _count_utf8_bytes(b0)
        bytes = UInt8[b0]
        while length(bytes) < nbytes && !isempty(buf)
            push!(bytes, popfirst!(buf))
        end
        s = String(bytes)
        isempty(s) && return nothing
        return KeyPress(first(s); time)
    end
    return nothing  # other C0 control byte: ignore
end

_count_utf8_bytes(lead::UInt8) = lead >= 0xf0 ? 4 : lead >= 0xe0 ? 3 : 2

# Parse the event at the front of `buf`, which starts with ESC. ESC starts a
# control sequence (`ESC [`), a key of the keypad (`ESC O`), an Alt chord (ESC
# and the key, as xterm sends it), or it is the Escape key itself.
function _next_escape_event!(buf::Vector{UInt8}, settled::Bool, time::Real)
    if length(buf) == 1
        settled || return nothing
        popfirst!(buf)
        return KeyDown(:escape, ModifierKeys(); time)
    end
    second = buf[2]
    if second == 0x1b
        # A second ESC starts a new key, so the first ESC is Escape.
        popfirst!(buf)
        return KeyDown(:escape, ModifierKeys(); time)
    elseif second == UInt8('[') || second == UInt8('O')
        event, count = _decode_escape_sequence(buf, time)
        if count > 0
            deleteat!(buf, 1:count)
            return event
        end
        # The sequence is not complete. With no more bytes to come, ESC and
        # `[` or `O` were typed as an Alt chord.
        settled || return nothing
    end
    tail = buf[2:end]
    event = _next_event!(tail; settled, time)
    consumed = length(buf) - 1 - length(tail)
    consumed == 0 && return nothing
    deleteat!(buf, 1:(1 + consumed))
    return event === nothing ? nothing : _with_alt_modifier(event)
end

# The keys of the final byte of a control sequence, and of the byte after `ESC O`.
const _FINAL_BYTE_KEYS = Dict{UInt8,Symbol}(
    UInt8('A') => :up, UInt8('B') => :down, UInt8('C') => :right, UInt8('D') => :left,
    UInt8('H') => :home, UInt8('F') => :end,
    UInt8('P') => :f1, UInt8('Q') => :f2, UInt8('R') => :f3, UInt8('S') => :f4)

# The keys of `ESC [ n ~`, by the number n. 1 and 7 are Home, 4 and 8 are End:
# xterm and rxvt send different numbers.
const _TILDE_KEYS = Dict{Int,Symbol}(
    1 => :home, 2 => :insert, 3 => :delete, 4 => :end, 5 => :page_up, 6 => :page_down,
    7 => :home, 8 => :end, 11 => :f1, 12 => :f2, 13 => :f3, 14 => :f4, 15 => :f5,
    17 => :f6, 18 => :f7, 19 => :f8, 20 => :f9, 21 => :f10, 23 => :f11, 24 => :f12)

# Decode the sequence `ESC [ parameters final` or `ESC O final` at the front of
# `buf`. Return the event and the count of bytes that the sequence takes. The
# event is `nothing` for a sequence that has no key here, and the count is 0
# for a sequence whose final byte has not arrived. The event has the time `time`.
function _decode_escape_sequence(buf::Vector{UInt8}, time::Real)
    if buf[2] == UInt8('O')
        length(buf) < 3 && return (nothing, 0)
        key = get(_FINAL_BYTE_KEYS, buf[3], nothing)
        # `ESC O` and a byte that no keypad key sends is Alt+O.
        key === nothing && return (KeyPress('O', ModifierKeys(alt = true); time), 2)
        return (_make_key_event(key, ModifierKeys(), time), 3)
    end
    index = 3
    while index <= length(buf) && 0x20 <= buf[index] <= 0x3f
        index += 1
    end
    index > length(buf) && return (nothing, 0)
    final = buf[index]
    # A byte that can not end a sequence ends the sequence without an event;
    # that byte is parsed on its own.
    0x40 <= final <= 0x7e || return (nothing, index - 1)
    parameters = [something(tryparse(Int, text), 1) for text in split(String(buf[3:index - 1]), ';')]
    modifiers = _decode_modifier_parameter(length(parameters) >= 2 ? parameters[2] : 1)
    key = final == UInt8('~') ? get(_TILDE_KEYS, parameters[1], nothing) :
          final == UInt8('Z') ? :tab :
          get(_FINAL_BYTE_KEYS, final, nothing)
    key === nothing && return (nothing, index)
    if final == UInt8('Z')
        modifiers = ModifierKeys(ctrl = modifiers.ctrl, shift = true, alt = modifiers.alt,
                                 meta = modifiers.meta)
    end
    return (_make_key_event(key, modifiers, time), index)
end

# xterm sends the modifiers of a key as the parameter 1 + m, where m is the sum
# of 1 for Shift, 2 for Alt, 4 for Ctrl and 8 for Meta.
function _decode_modifier_parameter(parameter::Int)
    m = max(parameter - 1, 0)
    ModifierKeys(ctrl = m & 4 != 0, shift = m & 1 != 0, alt = m & 2 != 0, meta = m & 8 != 0)
end

# Home with no modifier is the chord that selects the root; see `_home_event`.
_make_key_event(key::Symbol, modifiers::ModifierKeys, time::Real) =
    key === :home && modifiers == ModifierKeys() ? _home_event(time) :
                                                   KeyDown(key, modifiers; time)

_with_alt_modifier(event::KeyDown) =
    KeyDown(event.key, _with_alt_modifier(event.modifiers); repeat = event.repeat,
            time = event.time)
_with_alt_modifier(event::KeyPress) =
    KeyPress(event.char, event.text, _with_alt_modifier(event.modifiers); time = event.time)
_with_alt_modifier(modifiers::ModifierKeys) =
    ModifierKeys(ctrl = modifiers.ctrl, shift = modifiers.shift, alt = true,
                 meta = modifiers.meta)
_with_alt_modifier(event) = event

# The terminal Home key maps to the reader's "select the root node" chord
# (Ctrl+Alt+Home). It is the console's entry point into structural navigation
# (there is no mouse to click a starting selection).
_home_event(time::Real) = KeyDown(:home, ModifierKeys(ctrl=true, alt=true); time)
