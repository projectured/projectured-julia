"""
    Web

Opt-in package: the HTTP/WebSocket web backend (browser-rendered editor). Depends
on `ProjecturedDomain` + HTTP/JSON3; `using ProjecturedWeb` exports `WebBackend`
(construct it directly). SDL-free — reuses the pure-Julia TrueType text metrics.
Relocated from the former program/src/backend/Web.jl (WebBackendModule).
"""
module ProjecturedWeb

using ProjecturedDomain


using HTTP
using JSON3
using Base64: base64encode

# The backend contract (AR-QUALIFIED-EXTENSION): bare `using`, extended by
# qualification below. A bare `using` of an alias binds the module's *real*
# name, so the extension sites read BackendModule.*.
using ProjecturedDomain.BackendApiModule
import ProjecturedDomain.GraphicsModule: GraphicsCanvas, GraphicsText, GraphicsRect, GraphicsLine,
                         GraphicsCircle, GraphicsPolyline, GraphicsPolygon, GraphicsSpline,
                         GraphicsViewport, GraphicsImage, GraphicsFence,
                         _bounds_elem!, _accumulate_bounds!, tessellate_spline
import ProjecturedDomain.CollectionModule: ListNode, CellVector, ComputedCellVector
import ProjecturedDomain.ColorModule: StyleColor
import ProjecturedDomain.GeometryModule: AffineTransform, affine_identity
import ProjecturedDomain.FontModule: StyleFont, font_logical_size
import ProjecturedDomain.CellModule: Cell, ComputedCell, is_cell_up_to_date
import ProjecturedDomain.EventModule: WindowInput, ModifierKeys,
                               WindowQuit, WindowClose, WindowResize, WindowDefocus
import ProjecturedDomain.ScreenDocumentModule: ScreenDocument, WindowDocument
import ProjecturedDomain.EventModule: KeyDown, KeyUp, KeyPress
import ProjecturedDomain.EventModule: MouseDown, MouseUp, MouseMove, MouseScroll
# SDL-free text measurement: reuse the pure-Julia TrueType metrics measurer from
# the SDL-free TrueType measurer, so the web backend needs no SDL/SDL_ttf at all.
# `truetype_measure_text` is the shared font-metrics utility (TrueTypeModule),
# also used by the PDF backend and every projection example.
import ProjecturedDomain.TrueTypeModule: truetype_measure_text

export WebBackend, web_key_to_symbol

# ════════════════════════════════════════════════════════════════════════
# Connection + backend state
# ════════════════════════════════════════════════════════════════════════

"""
    WebConn

The single live WebSocket connection. `outbox` is an in-order FIFO of JSON
messages drained by the send task. Patches are order-sensitive, so the queue is
never coalesced; when it nears capacity the backend falls back to a full resend
(`force_full`) instead of dropping a patch.
"""
mutable struct WebConn
    ws::Any
    outbox::Channel{String}
    cap::Int
    sendtask::Union{Task,Nothing}
end

WebConn(ws; cap::Int=512) = WebConn(ws, Channel{String}(cap), cap, nothing)

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
    conn::Union{WebConn,Nothing}          # the one live connection
    windows::Dict{Symbol,WebWindowState}  # per-window incremental state
    last_ids::Vector{Symbol}              # window ids sent last frame (for close detection)
    force_full::Bool                      # send every window in full on the next frame
end

function WebBackend(; host::AbstractString="127.0.0.1", port::Integer=8080)
    # Paths relative to this package's main/ (web/main/): web assets at web/assets,
    # fonts at the shared <repo-root>/font.
    webdir  = normpath(joinpath(@__DIR__, "..", "assets"))
    fontdir = normpath(joinpath(@__DIR__, "..", "..", "..", "asset", "font"))
    WebBackend(String(host), Int(port), webdir, fontdir,
               nothing, Channel{Any}(256), nothing,
               Dict{Symbol,WebWindowState}(), Symbol[], false)
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
function web_key_to_symbol(key::AbstractString, code::AbstractString, mods::ModifierKeys)::Symbol
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
        c == '0' && return :zero          # Ctrl+0 — reset transform/zoom
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
        return Dict("t" => "text", "x" => Int(elem.x), "y" => Int(elem.y),
                    "s" => elem.text, "f" => _font_family(font.filename),
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

mutable struct _DAcc
    minx::Int; miny::Int; maxx::Int; maxy::Int
end
_DAcc() = _DAcc(typemax(Int), typemax(Int), typemin(Int), typemin(Int))
_acc_empty(a::_DAcc) = a.maxx == typemin(Int)
_extend!(a::_DAcc, b) = (a.minx = min(a.minx, b[1]); a.miny = min(a.miny, b[2]);
                         a.maxx = max(a.maxx, b[3]); a.maxy = max(a.maxy, b[4]); nothing)

function _bounds_of_elem(elem, ox::Int, oy::Int)
    mnx = Ref(typemax(Int)); mny = Ref(typemax(Int)); mxx = Ref(typemin(Int)); mxy = Ref(typemin(Int))
    _bounds_elem!(elem, ox, oy, truetype_measure_text, mnx, mny, mxx, mxy)
    mxx[] == typemin(Int) ? nothing : (mnx[], mny[], mxx[], mxy[])
end

function _bounds_of_canvas(canvas::GraphicsCanvas, ox::Int, oy::Int)
    mnx = Ref(typemax(Int)); mny = Ref(typemax(Int)); mxx = Ref(typemin(Int)); mxy = Ref(typemin(Int))
    _accumulate_bounds!(canvas, ox, oy, truetype_measure_text, mnx, mny, mxx, mxy)
    mxx[] == typemin(Int) ? nothing : (mnx[], mny[], mxx[], mxy[])
end

function _bounds_of_listnode(head::ListNode, ox::Int, oy::Int)
    mnx = Ref(typemax(Int)); mny = Ref(typemax(Int)); mxx = Ref(typemin(Int)); mxy = Ref(typemin(Int))
    for n in _list_nodes(head)
        _bounds_elem!(n.value, ox, oy, truetype_measure_text, mnx, mny, mxx, mxy)
    end
    mxx[] == typemin(Int) ? nothing : (mnx[], mny[], mxx[], mxy[])
end

# True if any of `elem`'s own visual field cells is stale. `:selection` is the
# reader's reference (not rendered); `:prev`/`:next` are the list spine (handled
# separately) — so they never force a repaint on their own.
function _node_dirty(elem)::Bool
    for f in fieldnames(typeof(elem))
        (f === :selection || f === :prev || f === :next) && continue
        c = getfield(elem, f)
        c isa Cell || continue
        is_cell_up_to_date(c) || return true
    end
    false
end

function _union_unit!(acc::_DAcc, prev::Dict{UInt,NTuple{4,Int}}, key::UInt,
                      newb::Union{Nothing,NTuple{4,Int}})
    old = get(prev, key, nothing)
    old === nothing || _extend!(acc, old)
    if newb === nothing
        delete!(prev, key)
    else
        _extend!(acc, newb)
        prev[key] = newb
    end
end

# `include_xy` is false for the top-level window content (rendered at origin, so
# its own x/y cells are never read and must not trigger a repaint).
function _collect_canvas_dirty!(canvas::GraphicsCanvas, ox::Int, oy::Int,
                                acc::_DAcc, prev::Dict{UInt,NTuple{4,Int}};
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
                                  acc::_DAcc, prev::Dict{UInt,NTuple{4,Int}})
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
                              acc::_DAcc, prev::Dict{UInt,NTuple{4,Int}})
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
        tmp = _DAcc()
        _collect_canvas_dirty!(content, vx + Int(content.x), vy + Int(content.y), tmp, prev)
        _acc_empty(tmp) && return
        ix0 = max(tmp.minx, vx); iy0 = max(tmp.miny, vy)
        ix1 = min(tmp.maxx, vx + vw); iy1 = min(tmp.maxy, vy + vh)
        (ix1 > ix0 && iy1 > iy0) && _extend!(acc, (ix0, iy0, ix1, iy1))
    elseif _node_dirty(elem)
        _union_unit!(acc, prev, objectid(elem), _bounds_of_elem(elem, ox, oy))
    end
    nothing
end

# Compute the dirty rectangle (x, y, w, h) for a window's content, or `nothing`
# if nothing changed. Padded by 2px and clamped to the visible quadrant.
function _collect_window_dirty(content::GraphicsCanvas, prev::Dict{UInt,NTuple{4,Int}})
    acc = _DAcc()
    _collect_canvas_dirty!(content, 0, 0, acc, prev; include_xy=false)
    _acc_empty(acc) && return nothing
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
    m === nothing && return ModifierKeys(false, false, false, false)
    ModifierKeys(Bool(get(m, :ctrl, false)), Bool(get(m, :shift, false)),
              Bool(get(m, :alt, false)), Bool(get(m, :meta, false)))
end

_button(obj)::Symbol = Symbol(String(get(obj, :button, "left")))
_winid(obj)::Symbol = haskey(obj, :window) ? Symbol(String(obj[:window])) : :none

# Decode one client message and enqueue the resulting WindowInput(s). Only raw
# device events are emitted; click (`MousePress`) synthesis from a MouseDown/
# MouseUp pair is the editor's `GestureRecognizer`'s job, not the backend's
# (mirrors `SdlBackend`). Synthesising it here too made every click toggle/select
# twice — the recogniser's own `MousePress` plus this one — which read as "no
# change" for togglers (e.g. card collapse flips back immediately).
function _decode_and_enqueue!(backend::WebBackend, msg)
    obj = JSON3.read(msg)
    typ = String(obj[:type])
    wid = _winid(obj)

    if typ == "mousedown"
        b = _button(obj); x = Int(obj[:x]); y = Int(obj[:y])
        put!(backend.inbound, WindowInput(wid, MouseDown(b, x, y, _mods(obj))))

    elseif typ == "mouseup"
        b = _button(obj); x = Int(obj[:x]); y = Int(obj[:y]); m = _mods(obj)
        put!(backend.inbound, WindowInput(wid, MouseUp(b, x, y, m)))

    elseif typ == "mousemove"
        buttons = Symbol(String(get(obj, :buttons, "none")))
        buttons === :none && return  # only forward motion while a button is held
        put!(backend.inbound, WindowInput(wid,
            MouseMove(Int(obj[:x]), Int(obj[:y]), buttons, _mods(obj))))

    elseif typ == "scroll"
        put!(backend.inbound, WindowInput(wid,
            MouseScroll(Int(obj[:dx]), Int(obj[:dy]), Int(obj[:x]), Int(obj[:y]), _mods(obj))))

    elseif typ == "keydown"
        m = _mods(obj)
        key = String(obj[:key])
        # Escape is an ordinary key here, as it is in the SDL backend: a backend
        # reports what happened and decides no meaning. The editor loop quits on an
        # Escape that no reader handled.
        sym = web_key_to_symbol(key, String(get(obj, :code, "")), m)
        put!(backend.inbound, WindowInput(wid, KeyDown(sym, m, Bool(get(obj, :repeat, false)))))

    elseif typ == "keyup"
        m = _mods(obj)
        sym = web_key_to_symbol(String(obj[:key]), String(get(obj, :code, "")), m)
        put!(backend.inbound, WindowInput(wid, KeyUp(sym, m)))

    elseif typ == "keypress"
        text = String(obj[:text])
        isempty(text) && return
        put!(backend.inbound, WindowInput(wid, KeyPress(first(text), text, _mods(obj))))

    elseif typ == "resize"
        put!(backend.inbound, WindowInput(wid, WindowResize(Int(obj[:w]), Int(obj[:h]))))

    elseif typ == "close"
        put!(backend.inbound, WindowInput(wid, WindowClose()))

    elseif typ == "blur"
        put!(backend.inbound, WindowInput(wid, WindowDefocus()))

    elseif typ == "quit"
        put!(backend.inbound, WindowInput(:none, WindowQuit()))

    elseif typ == "resync"
        # Client (re)launched popups and wants a fresh full state for everything.
        _reset_for_full!(backend)
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
function _send_loop(conn::WebConn)
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
function _enqueue!(backend::WebBackend, conn::WebConn, msg::String, snapshot::Bool)
    overflow = Base.n_avail(conn.outbox) >= conn.cap - 1
    if snapshot || overflow
        while isready(conn.outbox)
            try; take!(conn.outbox); catch; break; end
        end
        overflow && (backend.force_full = true)
    end
    try; put!(conn.outbox, msg); catch; end
    return
end

# Force the next frame to send every window in full (on connect / resync / queue
# overflow). Clearing per-window state drops stale incremental bookkeeping.
function _reset_for_full!(backend::WebBackend)
    empty!(backend.windows)
    backend.last_ids = Symbol[]
    backend.force_full = true
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
    # Text metrics come from the pure-Julia TrueType measurer (truetype_measure_text),
    # so no SDL/SDL_ttf initialisation is needed — the web backend is SDL-free.
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
    # Intentionally do not TTF_Quit/SDL_Quit: the shared SDL font cache in
    # SdlBackendModule holds open TTF_Font pointers that would dangle. SDL stays
    # initialised for the process lifetime; harmless.
    return nothing
end

# `truetype_measure_text` already measures at the font-zoomed logical size (it reads
# `_FONT_ZOOM` via `font_logical_size`), so web layout reflows with Ctrl+Alt zoom
# for free (no-op at the default font zoom). Web has no display-scale knob — full
# zoom is the browser's own; font zoom rides the backend-agnostic `_FONT_ZOOM` cell.
BackendModule.measure_text(::WebBackend, text::AbstractString, font::StyleFont) =
    truetype_measure_text(text, font)

# Non-blocking poll: hand back the next decoded event, or nothing.
BackendModule.read_from_devices(backend::WebBackend, devices) =
    isready(backend.inbound) ? take!(backend.inbound) : nothing

# `primary` marks the in-tab window (the first `WindowDocument` in list order):
# the client renders it directly in the page it was opened from, never a popup.
_window_meta(w::WindowDocument, draw; primary::Bool=false) = Dict(
    "id" => String(w.id), "title" => w.title, "primary" => primary,
    "x" => Int(w.x), "y" => Int(w.y), "w" => Int(w.width), "h" => Int(w.height),
    "bg" => Int[Int(w.bg[1]), Int(w.bg[2]), Int(w.bg[3]), Int(w.bg[4])],
    "style" => String(w.style), "draw" => draw)

"""
    write_to_devices(backend::WebBackend, devices, screen::ScreenDocument)

Reconcile the connected client against the projection-output `ScreenDocument`.
A window is sent in full on first paint / after a forced resync; otherwise only a
`patch` covering the reactive dirty rectangle is sent. Windows that disappeared
are closed. The message is `{type:"update", full:[…], patches:[…], close:[…]}`;
nothing is sent when no client is connected or no window changed.
"""
function BackendModule.write_to_devices(backend::WebBackend, devices, screen::ScreenDocument)
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

    force = backend.force_full
    backend.force_full = false

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

    (isempty(full) && isempty(patches) && isempty(closed)) && return nothing
    msg = JSON3.write(Dict("type" => "update", "full" => full, "patches" => patches, "close" => closed))
    # `force` ⇒ a complete snapshot (all windows full, no patches), safe to drain
    # the backlog against; otherwise append in order.
    _enqueue!(backend, conn, msg, force)
    return nothing
end

# Fail loud on a miswired pipeline whose output is not a ScreenDocument.
function BackendModule.write_to_devices(::WebBackend, devices, output)
    error("write_to_devices(::WebBackend, …): pipeline output is $(typeof(output)), " *
          "expected a ScreenDocument. The web backend renders the multi-window " *
          "screen pipeline (same as the SDL backend).")
end

end # module Web
