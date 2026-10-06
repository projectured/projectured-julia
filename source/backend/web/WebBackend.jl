# Fragment of `WebModule` — `WebBackend`: the HTTP and WebSocket server, the
# drawing of each window as JSON, and the input of the browser.

# ════════════════════════════════════════════════════════════════════════
# Connection + backend state
# ════════════════════════════════════════════════════════════════════════

"""
    WebConnection

The single live WebSocket connection. `outbox` is an in-order FIFO of JSON
messages drained by the send task. Patches are order-sensitive, so the queue is
never coalesced; when it nears capacity the backend falls back to a full resend
(`force_full`) instead of dropping a patch.
"""
mutable struct WebConnection
    ws::Any
    outbox::Channel{String}
    cap::Int
    sendtask::Union{Task,Nothing}
end

WebConnection(ws; cap::Int=512) = WebConnection(ws, Channel{String}(cap), cap, nothing)

"""
    WebWindowState

Per-window incremental-render bookkeeping. `prev_bounds` maps each renderable
unit's `objectid` to the absolute logical bounds at which it was last painted, so
a moved/shrunk unit's vacated pixels can be cleared (old ∪ new). `first_paint`
forces a full `window` message the next time the window is rendered.
"""
mutable struct WebWindowState
    prev_bounds::Dict{UInt,NTuple{4,Int}}
    first_paint::Bool
end
WebWindowState() = WebWindowState(Dict{UInt,NTuple{4,Int}}(), true)

"""
    WebBackend(; host="127.0.0.1", port=8080)

HTTP + WebSocket backend. Serves the browser client and a per-window JSON
draw-list (full windows + incremental patches), and decodes the client's input
events. One client per editor.
"""
mutable struct WebBackend <: Backend
    host::String
    port::Int
    webdir::String
    fontdir::String
    server::Any
    inbound::Channel{Any}                 # decoded EventEnvelopes from the client
    wake_gate::Base.Event                 # autoreset: ends `wait_for_input`, stores a notification that comes first
    conn::Union{WebConnection,Nothing}          # the one live connection
    windows::Dict{Symbol,WebWindowState}  # per-window incremental state
    last_ids::Vector{Symbol}              # window ids sent last frame (for close detection)
    force_full::Bool                      # send every window in full on the next frame
    zoom::Float64                         # the zoom of the display at the last frame sent
    # Where the last pointer event that the editor read put the pointer: the id
    # of its window and the point. `:none` before the first one.
    pointer_window::Symbol
    pointer_x::Int
    pointer_y::Int
    pointer_shapes::Dict{Symbol,Symbol}   # the shape of the pointer sent for each window
end

function WebBackend(; host::AbstractString="127.0.0.1", port::Integer=8080)
    WebBackend(String(host), Int(port), get_web_asset_directory("web"),
               get_web_asset_directory("font"),
               nothing, Channel{Any}(256), Base.Event(true), nothing,
               Dict{Symbol,WebWindowState}(), Symbol[], false, 1.0,
               :none, -1, -1, Dict{Symbol,Symbol}())
end

# The browser draws a screen of windows, and `--backend=web` names it.
get_backend_name(::Type{WebBackend}) = :web
get_backend_output(::Type{WebBackend}) = :windows

"""
    get_web_asset_directory(name, bindir = Sys.BINDIR) -> String

The folder of the shared assets called `name`: `web`, the client that the
browser loads, or `font`, the fonts that every backend measures with. A binary
that a build made carries them in `share/projectured/<name>` beside its
executable, and reads them there. A Julia session reads `asset/<name>` in the
checkout, two levels above this file.
"""
function get_web_asset_directory(name::AbstractString, bindir::AbstractString = Sys.BINDIR)
    bundled = normpath(joinpath(bindir, "..", "share", "projectured", name))
    isdir(bundled) ? bundled : normpath(joinpath(@__DIR__, "..", "..", "..", "asset", name))
end

# ════════════════════════════════════════════════════════════════════════
# Key mapping (server-side; the key names of sdl_keysym_to_symbol)
# ════════════════════════════════════════════════════════════════════════

"""
    convert_web_key_to_symbol(key, code, mods) -> Symbol

Map a browser `KeyboardEvent.key` (+ `code` for left/right modifier identity)
to the backend-agnostic key vocabulary, with the names that `sdl_keysym_to_symbol`
gives. The browser reports the character that a key types, so a character that
SDL names only on the keypad, such as `*`, has its name here on every key.
A letter key `a` to `z` or `A` to `Z` has the name of its lower-case letter,
`:a` to `:z`. Printable keys whose specific identity is not tracked return
`:char` (the character itself arrives separately via a `keypress` → `KeyPress`).
"""
function convert_web_key_to_symbol(key::AbstractString, code::AbstractString, mods::ModifierKeys)::Symbol
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
        c == ',' && return :comma
        c == '/' && return :slash
        c == '\\' && return :backslash
        c == '*' && return :asterisk
        c == '[' && return :left_bracket
        c == ']' && return :right_bracket
        (c == '=' || c == '+') && return :equals
        c == '-' && return :minus
        c == '0' && return :zero          # Ctrl+0 — reset transform/zoom
        lc = lowercase(c)
        'a' <= lc <= 'z' && return Symbol(lc)
        return :char
    end
    return :char
end

# ════════════════════════════════════════════════════════════════════════
# Draw-list serialization (mirrors Sdl's _dispatch_render_elem!)
# ════════════════════════════════════════════════════════════════════════

# Convert a domain `StyleColor` (Float64 RGBA in [0,1]) to the 0–255 int array the
# browser draw-list consumes (it builds a CSS `rgba()` from it).
_rgba(c::StyleColor) = Int[round(Int, c.red * 255), round(Int, c.green * 255),
                           round(Int, c.blue * 255), round(Int, c.alpha * 255)]
_font_family(path::AbstractString) = splitext(basename(path))[1]

# A canvas's element list in render order: the `ListNode` prev-chain (nearest the
# head first), then the head and its next-chain — matching `_render_canvas!`.
function _list_nodes(head::ListNode)
    nodes = ListNode[]
    pn = head.prev
    while pn !== nothing
        push!(nodes, pn); pn = pn.prev
    end
    node = head
    while node !== nothing
        push!(nodes, node); node = node.next
    end
    nodes
end

# Serialize one element into a draw-list node, or `nothing` to skip it.
function _serialize_node(elem)
    if elem isa GraphicsText
        font = elem.font::StyleFont
        text = elem.text
        # The browser draws what the layout measured: each character at its pen
        # position, on the baseline of the text's box, in the fallback order of
        # the font. So its own kerning and ligatures, which neither the layout nor
        # the other backends apply, never move a glyph.
        _, ascent, _ = compute_text_extent(text, font)
        offsets = compute_caret_offsets(FontFileMeasure(), text, font)
        path = compute_font_path(font)
        families = [_font_family(path);
                    [_font_family(file) for file in get_fallback_font_files(font)]]
        return Dict("t" => "text", "x" => Int(elem.x), "y" => Int(elem.y), "b" => ascent,
                    "s" => text, "o" => round.(offsets; digits = 2), "f" => families,
                    "sz" => font_logical_size(font), "c" => _rgba(elem.color))
    elseif elem isa GraphicsRect
        return Dict("t" => "rect", "x" => Int(elem.x), "y" => Int(elem.y),
                    "w" => Int(elem.w), "h" => Int(elem.h), "c" => _rgba(elem.color),
                    "rtl" => Int(elem.radius_tl), "rtr" => Int(elem.radius_tr),
                    "rbr" => Int(elem.radius_br), "rbl" => Int(elem.radius_bl),
                    "bw" => Int(elem.border_width), "bc" => _rgba(elem.border_color))
    elseif elem isa GraphicsLine
        d = Dict("t" => "line", "x1" => Int(elem.x1), "y1" => Int(elem.y1),
                 "x2" => Int(elem.x2), "y2" => Int(elem.y2),
                 "c" => _rgba(elem.color), "w" => Int(elem.width))
        elem.dash === nothing || (d["dash"] = [Int(elem.dash[1]), Int(elem.dash[2])])
        return d
    elseif elem isa GraphicsCircle
        return Dict("t" => "circle", "cx" => Int(elem.cx), "cy" => Int(elem.cy),
                    "r" => Int(elem.radius), "c" => _rgba(elem.color),
                    "bw" => Int(elem.border_width), "bc" => _rgba(elem.border_color))
    elseif elem isa GraphicsArc
        return Dict("t" => "arc", "cx" => Int(elem.cx), "cy" => Int(elem.cy),
                    "r" => Int(elem.radius), "w" => Int(elem.width),
                    "start" => Float64(elem.start_angle), "sweep" => Float64(elem.sweep_angle),
                    "c" => _rgba(elem.color))
    elseif elem isa GraphicsPolyline
        pts = [[Int(p[1]), Int(p[2])] for p in elem.points]
        d = Dict("t" => "polyline", "pts" => pts, "c" => _rgba(elem.color),
                 "w" => Int(elem.width),
                 "sa" => elem.start_arrow, "ea" => elem.end_arrow,
                 "as" => Int(elem.arrow_size))
        elem.dash === nothing || (d["dash"] = [Int(elem.dash[1]), Int(elem.dash[2])])
        return d
    elseif elem isa GraphicsPolygon
        pts = [[Int(p[1]), Int(p[2])] for p in elem.points]
        return Dict("t" => "polygon", "pts" => pts, "c" => _rgba(elem.color),
                    "bw" => Int(elem.border_width), "bc" => _rgba(elem.border_color))
    elseif elem isa GraphicsSpline
        # Tessellate server-side so the browser only needs the polyline path.
        tess = tessellate_spline(elem.points, elem.kind, elem.segments)
        pts = [[round(Int, p[1]), round(Int, p[2])] for p in tess]
        d = Dict("t" => "polyline", "pts" => pts, "c" => _rgba(elem.color),
                 "w" => Int(elem.width),
                 "sa" => elem.start_arrow, "ea" => elem.end_arrow,
                 "as" => Int(elem.arrow_size))
        elem.dash === nothing || (d["dash"] = [Int(elem.dash[1]), Int(elem.dash[2])])
        return d
    elseif elem isa GraphicsViewport
        content = elem.content::GraphicsCanvas
        d = Dict("t" => "clip", "x" => Int(elem.x), "y" => Int(elem.y),
                 "w" => Int(elem.w), "h" => Int(elem.h),
                 "ox" => Int(content.x), "oy" => Int(content.y),
                 "content" => _serialize_children(content))
        _add_transform!(d, elem.transform)
        return d
    elseif elem isa GraphicsCanvas
        return Dict("t" => "group", "x" => Int(elem.x), "y" => Int(elem.y),
                    "content" => _serialize_children(elem))
    elseif elem isa GraphicsImage
        return _serialize_image(elem)
    end
    return nothing  # GraphicsFence / unknown
end

# A viewport's affine transform, emitted as the canvas matrix [a,b,c,d,e,f]
# (matches `CanvasRenderingContext2D.transform`). Omitted for the identity so
# ordinary scrolling viewports carry no extra payload and older clients ignore it.
function _add_transform!(d::Dict, M::AffineTransform)
    M === affine_identity && return d
    (M.a == 1.0 && M.b == 0.0 && M.c == 0.0 && M.d == 1.0 && M.e == 0.0 && M.f == 0.0) && return d
    d["m"] = Float64[M.a, M.b, M.c, M.d, M.e, M.f]
    d
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

# Serialize a canvas's full element list (the top-level window content is painted
# at origin like SDL's `_render_canvas!(…, 0, 0, …)`, so its own x/y are ignored).
function _serialize_children(canvas::GraphicsCanvas)
    out = Any[]
    elements = canvas.elements
    if elements isa ListNode
        for node in _list_nodes(elements)
            n = _serialize_node(node.value)
            n === nothing || push!(out, n)
        end
    else
        for elem in elements
            n = _serialize_node(elem)
            n === nothing || push!(out, n)
        end
    end
    out
end

# ── Clipped serialization (phase 2) ──────────────────────────────────────
#
# Like `_serialize_children`, but only emits primitives whose absolute bounds
# intersect `clip` (an (x, y, w, h) tuple). Groups/viewports are recursed and
# emitted only when they contribute a visible child, so a patch carries just the
# primitives covering the dirty region.

_intersects(b, clip) =
    b[1] < clip[1] + clip[3] && b[3] > clip[1] && b[2] < clip[2] + clip[4] && b[4] > clip[2]

function _serialize_clipped(canvas::GraphicsCanvas, ox::Int, oy::Int, clip)
    out = Any[]
    elements = canvas.elements
    if elements isa ListNode
        for node in _list_nodes(elements)
            n = _serialize_node_clipped(node.value, ox, oy, clip)
            n === nothing || push!(out, n)
        end
    else
        for elem in elements
            n = _serialize_node_clipped(elem, ox, oy, clip)
            n === nothing || push!(out, n)
        end
    end
    out
end

function _serialize_node_clipped(elem, ox::Int, oy::Int, clip)
    elem isa GraphicsFence && return nothing
    if elem isa GraphicsCanvas
        children = _serialize_clipped(elem, ox + Int(elem.x), oy + Int(elem.y), clip)
        isempty(children) && return nothing
        return Dict("t" => "group", "x" => Int(elem.x), "y" => Int(elem.y), "content" => children)
    elseif elem isa GraphicsViewport
        vx, vy = ox + Int(elem.x), oy + Int(elem.y)
        vw, vh = Int(elem.w), Int(elem.h)
        _intersects((vx, vy, vx + vw, vy + vh), clip) || return nothing
        # Under a non-identity transform the content's *untransformed* bounds no
        # longer line up with the screen-space clip, so per-element culling would
        # be wrong. Serialize the whole viewport (the transform is applied
        # client-side); correct, just a larger patch.
        elem.transform !== affine_identity && return _serialize_node(elem)
        content = elem.content::GraphicsCanvas
        children = _serialize_clipped(content, vx + Int(content.x), vy + Int(content.y), clip)
        isempty(children) && return nothing
        d = Dict("t" => "clip", "x" => Int(elem.x), "y" => Int(elem.y),
                 "w" => vw, "h" => vh, "ox" => Int(content.x), "oy" => Int(content.y),
                 "content" => children)
        _add_transform!(d, elem.transform)
        return d
    else
        b = _bounds_of_elem(elem, ox, oy)
        b === nothing && return nothing
        _intersects(b, clip) || return nothing
        return _serialize_node(elem)
    end
end

# ════════════════════════════════════════════════════════════════════════
# Dirty-rectangle analysis (phase 2)
# ════════════════════════════════════════════════════════════════════════
#
# Walk the window's content canvas the way the renderer does, but test each
# unit's reactive `is_cell_up_to_date` flag *before* reading its value (reading
# recomputes). Stale computed-container cells (a canvas's `elements`, a
# CellVector's backing vector, a ListNode's spine) mark a whole subtree dirty;
# a leaf whose own field cell is stale (in-place mutation) is a tight dirty unit.
# For each dirty unit we union its previous painted bounds with its new bounds so
# moved/shrunk content clears its vacated pixels.

function _bounds_of_elem(elem, ox::Int, oy::Int)
    get_content_box(extend_element_bounds!(ContentBounds(), elem, (ox, oy)))
end

_bounds_of_canvas(canvas::GraphicsCanvas, ox::Int, oy::Int) =
    get_content_box(extend_canvas_bounds!(ContentBounds(), canvas, (ox, oy)))

function _bounds_of_listnode(head::ListNode, ox::Int, oy::Int)
    bounds = ContentBounds()
    for n in _list_nodes(head)
        extend_element_bounds!(bounds, n.value, (ox, oy))
    end
    get_content_box(bounds)
end

# True if any of `elem`'s own visual field cells is stale. A view state field is
# the reader's (not rendered); `:prev`/`:next` are the list spine (handled
# separately) — so they never force a repaint on their own.
function _node_dirty(elem)::Bool
    for f in fieldnames(typeof(elem))
        (is_view_state_field(f) || f === :prev || f === :next) && continue
        c = getfield(elem, f)
        c isa Cell || continue
        is_cell_up_to_date(c) || return true
    end
    false
end

function _union_unit!(acc::ContentBounds, prev::Dict{UInt,NTuple{4,Int}}, key::UInt,
                      newb::Union{Nothing,NTuple{4,Int}})
    old = get(prev, key, nothing)
    old === nothing || extend_content_bounds!(acc, old)
    if newb === nothing
        delete!(prev, key)
    else
        extend_content_bounds!(acc, newb)
        prev[key] = newb
    end
end

# `include_xy` is false for the top-level window content (rendered at origin, so
# its own x/y cells are never read and must not trigger a repaint).
function _collect_canvas_dirty!(canvas::GraphicsCanvas, ox::Int, oy::Int,
                                acc::ContentBounds, prev::Dict{UInt,NTuple{4,Int}};
                                include_xy::Bool=true)
    ec = getfield(canvas, :elements)
    cd = !is_cell_up_to_date(ec)
    if include_xy && !cd
        cd = !is_cell_up_to_date(getfield(canvas, :x)) || !is_cell_up_to_date(getfield(canvas, :y))
    end
    ev = canvas.elements                      # read after capturing validity above
    if !cd && ev isa CellVector && !is_cell_up_to_date(getfield(ev, :elements))
        cd = true
    end
    if cd
        _union_unit!(acc, prev, objectid(canvas), _bounds_of_canvas(canvas, ox, oy))
        return
    end
    if ev isa ListNode
        _collect_listnode_dirty!(ev, ox, oy, acc, prev)
    else
        for elem in ev
            _collect_elem_dirty!(elem, ox, oy, acc, prev)
        end
    end
    nothing
end

# A spine change (line inserted/removed) reflows the list, so the whole list is
# one dirty unit; otherwise each node's value is checked individually.
function _collect_listnode_dirty!(head::ListNode, ox::Int, oy::Int,
                                  acc::ContentBounds, prev::Dict{UInt,NTuple{4,Int}})
    nodes = _list_nodes(head)
    for n in nodes
        if !is_cell_up_to_date(getfield(n, :next)) || !is_cell_up_to_date(getfield(n, :prev))
            _union_unit!(acc, prev, objectid(head), _bounds_of_listnode(head, ox, oy))
            return
        end
    end
    for n in nodes
        _collect_elem_dirty!(n.value, ox, oy, acc, prev)
    end
    nothing
end

function _collect_elem_dirty!(elem, ox::Int, oy::Int,
                              acc::ContentBounds, prev::Dict{UInt,NTuple{4,Int}})
    elem isa GraphicsFence && return
    if elem isa GraphicsCanvas
        _collect_canvas_dirty!(elem, ox + Int(elem.x), oy + Int(elem.y), acc, prev)
    elseif elem isa GraphicsViewport
        vx, vy = ox + Int(elem.x), oy + Int(elem.y)
        vw, vh = Int(elem.w), Int(elem.h)
        if _node_dirty(elem)
            _union_unit!(acc, prev, objectid(elem), (vx, vy, vx + vw, vy + vh))
            return
        end
        content = elem.content::GraphicsCanvas
        tmp = ContentBounds()
        _collect_canvas_dirty!(content, vx + Int(content.x), vy + Int(content.y), tmp, prev)
        get_content_box(tmp) === nothing && return
        ix0 = max(tmp.minx, vx); iy0 = max(tmp.miny, vy)
        ix1 = min(tmp.maxx, vx + vw); iy1 = min(tmp.maxy, vy + vh)
        (ix1 > ix0 && iy1 > iy0) && extend_content_bounds!(acc, (ix0, iy0, ix1, iy1))
    elseif _node_dirty(elem)
        _union_unit!(acc, prev, objectid(elem), _bounds_of_elem(elem, ox, oy))
    end
    nothing
end

# Compute the dirty rectangle (x, y, w, h) for a window's content, or `nothing`
# if nothing changed. Padded by 2px and clamped to the visible quadrant.
function _collect_window_dirty(content::GraphicsCanvas, prev::Dict{UInt,NTuple{4,Int}})
    acc = ContentBounds()
    _collect_canvas_dirty!(content, 0, 0, acc, prev; include_xy=false)
    get_content_box(acc) === nothing && return nothing
    x0 = max(0, acc.minx - 2); y0 = max(0, acc.miny - 2)
    x1 = acc.maxx + 2; y1 = acc.maxy + 2
    (x1 <= x0 || y1 <= y0) && return nothing
    (x0, y0, x1 - x0, y1 - y0)
end

# Record the painted bounds of every renderable unit, so the first subsequent
# change has a previous extent to union against. Called after a full window send.
function _record_all_bounds!(prev::Dict{UInt,NTuple{4,Int}}, canvas::GraphicsCanvas, ox::Int, oy::Int)
    b = _bounds_of_canvas(canvas, ox, oy)
    b === nothing || (prev[objectid(canvas)] = b)
    ev = canvas.elements
    if ev isa ListNode
        lb = _bounds_of_listnode(ev, ox, oy)
        lb === nothing || (prev[objectid(ev)] = lb)
        for n in _list_nodes(ev)
            _record_elem_bounds!(prev, n.value, ox, oy)
        end
    else
        for elem in ev
            _record_elem_bounds!(prev, elem, ox, oy)
        end
    end
    nothing
end

function _record_elem_bounds!(prev::Dict{UInt,NTuple{4,Int}}, elem, ox::Int, oy::Int)
    elem isa GraphicsFence && return
    if elem isa GraphicsCanvas
        _record_all_bounds!(prev, elem, ox + Int(elem.x), oy + Int(elem.y))
    elseif elem isa GraphicsViewport
        vx, vy = ox + Int(elem.x), oy + Int(elem.y)
        prev[objectid(elem)] = (vx, vy, vx + Int(elem.w), vy + Int(elem.h))
        content = elem.content::GraphicsCanvas
        _record_all_bounds!(prev, content, vx + Int(content.x), vy + Int(content.y))
    else
        b = _bounds_of_elem(elem, ox, oy)
        b === nothing || (prev[objectid(elem)] = b)
    end
    nothing
end

# ════════════════════════════════════════════════════════════════════════
# Event decoding (client JSON → WindowInput on the inbound channel)
# ════════════════════════════════════════════════════════════════════════

function _mods(obj)::ModifierKeys
    m = get(obj, :mods, nothing)
    m === nothing && return ModifierKeys()
    ModifierKeys(ctrl = Bool(get(m, :ctrl, false)), shift = Bool(get(m, :shift, false)),
                 alt = Bool(get(m, :alt, false)), meta = Bool(get(m, :meta, false)))
end

# The button of a message, or `nothing` for a name that the event layer does not
# have: left, middle, right, and back and forward, the side buttons.
function _button(obj)::Union{Symbol,Nothing}
    name = get(obj, :button, "left")
    name in ("left", "middle", "right", "back", "forward") ? Symbol(name) : nothing
end

# The buttons that the `buttons` mask of a browser pointer event holds: 1 is the left,
# 2 the right, 4 the middle, 8 the back and 16 the forward button.
_get_held_mouse_buttons(mask::Integer) =
    MouseButtons(left = (mask & 1) != 0, middle = (mask & 4) != 0,
                 right = (mask & 2) != 0, back = (mask & 8) != 0, forward = (mask & 16) != 0)
_winid(obj)::Symbol = haskey(obj, :window) ? Symbol(String(obj[:window])) : :none

# The time of a message on the clock of `time()`. The page sends `t`, the time of
# the browser event in milliseconds since the Unix epoch. A message with no `t`
# has the time when it arrives.
_get_message_time(obj)::Float64 = haskey(obj, :t) ? Float64(obj[:t]) / 1000 : time()

# Decode one client message and enqueue the resulting WindowInput(s). Only raw
# device events are emitted; click (`MouseClick`) synthesis from a MouseDown/
# MouseUp pair is the job of the gesture tracking projection, not the backend's
# (mirrors `SdlBackend`). A click made here too would reach a reader twice, and a
# toggle, such as the fold of a card, would flip back at once.
function _decode_and_enqueue!(backend::WebBackend, msg)
    obj = JSON3.read(msg)
    typ = String(obj[:type])
    wid = _winid(obj)
    at = _get_message_time(obj)

    if typ == "mousedown"
        b = _button(obj); x = Int(obj[:x]); y = Int(obj[:y])
        b === nothing && return
        put!(backend.inbound, WindowInput(wid, MouseDown(b, x, y, _mods(obj); time = at)))

    elseif typ == "mouseup"
        b = _button(obj); x = Int(obj[:x]); y = Int(obj[:y]); m = _mods(obj)
        b === nothing && return
        put!(backend.inbound, WindowInput(wid, MouseUp(b, x, y, m; time = at)))

    elseif typ == "mousemove"
        # Every move: the client sends a move with no button held at most once
        # per animation frame, and a move with a button held at once.
        mask = Int(get(obj, :buttons, 0))
        put!(backend.inbound, WindowInput(wid,
            MouseMove(Int(obj[:x]), Int(obj[:y]), _get_held_mouse_buttons(mask),
                      _mods(obj); time = at)))

    elseif typ == "scroll"
        put!(backend.inbound, WindowInput(wid,
            MouseScroll(Int(obj[:dx]), Int(obj[:dy]), Int(obj[:x]), Int(obj[:y]), _mods(obj);
                        time = at)))

    elseif typ == "keydown"
        m = _mods(obj)
        key = String(obj[:key])
        # Escape is an ordinary key here, as it is in the SDL backend: a backend
        # reports what happened and decides no meaning. The editor loop quits on an
        # Escape that no reader handled.
        sym = convert_web_key_to_symbol(key, String(get(obj, :code, "")), m)
        repeat = Bool(get(obj, :repeat, false))
        put!(backend.inbound, WindowInput(wid, KeyDown(sym, m; repeat, time = at)))

    elseif typ == "keyup"
        m = _mods(obj)
        sym = convert_web_key_to_symbol(String(obj[:key]), String(get(obj, :code, "")), m)
        put!(backend.inbound, WindowInput(wid, KeyUp(sym, m; time = at)))

    elseif typ == "keypress"
        text = String(obj[:text])
        isempty(text) && return
        put!(backend.inbound, WindowInput(wid, KeyPress(first(text), text, _mods(obj);
                                                        time = at)))

    elseif typ == "resize"
        put!(backend.inbound, WindowInput(wid, WindowResize(Int(obj[:w]), Int(obj[:h]);
                                                            time = at)))

    elseif typ == "close"
        put!(backend.inbound, WindowInput(wid, WindowClose(; time = at)))

    elseif typ == "blur"
        put!(backend.inbound, WindowInput(wid, WindowDefocus(; time = at)))

    elseif typ == "leave"
        put!(backend.inbound, WindowInput(wid, WindowLeave(; time = at)))

    elseif typ == "quit"
        put!(backend.inbound, WindowInput(:none, WindowQuit(; time = at)))

    elseif typ == "resync"
        # Client (re)launched popups and wants a fresh full state for everything.
        _reset_for_full!(backend)
    end
    # The event is in the channel before the wake, so the wait that the wake
    # ends finds it.
    BackendModule.wake_backend!(backend)
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

# Drain queued messages to the socket in order until the connection closes.
function _send_loop(conn::WebConnection)
    for msg in conn.outbox
        try
            HTTP.WebSockets.isclosed(conn.ws) && break
            HTTP.WebSockets.send(conn.ws, msg)
        catch
            break
        end
    end
end

# Enqueue a frame message in order. A `snapshot` (the force_full path: every
# window in full, no patches) supersedes the backlog, so the queue is drained
# first. On overflow we likewise drain and arm a forced resend next frame — the
# imminent snapshot makes the dropped patches obsolete, so nothing is lost. A
# normal incremental message is only appended, never dropping a queued patch.
function _enqueue!(backend::WebBackend, conn::WebConnection, msg::String, snapshot::Bool)
    overflow = Base.n_avail(conn.outbox) >= conn.cap - 1
    if snapshot || overflow
        while isready(conn.outbox)
            try; take!(conn.outbox); catch; break; end
        end
        if overflow
            # The wake ends the next wait, so the full frame comes without an input.
            backend.force_full = true
            BackendModule.wake_backend!(backend)
        end
    end
    try; put!(conn.outbox, msg); catch; end
    return
end

# Force the next frame to send every window in full (on connect / resync).
# Clearing per-window state drops stale incremental bookkeeping. The wake ends
# a wait of the editor, so that the frame comes without an input. Queue
# overflow (`_enqueue!`) sets `force_full` and wakes the backend directly,
# without clearing this per-window state.
function _reset_for_full!(backend::WebBackend)
    empty!(backend.windows)
    empty!(backend.pointer_shapes)
    backend.last_ids = Symbol[]
    backend.force_full = true
    BackendModule.wake_backend!(backend)
    return
end

function _handle_ws(backend::WebBackend, ws)
    # One client per editor: reject a second connection.
    if backend.conn !== nothing
        try; HTTP.WebSockets.send(ws, JSON3.write(Dict("type" => "busy"))); catch; end
        return
    end
    conn = WebConnection(ws)
    backend.conn = conn
    _reset_for_full!(backend)
    conn.sendtask = @async _send_loop(conn)
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
        try; close(conn.outbox); catch; end
        backend.conn === conn && (backend.conn = nothing)
    end
    return
end

# ════════════════════════════════════════════════════════════════════════
# Backend interface
# ════════════════════════════════════════════════════════════════════════

function BackendModule.initialize_backend!(backend::WebBackend)
    # Text metrics come from the pure-Julia font file measure (FontFileMeasure),
    # so no SDL/SDL_ttf initialisation is needed — the web backend is SDL-free.
    backend.server = HTTP.listen!(backend.host, backend.port) do http
        if HTTP.WebSockets.isupgrade(http.message)
            HTTP.WebSockets.upgrade(ws -> _handle_ws(backend, ws), http)
        else
            _serve_static(backend, http)
        end
    end
    # PROGRAM OUTPUT, and not a log: it is the only way to learn where to point a
    # browser, and a binary that logs from `warn` and up would swallow a `@info`.
    # A raw write is safe here and not in the editor loop — `initialize_backend!`
    # runs once, before the assistant has a task that redirects `stdout`.
    println(stdout, "Web backend listening on http://$(backend.host):$(backend.port)")
    return nothing
end

function BackendModule.quit_backend!(backend::WebBackend)
    conn = backend.conn
    if conn !== nothing
        try; close(conn.outbox); catch; end
        try; close(conn.ws); catch; end
        backend.conn = nothing
    end
    if backend.server !== nothing
        try; close(backend.server); catch; end
        backend.server = nothing
    end
    return nothing
end

# Non-blocking poll: hand back the next decoded event, or nothing. A pointer event
# puts the pointer where the next frame finds the shape of the pointer.
function BackendModule.take_from_devices!(backend::WebBackend, devices)
    isready(backend.inbound) || return nothing
    input = take!(backend.inbound)
    _track_pointer!(backend, input)
    input
end

function _track_pointer!(backend::WebBackend, input)
    input isa WindowInput || return nothing
    event = input.event
    event isa Union{MouseMove,MouseDown,MouseUp,MouseScroll} || return nothing
    backend.pointer_window = input.window_id
    backend.pointer_x = event.x
    backend.pointer_y = event.y
    nothing
end

"""
    wait_for_input(backend::WebBackend, devices, timeout_seconds) -> Nothing

Block until the receive task puts an event into `inbound`, [`wake_backend!`](@ref)
is called, or `timeout_seconds` passes. An event already in `inbound` ends the
wait before it starts. The receive task wakes the backend after each message
that it decodes, and a new connection wakes it too, because the frame after it
sends every window in full. Everything here is a cooperative Julia wait; no
thread blocks.
"""
function BackendModule.wait_for_input(backend::WebBackend, devices, timeout_seconds)
    if isready(backend.inbound)
        # The frame after this wait reads every event in `inbound`, so the
        # notifications of those events are spent.
        reset(backend.wake_gate)
        return nothing
    end
    _wait_for_gate(backend.wake_gate, timeout_seconds)
    return nothing
end

"""
    wake_backend!(backend::WebBackend) -> Nothing

End a [`wait_for_input`](@ref) in progress, from any task or thread. The
autoreset gate stores a notification that arrives before the wait, so a wake
can not slip between the check of `inbound` and the block.
"""
BackendModule.wake_backend!(backend::WebBackend) =
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

# `primary` marks the in-tab window (the first `WindowDocument` in list order):
# the client renders it directly in the page it was opened from, never a popup.
_window_meta(w::WindowDocument, draw; primary::Bool=false) = Dict(
    "id" => String(w.id), "title" => w.title, "primary" => primary,
    "x" => Int(w.x), "y" => Int(w.y), "w" => Int(w.width), "h" => Int(w.height),
    "bg" => Int[Int(w.bg[1]), Int(w.bg[2]), Int(w.bg[3]), Int(w.bg[4])],
    "style" => String(w.style), "draw" => draw)

"""
    write_to_devices!(backend::WebBackend, devices, screen::ScreenDocument)

Reconcile the connected client against the projection-output `ScreenDocument`.
A window is sent in full on first paint / after a forced resync; otherwise only a
`patch` covering the reactive dirty rectangle is sent. Windows that disappeared
are closed. The message is
`{type:"update", zoom:…, full:[…], patches:[…], close:[…]}`; nothing is sent when
no client is connected or no window changed.

After it, the frame sends `{type:"pointer", window:…, cursor:…}` when the shape
that `find_pointer_shape` finds at the pointer, in the window of the last pointer
event that the editor read, is another one than the shape sent for that window.
`cursor` is the CSS cursor of the shape, which the client sets on the canvas of
the window.

`zoom` is the zoom of the `Display` in `devices`, or 1 with none. The client draws
each logical pixel as `devicePixelRatio × zoom` pixels of the page, reports the
size of each window divided by the zoom, and divides each pointer position by it,
so the server lays out and reads in logical pixels at every zoom. A new zoom sends
every window in full, because the client draws it again at the new ratio.
"""
function BackendModule.write_to_devices!(backend::WebBackend, devices, screen::ScreenDocument)
    conn = backend.conn
    conn === nothing && return nothing  # no client; a resync on (re)connect sends full

    wins = WindowDocument[]
    for w in screen.windows
        w isa WindowDocument && push!(wins, w)
    end
    ids = Symbol[w.id for w in wins]

    closed = String[]
    for id in backend.last_ids
        (id in ids) || (push!(closed, String(id)); delete!(backend.windows, id))
    end
    backend.last_ids = ids

    zoom = _get_display_zoom(devices)
    force = backend.force_full || zoom != backend.zoom
    backend.force_full = false
    backend.zoom = zoom
    force && empty!(backend.pointer_shapes)
    foreach(id -> delete!(backend.pointer_shapes, Symbol(id)), closed)

    # The first window in list order is the primary (in-tab) one; the client
    # renders it in the page it was opened from rather than a popup.
    primary_id = isempty(wins) ? :none : wins[1].id

    full = Any[]
    patches = Any[]
    for w in wins
        ws = get!(WebWindowState, backend.windows, w.id)
        content = w.content
        if force || ws.first_paint
            draw = content isa GraphicsCanvas ? _serialize_children(content) : Any[]
            push!(full, _window_meta(w, draw; primary = (w.id == primary_id)))
            ws.first_paint = false
            empty!(ws.prev_bounds)
            content isa GraphicsCanvas && _record_all_bounds!(ws.prev_bounds, content, 0, 0)
        elseif content isa GraphicsCanvas
            clip = _collect_window_dirty(content, ws.prev_bounds)
            clip === nothing || push!(patches, Dict(
                "window" => String(w.id),
                "clip" => Int[clip[1], clip[2], clip[3], clip[4]],
                "draw" => _serialize_clipped(content, 0, 0, clip)))
        end
    end

    pointer = _make_pointer_message(backend, wins)
    if !(isempty(full) && isempty(patches) && isempty(closed))
        msg = JSON3.write(Dict("type" => "update", "zoom" => zoom, "full" => full,
                               "patches" => patches, "close" => closed))
        # `force` ⇒ a complete snapshot (all windows full, no patches), safe to
        # drain the backlog against; otherwise append in order.
        _enqueue!(backend, conn, msg, force)
    end
    pointer === nothing || _enqueue!(backend, conn, pointer, false)
    return nothing
end

# The CSS cursor of each shape of the pointer. `:default` and a shape that this
# table does not name are the arrow.
const _CSS_CURSOR_OF_SHAPE = Dict{Symbol,String}(
    :arrow => "default", :ibeam => "text",
    :double_arrow_horizontal => "col-resize", :double_arrow_vertical => "row-resize",
    :pointing_hand => "pointer", :open_hand => "grab", :closed_hand => "grabbing",
    :crossed_circle => "not-allowed", :hourglass => "wait")

# The message that gives the canvas of the window under the pointer the cursor of
# the shape at the pointer, or `nothing` when that window shows it already.
function _make_pointer_message(backend::WebBackend, windows::Vector{WindowDocument})
    id = backend.pointer_window
    index = findfirst(w -> w.id === id, windows)
    index === nothing && return nothing
    content = windows[index].content
    content isa GraphicsCanvas || return nothing
    shape = find_pointer_shape(content, backend.pointer_x, backend.pointer_y)
    get(backend.pointer_shapes, id, nothing) === shape && return nothing
    backend.pointer_shapes[id] = shape
    JSON3.write(Dict("type" => "pointer", "window" => String(id),
                     "cursor" => get(_CSS_CURSOR_OF_SHAPE, shape, "default")))
end

# The zoom of the first `Display` in `devices`, or 1 with none.
function _get_display_zoom(devices)
    for device in devices
        device isa Display && return Float64(device.zoom)
    end
    1.0
end

# Fail loud on a miswired pipeline whose output is not a ScreenDocument.
function BackendModule.write_to_devices!(::WebBackend, devices, output)
    error("write_to_devices!(::WebBackend, …): pipeline output is $(typeof(output)), " *
          "expected a ScreenDocument. The web backend renders the multi-window " *
          "screen pipeline (same as the SDL backend).")
end
