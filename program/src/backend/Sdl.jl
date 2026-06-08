"""
    SdlBackendModule

SDL backend. Implements the abstract backend interface using SDL2 + SDL_ttf.
"""
module SdlBackendModule

using SimpleDirectMediaLayer
using SimpleDirectMediaLayer.LibSDL2
import ..BackendModule: Backend, init!, quit!, measure_text
import ..DeviceModule: Device, read_from_devices, write_to_devices, write_to_device
import ..GraphicsModule: GraphicsCanvas, GraphicsText, GraphicsRect, GraphicsViewport, GraphicsImage,
                         GraphicsFence, LayoutDirection, layout_none, layout_horizontal, layout_vertical
import ..CollectionModule: ListNode
import ..FontModule: StyleFont, font_scaled_size, _FONT_SCALE
import ..ScreenModule: Screen, QuitEvent
import ..ScreenDocumentModule: ScreenDocument, WindowDocument, EventEnvelope, WindowCloseRequest
import ..ModifiersModule: Modifiers
import ..KeyboardModule: KeyDown, KeyUp, KeyPress
import ..MouseModule: MouseDown, MouseUp, MousePress, MouseMove, MouseScroll
import ..ImageModule: ImageFile
import ..ProjectionApiModule: projection_print, Projection
import ..ProjectionContextModule: ProjectionContext
import ..ReactiveModule: Cell
import ..ReferenceModule: EmptyReferencePath
import ..IoMapModule: SimpleIoMap

export SdlBackend, sdl_measure_text, sdl_render_canvas, sdl_display_size,
       write_image, GraphicsCanvasToImageFile,
       sdl_decode_image, decode_image_file!

"""
    sdl_display_size(; display::Integer=0) -> (width, height)

Return the usable size in pixels of the given display (default 0). "Usable"
means with OS-reserved areas like the taskbar / menu bar subtracted —
the right thing for picking a default window size. Falls back to
`(1280, 720)` if SDL cannot answer (no display, headless run, etc.).
The video subsystem is initialized lazily; safe to call before `init!`.
"""
function sdl_display_size(; display::Integer=0)
    SDL_Init(SDL_INIT_VIDEO) == 0 || return (1280, 720)
    rect = Ref(SDL_Rect(Int32(0), Int32(0), Int32(0), Int32(0)))
    rc = SDL_GetDisplayUsableBounds(Int32(display), rect)
    if rc != 0 || rect[].w <= 0 || rect[].h <= 0
        return (1280, 720)
    end
    (Int(rect[].w), Int(rect[].h))
end

# ════════════════════════════════════════════════════════════════════════
# Backend
# ════════════════════════════════════════════════════════════════════════

"""
    SdlWindowResources

Backend-internal record of a live native SDL window plus the matching
`WindowDocument.id` it mirrors. Stored in the backend's `windows`
registry, keyed by `WindowDocument.id`.
"""
mutable struct SdlWindowResources
    win::Ptr{SDL_Window}
    renderer::Ptr{SDL_Renderer}
    id::Symbol           # WindowDocument.id this resource mirrors
    sdl_id::UInt32       # SDL_GetWindowID(win), cached for the reverse map
    title::String        # last applied title — used to skip redundant SDL calls
    width::Int           # last applied size
    height::Int
    x::Int               # last applied position (-1 = not yet positioned)
    y::Int
    style::Symbol        # last applied style
    bg::NTuple{4,UInt8}  # last applied background
end

"""
    SdlBackend()

SDL2 + SDL_ttf backend. Loaded TTF fonts are cached in the module-level
[`_font_cache`](@ref), shared across windows, measurement, and offscreen
image rendering. An internal `pending_events` queue holds synthesised
events (e.g. `MousePress`) scheduled to be delivered on the next poll.

`windows` is the live registry of native SDL windows, keyed by the
`WindowDocument.id` they mirror. `window_ids` is the reverse map from
SDL `windowID` to `WindowDocument.id`, used when translating raw SDL
events into `EventEnvelope`s. Both are reconciled by
`write_to_devices(::SdlBackend, devices, ::ScreenDocument)`.
"""
mutable struct SdlBackend <: Backend
    # Synthesised-event queue: drained before polling SDL.
    pending_events::Vector{Any}
    # State for MousePress synthesis.
    last_down_button::Symbol
    last_down_x::Int
    last_down_y::Int
    last_down_time::Float64
    # Multi-window reconciliation state.
    windows::Dict{Symbol, SdlWindowResources}
    window_ids::Dict{UInt32, Symbol}
end

SdlBackend() = SdlBackend(Any[], :none, 0, 0, 0.0,
                          Dict{Symbol, SdlWindowResources}(),
                          Dict{UInt32, Symbol}())

# Module-level TTF font cache, keyed by (filename, scaled_size).
# Shared by window rendering, offscreen image rendering, and text measurement.
# Populated lazily by `_get_font`; freed by `quit!`.
const _font_cache = Dict{Tuple{String,Int}, Ptr{TTF_Font}}()

# ════════════════════════════════════════════════════════════════════════
# Modifier extraction
# ════════════════════════════════════════════════════════════════════════

"""
    sdl_modifiers(mod::UInt16) -> Modifiers

Decode an SDL modifier bitmask into a `Modifiers` struct.

Bitmask layout (same as SDL_Keymod):
- Ctrl  : bits 6–7   (KMOD_LCTRL=0x0040, KMOD_RCTRL=0x0080)
- Shift : bits 0–1   (KMOD_LSHIFT=0x0001, KMOD_RSHIFT=0x0002)
- Alt   : bits 8–9   (KMOD_LALT=0x0100, KMOD_RALT=0x0200)
- Meta  : bits 10–11 (KMOD_LGUI=0x0400, KMOD_RGUI=0x0800)
"""
function sdl_modifiers(mod::UInt16)::Modifiers
    ctrl  = (mod & UInt16(0x00C0)) != UInt16(0)  # KMOD_LCTRL | KMOD_RCTRL
    shift = (mod & UInt16(0x0003)) != UInt16(0)  # KMOD_LSHIFT | KMOD_RSHIFT
    alt   = (mod & UInt16(0x0300)) != UInt16(0)  # KMOD_LALT | KMOD_RALT
    meta  = (mod & UInt16(0x0C00)) != UInt16(0)  # KMOD_LGUI | KMOD_RGUI
    Modifiers(ctrl, shift, alt, meta)
end

# Convenience overload: extract modifiers from the current SDL state.
_current_modifiers() = sdl_modifiers(UInt16(SDL_GetModState() & 0xFFFF))

# ════════════════════════════════════════════════════════════════════════
# Keyboard
# ════════════════════════════════════════════════════════════════════════

"""
    sdl_keysym_to_symbol(keysym::Int32) -> Symbol

Map an SDL keysym integer to the backend-agnostic key symbol vocabulary.
Returns `:char` for printable keys whose specific identity is not tracked
(the character value arrives separately via `SDL_TEXTINPUT`).
"""
function sdl_keysym_to_symbol(keysym::Int32)::Symbol
    # Navigation
    keysym == Int32(1073741904) && return :left
    keysym == Int32(1073741903) && return :right
    keysym == Int32(1073741906) && return :up
    keysym == Int32(1073741905) && return :down
    keysym == Int32(1073741898) && return :home
    keysym == Int32(1073741901) && return :end
    keysym == Int32(1073741899) && return :page_up
    keysym == Int32(1073741902) && return :page_down
    # Editing
    keysym == Int32(8)          && return :backspace
    keysym == Int32(127)        && return :delete
    keysym == Int32(13)         && return :return
    keysym == Int32(9)          && return :tab
    keysym == Int32(1073741897) && return :insert
    # Function keys
    keysym == Int32(1073741882) && return :f1
    keysym == Int32(1073741883) && return :f2
    keysym == Int32(1073741884) && return :f3
    keysym == Int32(1073741885) && return :f4
    keysym == Int32(1073741886) && return :f5
    keysym == Int32(1073741887) && return :f6
    keysym == Int32(1073741888) && return :f7
    keysym == Int32(1073741889) && return :f8
    keysym == Int32(1073741890) && return :f9
    keysym == Int32(1073741891) && return :f10
    keysym == Int32(1073741892) && return :f11
    keysym == Int32(1073741893) && return :f12
    # Misc
    keysym == Int32(27)         && return :escape
    keysym == Int32(32)         && return :space
    keysym == Int32(46)         && return :period   # '.' — used by the Ctrl+. fold chord
    keysym == Int32(1073741881) && return :caps_lock
    # Modifier-only keys
    keysym == Int32(1073742048) && return :lctrl
    keysym == Int32(1073742052) && return :rctrl
    keysym == Int32(1073742049) && return :lshift
    keysym == Int32(1073742053) && return :rshift
    keysym == Int32(1073742050) && return :lalt
    keysym == Int32(1073742054) && return :ralt
    keysym == Int32(1073742051) && return :lmeta
    keysym == Int32(1073742055) && return :rmeta
    # Printable fallback: character arrives via SDL_TEXTINPUT
    return :char
end

"""
    sdl_to_keydown(keysym, mod, is_repeat) -> KeyDown

Build a `KeyDown` from SDL key-down event fields.
"""
function sdl_to_keydown(keysym::Int32, mod::UInt16, is_repeat::Bool)::KeyDown
    KeyDown(sdl_keysym_to_symbol(keysym), sdl_modifiers(mod), is_repeat)
end

"""
    sdl_to_keyup(keysym, mod) -> KeyUp

Build a `KeyUp` from SDL key-up event fields.
"""
function sdl_to_keyup(keysym::Int32, mod::UInt16)::KeyUp
    KeyUp(sdl_keysym_to_symbol(keysym), sdl_modifiers(mod))
end

"""
    sdl_to_keypress(evt) -> Union{KeyPress, Nothing}

Build a `KeyPress` from an `SDL_TEXTINPUT` event. Returns `nothing` if
the event carries no printable text (e.g. empty or invalid UTF-8).
`SDL_TEXTINPUT` provides a null-terminated UTF-8 string in `evt.text.text`
(a `NTuple{32,UInt8}`).
"""
function sdl_to_keypress(evt)::Union{KeyPress,Nothing}
    text_bytes = evt.text.text  # NTuple{32,UInt8}
    len = 0
    for b in text_bytes
        b == 0x00 && break
        len += 1
    end
    len == 0 && return nothing
    text = try
        String(UInt8[text_bytes[i] for i in 1:len])
    catch
        return nothing
    end
    isempty(text) && return nothing
    ch = first(text)
    mods = _current_modifiers()
    KeyPress(ch, text, mods)
end

# ════════════════════════════════════════════════════════════════════════
# Mouse helpers
# ════════════════════════════════════════════════════════════════════════

# Map SDL button byte → Symbol.
_sdl_button_sym(b::UInt8) = b == 0x01 ? :left : b == 0x02 ? :middle : :right

# Map SDL_GetMouseState bitmask → currently-held button symbol.
function _held_button(bstate::UInt32)::Symbol
    (bstate & UInt32(0x01)) != UInt32(0) && return :left
    (bstate & UInt32(0x02)) != UInt32(0) && return :middle
    (bstate & UInt32(0x04)) != UInt32(0) && return :right
    :none
end

# ════════════════════════════════════════════════════════════════════════
# Native window lifecycle (internal helpers; driven by the reconciler in
# `write_to_devices(::SdlBackend, devices, ::ScreenDocument)`).
# ════════════════════════════════════════════════════════════════════════

const _WINDOW_FLAGS_DEFAULT  = SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | UInt32(0x00002000)  # 0x00002000 = SDL_WINDOW_ALLOW_HIGHDPI
const _WINDOW_FLAGS_TOOLTIP  = SDL_WINDOW_SHOWN | UInt32(0x00000010) | UInt32(0x00000400) | UInt32(0x00002000)  # SDL_WINDOW_BORDERLESS | SDL_WINDOW_ALWAYS_ON_TOP
const _WINDOW_FLAGS_FLOATING = SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | UInt32(0x00000400) | UInt32(0x00002000)  # SDL_WINDOW_ALWAYS_ON_TOP

function _window_flags(style::Symbol)
    style === :tooltip  && return _WINDOW_FLAGS_TOOLTIP
    style === :floating && return _WINDOW_FLAGS_FLOATING
    return _WINDOW_FLAGS_DEFAULT
end

# Open one native SDL window for a WindowDocument and return the resource record.
function _open_native_window!(w::WindowDocument)
    px = w.x < 0 ? SDL_WINDOWPOS_CENTERED : Int32(w.x)
    py = w.y < 0 ? SDL_WINDOWPOS_CENTERED : Int32(w.y)
    flags = _window_flags(w.style)
    win = SDL_CreateWindow(w.title, px, py,
        Int32(max(w.width, 1)), Int32(max(w.height, 1)), flags)
    @assert win != C_NULL "SDL window creation failed: $(unsafe_string(SDL_GetError()))"

    renderer = SDL_CreateRenderer(win, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC)
    @assert renderer != C_NULL "SDL renderer creation failed: $(unsafe_string(SDL_GetError()))"

    _update_font_scale!(win, renderer)

    sdl_id = UInt32(SDL_GetWindowID(win))
    SdlWindowResources(win, renderer, w.id, sdl_id, w.title,
                       Int(w.width), Int(w.height), Int(w.x), Int(w.y),
                       w.style, w.bg)
end

# Detect the effective display scale and update the module-wide font scale.
#
# Two-phase detection:
#
#   _detect_font_scale!() — called from init!, before any window exists:
#     1. PROJECTURED_FONT_SCALE env var — explicit override, always respected.
#     2. Xft.dpi from X resources — reliable on X11/XWayland (GNOME writes
#        Xft.dpi = 96 × scale, e.g. 192 for 200%).
#
#   _update_font_scale!(win, renderer) — called when a window opens, only if
#   the early detection left _FONT_SCALE at the default 1.0:
#     3. SDL renderer-output / window-size ratio — macOS Retina, native Wayland.
#     4. SDL_GetDisplayDPI / 96 — Windows fallback.
#
# Falls back to _FONT_SCALE = 1.0 (no scaling) if nothing fires.
function _detect_font_scale!()
    # 1. Explicit override.
    env_val = get(ENV, "PROJECTURED_FONT_SCALE", "")
    if !isempty(env_val)
        scale = tryparse(Float64, env_val)
        if scale !== nothing && scale > 0
            _FONT_SCALE[] = scale
            println("Font scale: $(_FONT_SCALE[]) (PROJECTURED_FONT_SCALE)")
            return true
        end
    end

    # 2. Xft.dpi from X resources — GNOME sets this to 96 × scale on X11 and
    #    XWayland.  Run xrdb only when a DISPLAY is available and xrdb exists.
    if haskey(ENV, "DISPLAY")
        try
            out = readchomp(pipeline(`xrdb -query`, stderr=devnull))
            m = match(r"(?:^|\n)Xft\.dpi:\s*(\d+(?:\.\d+)?)"i, out)
            if m !== nothing
                xft_dpi = parse(Float64, m.captures[1])
                if xft_dpi > 0
                    _FONT_SCALE[] = xft_dpi / 96.0
                    println("Font scale: $(_FONT_SCALE[]) (Xft.dpi = $xft_dpi)")
                    return true
                end
            end
        catch
            # xrdb not installed or failed — fall through.
        end
    end

    return false
end

function _update_font_scale!(win::Ptr{SDL_Window}, renderer::Ptr{SDL_Renderer})
    # Skip if already resolved during init!.
    _FONT_SCALE[] != 1.0 && return

    # SDL renderer output size vs logical window size.
    dw = Ref{Cint}(0); dh = Ref{Cint}(0)
    ww = Ref{Cint}(0); wh = Ref{Cint}(0)
    SDL_GetRendererOutputSize(renderer, dw, dh)
    SDL_GetWindowSize(win, ww, wh)
    if ww[] > 0 && dw[] > ww[]
        _FONT_SCALE[] = Float64(dw[]) / Float64(ww[])
        println("Font scale: $(_FONT_SCALE[]) (SDL renderer ratio)")
        return
    end

    # SDL DPI fallback (Windows / some X11 setups).
    display_index = SDL_GetWindowDisplayIndex(win)
    display_index < 0 && return
    ddpi = Ref{Cfloat}(0)
    hdpi = Ref{Cfloat}(0)
    vdpi = Ref{Cfloat}(0)
    if SDL_GetDisplayDPI(display_index, ddpi, hdpi, vdpi) == 0 && ddpi[] > 0
        _FONT_SCALE[] = Float64(ddpi[]) / 96.0
        println("Font scale: $(_FONT_SCALE[]) (SDL DPI = $(ddpi[]))")
    end
end

# Destroy one native SDL window. Loaded fonts persist in the
# module-level cache until `quit!`.
function _close_native_window!(res::SdlWindowResources)
    SDL_DestroyRenderer(res.renderer)
    SDL_DestroyWindow(res.win)
end

# ── Font resolution ────────────────────────────────────────────────────

function _get_font(font::StyleFont)
    size = font_scaled_size(font.size)
    key = (font.filename, size)
    get!(_font_cache, key) do
        f = TTF_OpenFont(font.filename, size)
        @assert f != C_NULL "Font load failed: $(font.filename)@$(size)"
        f
    end
end

# ── Render a single GraphicsText element ───────────────────────────────

function _render_element!(renderer::Ptr{SDL_Renderer}, elem::GraphicsText, ox::Int, oy::Int)
    text = elem.text::AbstractString
    isempty(text) && return

    font = _get_font(elem.font::StyleFont)
    color = SDL_Color(elem.r, elem.g, elem.b, elem.a)

    surface = TTF_RenderUTF8_Blended(font, text, color)
    surface == C_NULL && return
    texture = SDL_CreateTextureFromSurface(renderer, surface)

    w_ref, h_ref = Ref{Cint}(0), Ref{Cint}(0)
    SDL_QueryTexture(texture, C_NULL, C_NULL, w_ref, h_ref)
    dest = Ref(SDL_Rect(elem.x + ox, elem.y + oy, w_ref[], h_ref[]))
    SDL_RenderCopy(renderer, texture, C_NULL, dest)

    SDL_DestroyTexture(texture)
    SDL_FreeSurface(surface)
end

# ── Render a GraphicsViewport element ────────────────────────────────

function _render_viewport!(renderer::Ptr{SDL_Renderer}, vp::GraphicsViewport, ox::Int, oy::Int)
    vx = Int(vp.x) + ox
    vy = Int(vp.y) + oy
    vw = Int(vp.w)
    vh = Int(vp.h)
    clip = Ref(SDL_Rect(Int32(vx), Int32(vy), Int32(vw), Int32(vh)))
    SDL_RenderSetClipRect(renderer, clip)
    canvas = vp.content::GraphicsCanvas
    cx, cy = Int(canvas.x), Int(canvas.y)
    _render_canvas!(renderer, canvas, vx + cx, vy + cy, vx + vw, vy + vh)
    SDL_RenderSetClipRect(renderer, C_NULL)
end

# ── Render a GraphicsRect element ────────────────────────────────────

_corner_inset(radius::Int, dy::Int) =
    dy >= radius ? 0 : radius - isqrt(radius * radius - (radius - dy) * (radius - dy))

function _render_rect!(renderer::Ptr{SDL_Renderer}, rect::GraphicsRect, ox::Int, oy::Int)
    SDL_SetRenderDrawColor(renderer, rect.r, rect.g, rect.b, rect.a)
    x, y = Int(rect.x) + ox, Int(rect.y) + oy
    w, h_px = Int(rect.w), Int(rect.h)
    max_r = min(w ÷ 2, h_px ÷ 2)
    r_tl = clamp(Int(rect.radius_tl), 0, max_r)
    r_tr = clamp(Int(rect.radius_tr), 0, max_r)
    r_br = clamp(Int(rect.radius_br), 0, max_r)
    r_bl = clamp(Int(rect.radius_bl), 0, max_r)
    if (r_tl | r_tr | r_br | r_bl) == 0
        sdl_rect = Ref(SDL_Rect(Int32(x), Int32(y), Int32(w), Int32(h_px)))
        SDL_RenderFillRect(renderer, sdl_rect)
        return
    end
    top_max = max(r_tl, r_tr)
    bot_max = max(r_bl, r_br)
    mid_h = h_px - top_max - bot_max
    if mid_h > 0
        mid = Ref(SDL_Rect(Int32(x), Int32(y + top_max), Int32(w), Int32(mid_h)))
        SDL_RenderFillRect(renderer, mid)
    end
    for dy in 0:(top_max - 1)
        left = _corner_inset(r_tl, dy)
        right = _corner_inset(r_tr, dy)
        span_w = w - left - right
        span_w <= 0 && continue
        row = Ref(SDL_Rect(Int32(x + left), Int32(y + dy), Int32(span_w), Int32(1)))
        SDL_RenderFillRect(renderer, row)
    end
    for dy in 0:(bot_max - 1)
        left = _corner_inset(r_bl, dy)
        right = _corner_inset(r_br, dy)
        span_w = w - left - right
        span_w <= 0 && continue
        row = Ref(SDL_Rect(Int32(x + left), Int32(y + h_px - 1 - dy), Int32(span_w), Int32(1)))
        SDL_RenderFillRect(renderer, row)
    end
end

# ── Render a GraphicsImage element ─────────────────────────────────────

function _render_image!(renderer::Ptr{SDL_Renderer}, img::GraphicsImage, ox::Int, oy::Int)
    data = img.data
    data === nothing && return
    if data isa Ptr
        dest = Ref(SDL_Rect(img.x + ox, img.y + oy, img.w, img.h))
        SDL_RenderCopy(renderer, Ptr{SDL_Texture}(data), C_NULL, dest)
    elseif data isa Tuple && length(data) == 3 && data[1] isa Vector{UInt8}
        # Decoded image carrying its own native size: (pixels, nw, nh).
        # Build the surface at the native resolution and let SDL_RenderCopy
        # scale it into the span's display box (img.w × img.h).
        buf, nw, nh = data[1]::Vector{UInt8}, Int(data[2]), Int(data[3])
        _blit_rgba!(renderer, buf, nw, nh, img.x + ox, img.y + oy, Int(img.w), Int(img.h))
    elseif data isa Vector{UInt8}
        # Bare buffer with no native size: assume it already matches the
        # display box (img.w × img.h).
        _blit_rgba!(renderer, data, Int(img.w), Int(img.h), img.x + ox, img.y + oy, Int(img.w), Int(img.h))
    end
end

# Create an RGBA32 surface from `buf` (row-major, `src_w × src_h`), upload it
# as a texture, and copy it into the destination rect `(dx, dy, dw, dh)`,
# scaling as needed. `buf` must hold at least `src_w * src_h * 4` bytes.
function _blit_rgba!(renderer::Ptr{SDL_Renderer}, buf::Vector{UInt8},
                     src_w::Int, src_h::Int, dx::Int, dy::Int, dw::Int, dh::Int)
    (src_w <= 0 || src_h <= 0) && return
    surface = SDL_CreateRGBSurfaceFrom(
        pointer(buf), Int32(src_w), Int32(src_h), Int32(32), Int32(src_w * 4),
        0x000000ff, 0x0000ff00, 0x00ff0000, 0xff000000)
    surface == C_NULL && return
    texture = SDL_CreateTextureFromSurface(renderer, surface)
    if texture != C_NULL
        dest = Ref(SDL_Rect(dx, dy, dw, dh))
        SDL_RenderCopy(renderer, texture, C_NULL, dest)
        SDL_DestroyTexture(texture)
    end
    SDL_FreeSurface(surface)
end

# ── Dispatch over a heterogeneous element list ────────────────────────

function _render_elements!(renderer::Ptr{SDL_Renderer}, elements, ox::Int, oy::Int, vw::Int, vh::Int)
    for elem in elements
        _dispatch_render_elem!(renderer, elem, ox, oy, vw, vh)
    end
end

function _render_canvas!(renderer::Ptr{SDL_Renderer}, canvas::GraphicsCanvas, ox::Int, oy::Int, vw::Int, vh::Int)
    layout = canvas.layout
    elements = canvas.elements
    early_stop = !canvas.overlapping_elements && layout != layout_none
    if elements isa ListNode
        # Traverse prev links to render content before the head (e.g. negative y offsets)
        prev_node = elements.prev
        while prev_node !== nothing
            elem = prev_node.value
            if !(elem isa GraphicsFence)
                _dispatch_render_elem!(renderer, elem, ox, oy, vw, vh)
                if early_stop
                    if layout == layout_vertical
                        ey = _render_elem_y(elem)
                        ey !== nothing && (ey + oy) < 0 && break
                    elseif layout == layout_horizontal
                        ex = _render_elem_x(elem)
                        ex !== nothing && (ex + ox) < 0 && break
                    end
                end
            end
            prev_node = prev_node.prev
        end
        # Traverse next links from the head (existing forward rendering)
        node = elements
        while node !== nothing
            elem = node.value
            if !(elem isa GraphicsFence)
                if early_stop
                    if layout == layout_vertical
                        ey = _render_elem_y(elem)
                        ey !== nothing && (ey + oy) > vh && break
                    elseif layout == layout_horizontal
                        ex = _render_elem_x(elem)
                        ex !== nothing && (ex + ox) > vw && break
                    end
                end
                _dispatch_render_elem!(renderer, elem, ox, oy, vw, vh)
            end
            node = node.next
        end
    else
        for elem in elements
            elem isa GraphicsFence && continue
            if early_stop
                if layout == layout_vertical
                    ey = _render_elem_y(elem)
                    ey !== nothing && (ey + oy) > vh && break
                elseif layout == layout_horizontal
                    ex = _render_elem_x(elem)
                    ex !== nothing && (ex + ox) > vw && break
                end
            end
            _dispatch_render_elem!(renderer, elem, ox, oy, vw, vh)
        end
    end
end

function _dispatch_render_elem!(renderer::Ptr{SDL_Renderer}, elem, ox::Int, oy::Int, vw::Int, vh::Int)
    if elem isa GraphicsText
        _render_element!(renderer, elem, ox, oy)
    elseif elem isa GraphicsRect
        _render_rect!(renderer, elem, ox, oy)
    elseif elem isa GraphicsViewport
        _render_viewport!(renderer, elem, ox, oy)
    elseif elem isa GraphicsImage
        _render_image!(renderer, elem, ox, oy)
    elseif elem isa GraphicsCanvas
        # Nested canvas: offset by its position, remaining viewport
        cx, cy = Int(elem.x), Int(elem.y)
        _render_canvas!(renderer, elem, ox + cx, oy + cy, vw - cx, vh - cy)
    end
    # GraphicsFence and unknown types are silently skipped
end

_render_elem_x(elem) = hasproperty(elem, :x) ? Int(elem.x) : nothing
_render_elem_y(elem) = hasproperty(elem, :y) ? Int(elem.y) : nothing

# ── Per-window paint ──────────────────────────────────────────────────

# Clear and repaint one native window's canvas. Called by the
# reconciler once per WindowDocument per frame.
function _render_window!(res::SdlWindowResources, canvas::GraphicsCanvas)
    bg = res.bg
    SDL_SetRenderDrawColor(res.renderer, bg[1], bg[2], bg[3], bg[4])
    SDL_RenderClear(res.renderer)
    _render_canvas!(res.renderer, canvas, 0, 0, res.width, res.height)
    SDL_RenderPresent(res.renderer)
end

# ════════════════════════════════════════════════════════════════════════
# Font measurement
# ════════════════════════════════════════════════════════════════════════

"""
    measure_text(backend::SdlBackend, text::AbstractString, font::StyleFont) -> (Int, Int)

Return `(pixel_width, pixel_height)` of `text` rendered in `font`, using SDL_ttf.
Font handles are cached in the module-level [`_font_cache`](@ref).
"""
function measure_text(::SdlBackend, text::AbstractString, font::StyleFont)
    size = font_scaled_size(font.size)
    isempty(text) && return (0, size)
    cached_font = _get_font(font)
    w_ref, h_ref = Ref{Cint}(0), Ref{Cint}(0)
    TTF_SizeUTF8(cached_font, String(text), w_ref, h_ref)
    return (Int(w_ref[]), Int(h_ref[]))
end

# ── Standalone convenience function ──────────────────────────────────

const _font_backend = SdlBackend()

"""
    sdl_measure_text(text, font) -> (Int, Int)

Standalone text measurement using SDL_ttf. Returns `(pixel_width, pixel_height)`.
Uses a module-level font cache.
"""
sdl_measure_text(text, font) = measure_text(_font_backend, text, font)

# ── Canvas rasterization ──────────────────────────────────────────────

"""
    sdl_render_canvas(canvas::GraphicsCanvas) -> GraphicsImage

Render `canvas` to an offscreen SDL texture and return a `GraphicsImage`
holding the texture pointer as `data`. The caller is responsible for
eventually destroying the texture. Has the `(canvas) -> GraphicsImage`
signature expected by `GraphicsCaching`.

NOTE: requires an active SDL window/renderer. Currently uses the renderer
of the first open window — a proper implementation will accept a renderer
parameter or use a shared offscreen context.
"""
function sdl_render_canvas(canvas::GraphicsCanvas)
    GraphicsImage(Int32(0), Int32(0), Int32(0), Int32(0), nothing)
end

# ════════════════════════════════════════════════════════════════════════
# Offscreen rendering / write_image
# ════════════════════════════════════════════════════════════════════════

"""
    write_image(canvas::GraphicsCanvas, filename::AbstractString;
                width::Integer = 800, height::Integer = 600,
                background::NTuple{4,UInt8} = (0xfd, 0xf6, 0xe3, 0xff)) -> ImageFile

Low-level overload. Render `canvas` to an offscreen SDL2 software renderer and
save the result to `filename`. Returns an `ImageFile` document.
No window is required; SDL2 + SDL_ttf are initialized lazily.

Supported extensions (case-insensitive): `.bmp` (via `SDL_SaveBMP_RW`) and
`.png` (via `IMG_SavePNG` from SDL2_image).

Most callers should use `write_image(document, projection, filename)` instead.
"""
function write_image(canvas::GraphicsCanvas, filename::AbstractString;
                     width::Integer = 800,
                     height::Integer = 600,
                     background::NTuple{4,UInt8} = (0xfd, 0xf6, 0xe3, 0xff))
    SDL_Init(SDL_INIT_VIDEO)
    TTF_Init()

    surface = SDL_CreateRGBSurface(UInt32(0), Int32(width), Int32(height), Int32(32),
                                   UInt32(0x00FF0000), UInt32(0x0000FF00),
                                   UInt32(0x000000FF), UInt32(0xFF000000))
    @assert surface != C_NULL "SDL surface creation failed: $(unsafe_string(SDL_GetError()))"

    renderer = SDL_CreateSoftwareRenderer(surface)
    @assert renderer != C_NULL "SDL software renderer creation failed: $(unsafe_string(SDL_GetError()))"

    r, g, b, a = background
    SDL_SetRenderDrawColor(renderer, r, g, b, a)
    SDL_RenderClear(renderer)

    _render_canvas!(renderer, canvas, 0, 0, Int(width), Int(height))

    ext = lowercase(splitext(filename)[2])
    if ext == ".bmp"
        rw = SDL_RWFromFile(filename, "wb")
        @assert rw != C_NULL "Failed to open output file: $filename"
        SDL_SaveBMP_RW(surface, rw, Int32(1))   # freedst=1 — SDL closes the RW handle
    elseif ext == ".png"
        if IMG_SavePNG(surface, filename) != 0
            err = unsafe_string(SDL_GetError())
            SDL_DestroyRenderer(renderer)
            SDL_FreeSurface(surface)
            error("write_image: IMG_SavePNG failed for $filename: $err")
        end
    else
        SDL_DestroyRenderer(renderer)
        SDL_FreeSurface(surface)
        error("write_image: unsupported format \"$ext\" (only .bmp and .png are supported)")
    end

    SDL_DestroyRenderer(renderer)
    SDL_FreeSurface(surface)

    ImageFile(filename)
end

"""
    write_image(document, projection, filename::AbstractString;
                width::Integer = 800, height::Integer = 600,
                background::NTuple{4,UInt8} = (0xfd, 0xf6, 0xe3, 0xff)) -> ImageFile

Run `projection_print(projection, document)` to obtain a `GraphicsCanvas`,
then render it offscreen and save to `filename` (BMP). The projection is
provided by the caller, typically the same pipeline used to open a live editor
window. Returns an `ImageFile` pointing at the saved file.

```julia
proj = SequentialProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure=sdl_measure_text),
)
write_image(doc, proj, "snapshot.bmp"; width=1200, height=800)
```

Throws if the projection output is not a `GraphicsCanvas`.
"""
function write_image(document, projection, filename::AbstractString;
                     width::Integer = 800,
                     height::Integer = 600,
                     background::NTuple{4,UInt8} = (0xfd, 0xf6, 0xe3, 0xff))
    ctx = ProjectionContext(EmptyReferencePath(),
                            Cell(Int(width)), Cell(Int(height)),
                            Dict{Symbol,Any}())
    iomap = projection_print(projection, document, nothing, ctx)
    canvas = iomap.output
    canvas isa GraphicsCanvas ||
        error("write_image: projection output is $(typeof(canvas)), expected GraphicsCanvas")
    write_image(canvas, filename; width=width, height=height, background=background)
end

"""
    GraphicsCanvasToImageFile(filename; width=800, height=600,
                               background=(0xfd,0xf6,0xe3,0xff))

Printer-only projection. On `projection_print` it renders the input
`GraphicsCanvas` offscreen and saves to `filename` (BMP). The `output` field
of the returned `SimpleIoMap` is an `ImageFile` document. Has no reader.

```julia
proj = SequentialProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure=sdl_measure_text),
    GraphicsCanvasToImageFile("output.bmp"; width=1200, height=800),
)
iomap = projection_print(proj, doc)   # writes output.bmp
# iomap.output isa ImageFile
```
"""
struct GraphicsCanvasToImageFile <: Projection
    filename::String
    width::Int
    height::Int
    background::NTuple{4, UInt8}
end

function GraphicsCanvasToImageFile(filename::AbstractString;
                                    width::Integer = 800,
                                    height::Integer = 600,
                                    background = (0xfd, 0xf6, 0xe3, 0xff))
    GraphicsCanvasToImageFile(String(filename), Int(width), Int(height),
                               NTuple{4,UInt8}(background))
end

function projection_print(p::GraphicsCanvasToImageFile,
                           canvas::GraphicsCanvas, recursion, ctx)
    output = write_image(canvas, p.filename;
                         width=p.width, height=p.height, background=p.background)
    SimpleIoMap(p, canvas, output)
end

function map_reference_forward(::GraphicsCanvasToImageFile, iomap, reference)
    nothing
end

function map_reference_backward(::GraphicsCanvasToImageFile, iomap, reference)
    nothing
end

# ════════════════════════════════════════════════════════════════════════
# Application lifecycle
# ════════════════════════════════════════════════════════════════════════

function init!(::SdlBackend)
    @assert SDL_Init(SDL_INIT_VIDEO) == 0 "SDL init failed: $(unsafe_string(SDL_GetError()))"
    @assert TTF_Init() == 0 "TTF init failed: $(unsafe_string(SDL_GetError()))"
    SDL_StartTextInput()   # enable SDL_TEXTINPUT events (explicit for portability)
    _detect_font_scale!()
end

function quit!(::SdlBackend)
    SDL_StopTextInput()
    for font in values(_font_cache)
        TTF_CloseFont(font)
    end
    empty!(_font_cache)
    TTF_Quit()
    SDL_Quit()
end

# ════════════════════════════════════════════════════════════════════════
# Device I/O
# ════════════════════════════════════════════════════════════════════════

"""
    read_from_devices(backend::SdlBackend, devices) -> EventEnvelope or nothing

Poll the SDL event queue once and return an `EventEnvelope` wrapping a
backend-agnostic inner event:
- Pending synthesised events (e.g. `MousePress`) are returned first.
- `SDL_QUIT`                           → `EventEnvelope(:none, QuitEvent())`
- `SDL_WINDOWEVENT_CLOSE` for a window → `EventEnvelope(<id>, WindowCloseRequest())`
- `SDL_KEYDOWN`                        → `EventEnvelope(<id>, KeyDown)` (Escape → `QuitEvent()`)
- `SDL_KEYUP`                          → `EventEnvelope(<id>, KeyUp)`
- `SDL_TEXTINPUT`                      → `EventEnvelope(<id>, KeyPress)`
- `SDL_MOUSEBUTTONDOWN`                → `EventEnvelope(<id>, MouseDown)`
- `SDL_MOUSEBUTTONUP`                  → `EventEnvelope(<id>, MouseUp)`; also
                                          queues a synthetic `MousePress` envelope
                                          when the button-up matches the preceding
                                          button-down (≤ 5 px, ≤ 300 ms).
- `SDL_MOUSEMOTION` (btn held)         → `EventEnvelope(<id>, MouseMove)`
- `SDL_MOUSEWHEEL`                     → `EventEnvelope(<id>, MouseScroll)`

`<id>` is the `WindowDocument.id` of the originating window (looked up
in `backend.window_ids`), or `:none` if the SDL event carries no window
id or refers to a window the backend does not track.
"""
function read_from_devices(backend::SdlBackend, devices)
    # Deliver any previously synthesised events before polling SDL.
    if !isempty(backend.pending_events)
        return popfirst!(backend.pending_events)
    end

    event_ref = Ref{SDL_Event}()
    while Bool(SDL_PollEvent(event_ref))
        evt = event_ref[]
        t = evt.type

        if t == SDL_QUIT
            return EventEnvelope(:none, QuitEvent())

        elseif t == 0x00000200  # SDL_WINDOWEVENT
            # event byte 1 = SDL_WindowEventID
            sub = evt.window.event
            wid = _lookup_window_id(backend, evt.window.windowID)
            if sub == UInt8(14)  # SDL_WINDOWEVENT_CLOSE
                return EventEnvelope(wid, WindowCloseRequest())
            end
            # Other window events are not currently surfaced; keep polling.
            continue

        elseif t == SDL_KEYDOWN
            keysym = evt.key.keysym.sym
            wid = _lookup_window_id(backend, evt.key.windowID)
            if keysym == Int32(27)  # SDLK_ESCAPE
                return EventEnvelope(:none, QuitEvent())
            end
            is_repeat = evt.key.repeat != 0
            return EventEnvelope(wid, sdl_to_keydown(keysym, evt.key.keysym.mod, is_repeat))

        elseif t == 0x00000301  # SDL_KEYUP
            wid = _lookup_window_id(backend, evt.key.windowID)
            return EventEnvelope(wid, sdl_to_keyup(evt.key.keysym.sym, evt.key.keysym.mod))

        elseif t == 0x00000303  # SDL_TEXTINPUT
            kp = sdl_to_keypress(evt)
            kp === nothing && continue
            wid = _lookup_window_id(backend, evt.text.windowID)
            return EventEnvelope(wid, kp)

        elseif t == 0x00000401  # SDL_MOUSEBUTTONDOWN
            button = _sdl_button_sym(evt.button.button)
            mods = _current_modifiers()
            x, y = Int(evt.button.x), Int(evt.button.y)
            wid = _lookup_window_id(backend, evt.button.windowID)
            # Record for press synthesis.
            backend.last_down_button = button
            backend.last_down_x = x
            backend.last_down_y = y
            backend.last_down_time = time()
            return EventEnvelope(wid, MouseDown(button, x, y, mods))

        elseif t == 0x00000402  # SDL_MOUSEBUTTONUP
            button = _sdl_button_sym(evt.button.button)
            mods = _current_modifiers()
            x, y = Int(evt.button.x), Int(evt.button.y)
            wid = _lookup_window_id(backend, evt.button.windowID)
            # Synthesise MousePress when this up matches the preceding down.
            if button == backend.last_down_button &&
               abs(x - backend.last_down_x) < 5 &&
               abs(y - backend.last_down_y) < 5 &&
               (time() - backend.last_down_time) < 0.3
                push!(backend.pending_events,
                      EventEnvelope(wid, MousePress(button, x, y, mods)))
            end
            return EventEnvelope(wid, MouseUp(button, x, y, mods))

        elseif t == 0x00000400  # SDL_MOUSEMOTION
            # Only forward motion while a button is held to avoid flooding.
            mx_ref, my_ref = Ref{Cint}(0), Ref{Cint}(0)
            bstate = UInt32(SDL_GetMouseState(mx_ref, my_ref))
            buttons = _held_button(bstate)
            buttons == :none && continue
            mods = _current_modifiers()
            wid = _lookup_window_id(backend, evt.motion.windowID)
            return EventEnvelope(wid,
                MouseMove(Int(evt.motion.x), Int(evt.motion.y), buttons, mods))

        elseif t == 0x00000403  # SDL_MOUSEWHEEL
            mx_ref, my_ref = Ref{Cint}(0), Ref{Cint}(0)
            SDL_GetMouseState(mx_ref, my_ref)
            mods = _current_modifiers()
            wid = _lookup_window_id(backend, evt.wheel.windowID)
            dx, dy = Int(evt.wheel.x), Int(evt.wheel.y)
            if mods.shift && dx == 0
                dx, dy = dy, 0
            end
            return EventEnvelope(wid,
                MouseScroll(dx, dy, Int(mx_ref[]), Int(my_ref[]), mods))
        end
    end
    return nothing
end

# Map an SDL windowID to the matching WindowDocument.id, or :none when
# the backend does not currently track that window.
function _lookup_window_id(backend::SdlBackend, sdl_window_id)
    sid = UInt32(sdl_window_id)
    sid == UInt32(0) && return :none
    return get(backend.window_ids, sid, :none)
end

# ════════════════════════════════════════════════════════════════════════
# ScreenDocument reconciliation
# ════════════════════════════════════════════════════════════════════════

"""
    write_to_devices(backend::SdlBackend, devices, screen::ScreenDocument)

Reconcile live native SDL windows against the projection-output
`ScreenDocument`. Windows whose id no longer appears are destroyed;
new ids cause a window to be opened; existing windows have their
geometry / title / style updated as needed, then repainted with the
matching `WindowDocument.content` canvas.

The reconciler ignores `devices` other than via the presence of at
least one `Screen` entry — `Screen` itself carries no per-window
state and exists only to indicate that the editor wants to render
onto a display.
"""
function write_to_devices(backend::SdlBackend, devices::Vector{Device}, screen::ScreenDocument)
    desired_ids = Set{Symbol}()
    for w in screen.windows
        w isa WindowDocument || continue
        push!(desired_ids, w.id)
    end

    # Close windows whose document disappeared.
    for id in collect(keys(backend.windows))
        if !(id in desired_ids)
            res = backend.windows[id]
            delete!(backend.window_ids, res.sdl_id)
            _close_native_window!(res)
            delete!(backend.windows, id)
        end
    end

    # Open / update / paint each desired window.
    for w in screen.windows
        w isa WindowDocument || continue
        res = get(backend.windows, w.id, nothing)
        if res === nothing
            res = _open_native_window!(w)
            backend.windows[w.id] = res
            backend.window_ids[res.sdl_id] = res.id
        else
            _update_window_geometry!(res, w)
        end
        canvas = w.content
        canvas isa GraphicsCanvas ||
            error("write_to_devices: WindowDocument(id=:$(w.id)).content is $(typeof(canvas)), expected GraphicsCanvas")
        _render_window!(res, canvas)
    end
end

# Apply title / size / position / bg changes from a WindowDocument to
# its native counterpart. Cached fields on SdlWindowResources avoid
# redundant SDL calls when nothing changed.
function _update_window_geometry!(res::SdlWindowResources, w::WindowDocument)
    if w.title != res.title
        SDL_SetWindowTitle(res.win, w.title)
        res.title = String(w.title)
    end
    if w.width != res.width || w.height != res.height
        SDL_SetWindowSize(res.win, Int32(max(w.width, 1)), Int32(max(w.height, 1)))
        res.width = Int(w.width)
        res.height = Int(w.height)
    end
    if (w.x >= 0 && w.x != res.x) || (w.y >= 0 && w.y != res.y)
        px = w.x < 0 ? SDL_WINDOWPOS_CENTERED : Int32(w.x)
        py = w.y < 0 ? SDL_WINDOWPOS_CENTERED : Int32(w.y)
        SDL_SetWindowPosition(res.win, px, py)
        res.x = Int(w.x)
        res.y = Int(w.y)
    end
    if w.bg != res.bg
        res.bg = w.bg
    end
    # style changes mid-life would require flag-bit toggles that SDL
    # only partly supports; for now we just remember the latest value.
    res.style = w.style
end

# ════════════════════════════════════════════════════════════════════════
# Image decoding (IMG_Load)
# ════════════════════════════════════════════════════════════════════════

"""
    sdl_decode_image(filename::AbstractString) -> (data::Vector{UInt8}, width::Int32, height::Int32)

Load an image file (PNG, JPEG, BMP, etc.) via SDL2_image's `IMG_Load`,
convert to RGBA32 row-major pixel format, and return the raw bytes plus
the image dimensions. The returned `data` is suitable for passing to
`GraphicsImage` / `_render_image!`.

Throws on failure (file not found, unsupported format, etc.).
"""
function sdl_decode_image(filename::AbstractString)
    SDL_Init(SDL_INIT_VIDEO)
    surface = IMG_Load(filename)
    surface == C_NULL && error("sdl_decode_image: failed to load '$filename': $(unsafe_string(SDL_GetError()))")

    # Convert to RGBA32 (R=byte0, G=byte1, B=byte2, A=byte3 on little-endian)
    rgba_surface = SDL_ConvertSurfaceFormat(surface, UInt32(SDL_PIXELFORMAT_RGBA32), UInt32(0))
    SDL_FreeSurface(surface)
    rgba_surface == C_NULL && error("sdl_decode_image: format conversion failed: $(unsafe_string(SDL_GetError()))")

    s = unsafe_load(rgba_surface)
    w = Int32(s.w)
    h = Int32(s.h)
    pitch = Int(s.pitch)
    expected_pitch = Int(w) * 4

    # Copy pixel data row by row (pitch may include padding)
    data = Vector{UInt8}(undef, Int(w) * Int(h) * 4)
    for row in 0:(Int(h) - 1)
        src_ptr = s.pixels + row * pitch
        dst_offset = row * expected_pitch + 1
        unsafe_copyto!(pointer(data, dst_offset), Ptr{UInt8}(src_ptr), expected_pitch)
    end

    SDL_FreeSurface(rgba_surface)
    (data, w, h)
end

"""
    decode_image_file!(img::ImageFile)

Decode `img.filename` via SDL2_image and populate `img.raw` with a tuple
`(data::Vector{UInt8}, width::Int32, height::Int32)`.
"""
function decode_image_file!(img::ImageFile)
    fn = img.filename::AbstractString
    isempty(fn) && return img
    result = sdl_decode_image(fn)
    img.raw = result
    img
end

end # module
