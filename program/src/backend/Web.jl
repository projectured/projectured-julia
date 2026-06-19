"""
    WebBackendModule

Web backend. Runs the editor inside an HTTP + WebSocket server; the **final
rendering step happens in the browser**. A connected JavaScript client sends raw
mouse/keyboard events and receives a list of drawing primitives (a JSON
draw-list) to paint onto an HTML `<canvas>`.

This is a drop-in `Backend`: `run!(WebBackend(; port=8080), projection, document)`
substitutes for `run!(SdlBackend(), …)` with no change to the editor loop,
projection pipeline, or domains.

Layering vs. SDL:
- **Text metrics stay on the server.** The projection pipeline bakes
  `TextToGraphics(measure=sdl_measure_text)` into layout, so SDL_ttf must be
  initialised to print at all. `init!` runs `SDL_Init(SDL_INIT_VIDEO)` +
  `TTF_Init()` (no window) and reuses `sdl_measure_text`. The browser renders the
  same TTFs (served from `font/`), so metrics line up.
- **Output**: `write_to_devices` serializes the projection-output
  `ScreenDocument` into a per-window draw-list (mirroring the SDL renderer's
  element set) and pushes it to the client over the WebSocket.
- **Input**: a receive task decodes the client's JSON events into the
  backend-agnostic vocabulary (`MouseDown`, `KeyPress`, …) wrapped in
  `EventEnvelope`s on a `Channel`; `read_from_devices` drains it non-blocking.

Constraints (v1): exactly one client per editor (a second WS upgrade is
rejected); JSON transport both directions; key-symbol mapping is done on the
server (`web_key_to_symbol`, mirroring `sdl_keysym_to_symbol`).
"""
module WebBackendModule

using HTTP
using JSON3
using Base64: base64encode
using SimpleDirectMediaLayer.LibSDL2: SDL_Init, SDL_INIT_VIDEO, TTF_Init

import ..BackendModule: Backend, init!, quit!, measure_text
import ..DeviceModule: Device, read_from_devices, write_to_devices
import ..GraphicsModule: GraphicsCanvas, GraphicsText, GraphicsRect, GraphicsLine,
                         GraphicsCircle, GraphicsViewport, GraphicsImage, GraphicsFence
import ..CollectionModule: ListNode
import ..FontModule: StyleFont
import ..ScreenModule: QuitEvent
import ..ScreenDocumentModule: ScreenDocument, WindowDocument, EventEnvelope,
                               WindowCloseRequest, WindowResizeEvent
import ..ModifiersModule: Modifiers
import ..KeyboardModule: KeyDown, KeyUp, KeyPress
import ..MouseModule: MouseDown, MouseUp, MousePress, MouseMove, MouseScroll
import ..SdlBackendModule: sdl_measure_text

export WebBackend, web_key_to_symbol

# ════════════════════════════════════════════════════════════════════════
# Connection + backend state
# ════════════════════════════════════════════════════════════════════════

"""
    WebConn

The single live WebSocket connection. Outbound frames are coalesced: each new
frame overwrites `pending`, and a capacity-1 `doorbell` channel wakes the send
task — so frames produced faster than the socket drains collapse to the latest.
"""
mutable struct WebConn
    ws::Any
    pending::Ref{Union{Nothing,String}}
    doorbell::Channel{Nothing}
    sendtask::Union{Task,Nothing}
end

WebConn(ws) = WebConn(ws, Ref{Union{Nothing,String}}(nothing), Channel{Nothing}(1), nothing)

"""
    WebBackend(; host="127.0.0.1", port=8080)

HTTP + WebSocket backend. Serves the browser client and a per-window JSON
draw-list, and decodes the client's input events. One client per editor.
"""
mutable struct WebBackend <: Backend
    host::String
    port::Int
    webdir::String
    fontdir::String
    server::Any
    inbound::Channel{Any}              # decoded EventEnvelopes from the client
    conn::Union{WebConn,Nothing}       # the one live connection
    last_frame::Union{String,Nothing}  # last serialized frame (for late joiners)
    last_sent::Union{String,Nothing}   # last frame actually sent (dedup)
    # MousePress synthesis state (mirrors SdlBackend).
    last_down_button::Symbol
    last_down_x::Int
    last_down_y::Int
    last_down_time::Float64
end

function WebBackend(; host::AbstractString="127.0.0.1", port::Integer=8080)
    webdir  = normpath(joinpath(@__DIR__, "..", "..", "web"))
    fontdir = normpath(joinpath(@__DIR__, "..", "..", "..", "font"))
    WebBackend(String(host), Int(port), webdir, fontdir,
               nothing, Channel{Any}(256), nothing, nothing, nothing,
               :none, 0, 0, 0.0)
end

# ════════════════════════════════════════════════════════════════════════
# Key mapping (server-side; mirrors sdl_keysym_to_symbol)
# ════════════════════════════════════════════════════════════════════════

"""
    web_key_to_symbol(key, code, mods) -> Symbol

Map a browser `KeyboardEvent.key` (+ `code` for left/right modifier identity)
to the backend-agnostic key vocabulary, mirroring `sdl_keysym_to_symbol`.
Printable keys whose specific identity is not tracked return `:char` (the
character itself arrives separately via a `keypress` → `KeyPress`).
"""
function web_key_to_symbol(key::AbstractString, code::AbstractString, mods::Modifiers)::Symbol
    # Navigation
    key == "ArrowLeft"  && return :left
    key == "ArrowRight" && return :right
    key == "ArrowUp"    && return :up
    key == "ArrowDown"  && return :down
    key == "Home"       && return :home
    key == "End"        && return :end
    key == "PageUp"     && return :page_up
    key == "PageDown"   && return :page_down
    # Editing
    key == "Backspace"  && return :backspace
    key == "Delete"     && return :delete
    key == "Enter"      && return :return
    key == "Tab"        && return :tab
    key == "Insert"     && return :insert
    key == "Escape"     && return :escape
    key == "CapsLock"   && return :caps_lock
    # Function keys F1..F12
    if length(key) >= 2 && key[1] == 'F'
        n = tryparse(Int, SubString(key, 2))
        n !== nothing && 1 <= n <= 12 && return Symbol("f", n)
    end
    # Modifier-only keys (left/right via code)
    code == "ControlLeft"  && return :lctrl
    code == "ControlRight" && return :rctrl
    code == "ShiftLeft"    && return :lshift
    code == "ShiftRight"   && return :rshift
    code == "AltLeft"      && return :lalt
    code == "AltRight"     && return :ralt
    code == "MetaLeft"     && return :lmeta
    code == "MetaRight"    && return :rmeta
    key == "Control" && return :lctrl
    key == "Shift"   && return :lshift
    key == "Alt"     && return :lalt
    key == "Meta"    && return :lmeta
    # Single printable characters
    if length(key) == 1
        c = key[1]
        c == ' ' && return :space
        c == '.' && return :period
        c == '/' && return :slash
        c == '*' && return :asterisk
        (c == '=' || c == '+') && return :equals
        c == '-' && return :minus
        lc = lowercase(c)
        lc == 'c' && return :c
        lc == 'x' && return :x
        lc == 'v' && return :v
        lc == 'n' && return :n
        return :char
    end
    return :char
end

# ════════════════════════════════════════════════════════════════════════
# Draw-list serialization (mirrors Sdl's _dispatch_render_elem!)
# ════════════════════════════════════════════════════════════════════════

_rgba(e) = Int[Int(e.r), Int(e.g), Int(e.b), Int(e.a)]
_border_rgba(e) = Int[Int(e.border_r), Int(e.border_g), Int(e.border_b), Int(e.border_a)]
_font_family(path::AbstractString) = splitext(basename(path))[1]

# Serialize one element into a draw-list node, or `nothing` to skip it
# (GraphicsFence, an unrenderable image, or an unknown type).
function _serialize_node(elem)
    if elem isa GraphicsText
        font = elem.font::StyleFont
        return Dict("t" => "text", "x" => Int(elem.x), "y" => Int(elem.y),
                    "s" => elem.text, "f" => _font_family(font.filename),
                    "sz" => font.size, "c" => _rgba(elem))
    elseif elem isa GraphicsRect
        return Dict("t" => "rect", "x" => Int(elem.x), "y" => Int(elem.y),
                    "w" => Int(elem.w), "h" => Int(elem.h), "c" => _rgba(elem),
                    "rtl" => Int(elem.radius_tl), "rtr" => Int(elem.radius_tr),
                    "rbr" => Int(elem.radius_br), "rbl" => Int(elem.radius_bl),
                    "bw" => Int(elem.border_width), "bc" => _border_rgba(elem))
    elseif elem isa GraphicsLine
        return Dict("t" => "line", "x1" => Int(elem.x1), "y1" => Int(elem.y1),
                    "x2" => Int(elem.x2), "y2" => Int(elem.y2),
                    "c" => _rgba(elem), "w" => Int(elem.width))
    elseif elem isa GraphicsCircle
        return Dict("t" => "circle", "cx" => Int(elem.cx), "cy" => Int(elem.cy),
                    "r" => Int(elem.radius), "c" => _rgba(elem),
                    "bw" => Int(elem.border_width), "bc" => _border_rgba(elem))
    elseif elem isa GraphicsViewport
        content = elem.content::GraphicsCanvas
        return Dict("t" => "clip", "x" => Int(elem.x), "y" => Int(elem.y),
                    "w" => Int(elem.w), "h" => Int(elem.h),
                    "ox" => Int(content.x), "oy" => Int(content.y),
                    "content" => _serialize_children(content))
    elseif elem isa GraphicsCanvas
        return Dict("t" => "group", "x" => Int(elem.x), "y" => Int(elem.y),
                    "content" => _serialize_children(elem))
    elseif elem isa GraphicsImage
        return _serialize_image(elem)
    end
    return nothing  # GraphicsFence / unknown
end

# Only the decoded-buffer image forms are serializable; the SDL-texture `Ptr`
# form is skipped (it has no web analog in v1).
function _serialize_image(elem::GraphicsImage)
    data = elem.data
    data === nothing && return nothing
    local buf::Vector{UInt8}, nw::Int, nh::Int
    if data isa Tuple && length(data) == 3 && data[1] isa Vector{UInt8}
        buf, nw, nh = data[1]::Vector{UInt8}, Int(data[2]), Int(data[3])
    elseif data isa Vector{UInt8}
        buf, nw, nh = data, Int(elem.w), Int(elem.h)
    else
        return nothing
    end
    (nw <= 0 || nh <= 0) && return nothing
    Dict("t" => "image", "x" => Int(elem.x), "y" => Int(elem.y),
         "w" => Int(elem.w), "h" => Int(elem.h),
         "nw" => nw, "nh" => nh, "rgba" => base64encode(buf))
end

# Serialize a canvas's element list, mirroring `_render_canvas!`'s traversal
# order (the `ListNode` prev-chain, then the head's next-chain) so paint
# z-order matches SDL. The early-stop / off-screen culling is omitted for
# correctness in v1 (the client clips).
function _serialize_children(canvas::GraphicsCanvas)
    out = Any[]
    elements = canvas.elements
    if elements isa ListNode
        prev_node = elements.prev
        while prev_node !== nothing
            n = _serialize_node(prev_node.value)
            n === nothing || push!(out, n)
            prev_node = prev_node.prev
        end
        node = elements
        while node !== nothing
            n = _serialize_node(node.value)
            n === nothing || push!(out, n)
            node = node.next
        end
    else
        for elem in elements
            n = _serialize_node(elem)
            n === nothing || push!(out, n)
        end
    end
    out
end

# Serialize the whole ScreenDocument into a `frame` message. The top-level
# window content canvas is painted at origin (0,0) just like SDL
# (`_render_canvas!(…, 0, 0, …)`), so its own x/y are not applied here.
function _serialize_screen(screen::ScreenDocument)::String
    windows = Any[]
    for w in screen.windows
        w isa WindowDocument || continue
        content = w.content
        draw = content isa GraphicsCanvas ? _serialize_children(content) : Any[]
        push!(windows, Dict(
            "id" => String(w.id), "title" => w.title,
            "x" => Int(w.x), "y" => Int(w.y), "w" => Int(w.width), "h" => Int(w.height),
            "bg" => Int[Int(w.bg[1]), Int(w.bg[2]), Int(w.bg[3]), Int(w.bg[4])],
            "style" => String(w.style), "draw" => draw))
    end
    JSON3.write(Dict("type" => "frame", "windows" => windows))
end

# ════════════════════════════════════════════════════════════════════════
# Event decoding (client JSON → EventEnvelope on the inbound channel)
# ════════════════════════════════════════════════════════════════════════

function _mods(obj)::Modifiers
    m = get(obj, :mods, nothing)
    m === nothing && return Modifiers(false, false, false, false)
    Modifiers(Bool(get(m, :ctrl, false)), Bool(get(m, :shift, false)),
              Bool(get(m, :alt, false)), Bool(get(m, :meta, false)))
end

_button(obj)::Symbol = Symbol(String(get(obj, :button, "left")))
_winid(obj)::Symbol = haskey(obj, :window) ? Symbol(String(obj[:window])) : :none

# Decode one client message and enqueue the resulting EventEnvelope(s). All
# MousePress synthesis state lives on `backend` and is touched only here (single
# receive task), so no locking is needed.
function _decode_and_enqueue!(backend::WebBackend, msg)
    obj = JSON3.read(msg)
    typ = String(obj[:type])
    wid = _winid(obj)

    if typ == "mousedown"
        b = _button(obj); x = Int(obj[:x]); y = Int(obj[:y])
        backend.last_down_button = b
        backend.last_down_x = x
        backend.last_down_y = y
        backend.last_down_time = time()
        put!(backend.inbound, EventEnvelope(wid, MouseDown(b, x, y, _mods(obj))))

    elseif typ == "mouseup"
        b = _button(obj); x = Int(obj[:x]); y = Int(obj[:y]); m = _mods(obj)
        put!(backend.inbound, EventEnvelope(wid, MouseUp(b, x, y, m)))
        # Synthesise MousePress when this up matches the preceding down.
        if b == backend.last_down_button &&
           abs(x - backend.last_down_x) < 5 && abs(y - backend.last_down_y) < 5 &&
           (time() - backend.last_down_time) < 0.3
            put!(backend.inbound, EventEnvelope(wid, MousePress(b, x, y, m)))
        end

    elseif typ == "mousemove"
        buttons = Symbol(String(get(obj, :buttons, "none")))
        buttons === :none && return  # only forward motion while a button is held
        put!(backend.inbound, EventEnvelope(wid,
            MouseMove(Int(obj[:x]), Int(obj[:y]), buttons, _mods(obj))))

    elseif typ == "scroll"
        put!(backend.inbound, EventEnvelope(wid,
            MouseScroll(Int(obj[:dx]), Int(obj[:dy]), Int(obj[:x]), Int(obj[:y]), _mods(obj))))

    elseif typ == "keydown"
        m = _mods(obj)
        key = String(obj[:key])
        # Escape quits the application, mirroring the SDL backend.
        if key == "Escape"
            put!(backend.inbound, EventEnvelope(:none, QuitEvent()))
            return
        end
        sym = web_key_to_symbol(key, String(get(obj, :code, "")), m)
        put!(backend.inbound, EventEnvelope(wid, KeyDown(sym, m, Bool(get(obj, :repeat, false)))))

    elseif typ == "keyup"
        m = _mods(obj)
        sym = web_key_to_symbol(String(obj[:key]), String(get(obj, :code, "")), m)
        put!(backend.inbound, EventEnvelope(wid, KeyUp(sym, m)))

    elseif typ == "keypress"
        text = String(obj[:text])
        isempty(text) && return
        put!(backend.inbound, EventEnvelope(wid, KeyPress(first(text), text, _mods(obj))))

    elseif typ == "resize"
        put!(backend.inbound, EventEnvelope(wid, WindowResizeEvent(Int(obj[:w]), Int(obj[:h]))))

    elseif typ == "close"
        put!(backend.inbound, EventEnvelope(wid, WindowCloseRequest()))

    elseif typ == "quit"
        put!(backend.inbound, EventEnvelope(:none, QuitEvent()))
    end
    return
end

# ════════════════════════════════════════════════════════════════════════
# HTTP: static assets + WebSocket
# ════════════════════════════════════════════════════════════════════════

function _fonts_json(fontdir::AbstractString)::String
    names = String[]
    if isdir(fontdir)
        for f in readdir(fontdir)
            ext = lowercase(splitext(f)[2])
            (ext == ".ttf" || ext == ".otf") && push!(names, f)
        end
    end
    JSON3.write(Dict("fonts" => names))
end

# Resolve a request path to (body, content_type), or (nothing, "") for 404.
function _resolve_asset(backend::WebBackend, path::AbstractString)
    if path == "/" || path == "/index.html"
        f = joinpath(backend.webdir, "index.html")
        isfile(f) && return (read(f), "text/html; charset=utf-8")
    elseif path == "/client.js"
        f = joinpath(backend.webdir, "client.js")
        isfile(f) && return (read(f), "text/javascript; charset=utf-8")
    elseif path == "/fonts.json"
        return (Vector{UInt8}(_fonts_json(backend.fontdir)), "application/json")
    elseif startswith(path, "/font/")
        name = basename(path)  # basename guards against path traversal
        f = joinpath(backend.fontdir, name)
        if isfile(f)
            ext = lowercase(splitext(name)[2])
            return (read(f), ext == ".otf" ? "font/otf" : "font/ttf")
        end
    end
    return (nothing, "")
end

function _serve_static(backend::WebBackend, http)
    path = first(split(http.message.target, '?'))
    body, ctype = _resolve_asset(backend, path)
    if body === nothing
        HTTP.setstatus(http, 404)
        HTTP.startwrite(http)
        write(http, "not found")
        return
    end
    HTTP.setstatus(http, 200)
    HTTP.setheader(http, "Content-Type" => ctype)
    HTTP.setheader(http, "Cache-Control" => "no-cache")
    HTTP.startwrite(http)
    write(http, body)
    return
end

# Drain coalesced frames to the socket until the connection closes.
function _send_loop(conn::WebConn)
    for _ in conn.doorbell
        msg = conn.pending[]
        conn.pending[] = nothing
        msg === nothing && continue
        try
            HTTP.WebSockets.isclosed(conn.ws) && break
            HTTP.WebSockets.send(conn.ws, msg)
        catch
            break
        end
    end
end

function _send_frame!(conn::WebConn, str::AbstractString)
    conn.pending[] = String(str)
    isready(conn.doorbell) || (try; put!(conn.doorbell, nothing); catch; end)
    return
end

function _handle_ws(backend::WebBackend, ws)
    # One client per editor: reject a second connection.
    if backend.conn !== nothing
        try; HTTP.WebSockets.send(ws, JSON3.write(Dict("type" => "busy"))); catch; end
        return
    end
    conn = WebConn(ws)
    backend.conn = conn
    backend.last_sent = nothing  # force a full resend to the new client
    conn.sendtask = @async _send_loop(conn)
    backend.last_frame === nothing || _send_frame!(conn, backend.last_frame)
    try
        for msg in ws
            try
                _decode_and_enqueue!(backend, msg)
            catch err
                @warn "web backend: failed to decode client event" exception=err
            end
        end
    catch
        # Connection dropped; fall through to cleanup.
    finally
        try; close(conn.doorbell); catch; end
        backend.conn === conn && (backend.conn = nothing)
    end
    return
end

# ════════════════════════════════════════════════════════════════════════
# Backend interface
# ════════════════════════════════════════════════════════════════════════

function init!(backend::WebBackend)
    # SDL_ttf is needed for text metrics (`sdl_measure_text`); no window is
    # created. SDL_INIT_VIDEO is reference-counted, so this is safe to repeat.
    SDL_Init(SDL_INIT_VIDEO)
    TTF_Init()
    backend.server = HTTP.listen!(backend.host, backend.port) do http
        if HTTP.WebSockets.isupgrade(http.message)
            HTTP.WebSockets.upgrade(ws -> _handle_ws(backend, ws), http)
        else
            _serve_static(backend, http)
        end
    end
    @info "Web backend listening on http://$(backend.host):$(backend.port)"
    return nothing
end

function quit!(backend::WebBackend)
    conn = backend.conn
    if conn !== nothing
        try; close(conn.doorbell); catch; end
        try; close(conn.ws); catch; end
        backend.conn = nothing
    end
    if backend.server !== nothing
        try; close(backend.server); catch; end
        backend.server = nothing
    end
    # Intentionally do not TTF_Quit/SDL_Quit: the shared SDL font cache in
    # SdlBackendModule holds open TTF_Font pointers that would dangle. SDL stays
    # initialised for the process lifetime; harmless.
    return nothing
end

measure_text(::WebBackend, text::AbstractString, font::StyleFont) = sdl_measure_text(text, font)

# Non-blocking poll: hand back the next decoded event, or nothing.
read_from_devices(backend::WebBackend, devices) =
    isready(backend.inbound) ? take!(backend.inbound) : nothing

"""
    write_to_devices(backend::WebBackend, devices, screen::ScreenDocument)

Serialize the projection-output `ScreenDocument` into a per-window JSON
draw-list and push it to the connected client. A frame identical to the last one
sent is skipped (the editor loop repaints every frame at ~100 Hz). The latest
frame is retained so a client connecting later receives the current view.
"""
function write_to_devices(backend::WebBackend, devices, screen::ScreenDocument)
    str = _serialize_screen(screen)
    backend.last_frame = str
    conn = backend.conn
    if conn !== nothing && str != backend.last_sent
        _send_frame!(conn, str)
        backend.last_sent = str
    end
    return nothing
end

# Fail loud on a miswired pipeline whose output is not a ScreenDocument.
function write_to_devices(::WebBackend, devices, output)
    error("write_to_devices(::WebBackend, …): pipeline output is $(typeof(output)), " *
          "expected a ScreenDocument. The web backend renders the multi-window " *
          "screen pipeline (same as the SDL backend).")
end

end # module
