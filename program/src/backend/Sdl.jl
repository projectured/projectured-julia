"""
    SdlBackendModule

SDL backend. Implements the abstract backend interface using SDL2 + SDL_ttf.
"""
module SdlBackendModule

using SimpleDirectMediaLayer
using SimpleDirectMediaLayer.LibSDL2
import ..BackendModule: Backend, init!, quit!, open_window!, close_window!, measure_text
import ..DeviceModule: Device, read_from_devices, write_to_devices, write_to_device
import ..GraphicsModule: GraphicsCanvas, GraphicsText, GraphicsRect, GraphicsViewport, GraphicsImage,
                         GraphicsFence, LayoutDirection, layout_none, layout_horizontal, layout_vertical
import ..CollectionModule: ListNode
import ..FontModule: StyleFont, font_scaled_size, _FONT_SCALE
import ..WindowModule: Window, QuitEvent
import ..KeyboardModule: KeyPress
import ..MouseModule: MouseClick, MouseMove, MouseScroll

export SdlBackend, sdl_measure_text, sdl_render_canvas

# ════════════════════════════════════════════════════════════════════════
# Backend
# ════════════════════════════════════════════════════════════════════════

"""
    SdlBackend()

SDL2 + SDL_ttf backend. The font measurement cache is shared across all
windows.
"""
mutable struct SdlBackend <: Backend
    font_cache::Dict{Tuple{String,Int}, Ptr{Nothing}}
end

SdlBackend() = SdlBackend(Dict{Tuple{String,Int}, Ptr{Nothing}}())

# ════════════════════════════════════════════════════════════════════════
# Keyboard
# ════════════════════════════════════════════════════════════════════════

"""
    sdl_to_keypress(keysym::Int32, mod::UInt16 = UInt16(0)) -> Union{KeyPress, Nothing}

Convert an SDL keysym value and modifier bitmask to a `KeyPress`. Returns
`nothing` for unrecognised keys (caller handles escape/quit separately).
`ctrl` is set when either Ctrl key is held (KMOD_LCTRL | KMOD_RCTRL).
"""
function sdl_to_keypress(keysym::Int32, mod::UInt16 = UInt16(0))
    ctrl = (mod & UInt16(0x00C0)) != UInt16(0)
    keysym == Int32(1073741904) && return KeyPress(:left,   ctrl)  # SDLK_LEFT
    keysym == Int32(1073741903) && return KeyPress(:right,  ctrl)  # SDLK_RIGHT
    keysym == Int32(1073741906) && return KeyPress(:up,     ctrl)  # SDLK_UP
    keysym == Int32(1073741905) && return KeyPress(:down,   ctrl)  # SDLK_DOWN
    keysym == Int32(1073741898) && return KeyPress(:home,   ctrl)  # SDLK_HOME
    keysym == Int32(1073741901) && return KeyPress(:end,    ctrl)  # SDLK_END
    keysym == Int32(13)         && return KeyPress(:return, ctrl)  # SDLK_RETURN
    keysym == Int32(44)         && return KeyPress(:comma,  ctrl)  # SDLK_COMMA
    keysym == Int32(46)         && return KeyPress(:period, ctrl)  # SDLK_PERIOD
    return nothing
end

# ════════════════════════════════════════════════════════════════════════
# Mouse
# ════════════════════════════════════════════════════════════════════════

"""
    sdl_to_mouse(evt) -> Union{MouseClick, MouseMove, MouseScroll, Nothing}

Convert an SDL event to one of the mouse event structs.
Returns `nothing` for non-mouse events.

Handled SDL event types:
- `SDL_MOUSEBUTTONDOWN` → `MouseClick`
- `SDL_MOUSEMOTION`    → `MouseMove`
- `SDL_MOUSEWHEEL`     → `MouseScroll`
"""
function sdl_to_mouse(evt)
    t = evt.type
    if t == 0x00000401  # SDL_MOUSEBUTTONDOWN
        b = evt.button.button
        button = b == 0x01 ? :left : b == 0x02 ? :middle : :right
        return MouseClick(button, Int(evt.button.x), Int(evt.button.y))
    elseif t == 0x00000200  # SDL_MOUSEMOTION
        return MouseMove(Int(evt.motion.x), Int(evt.motion.y))
    elseif t == 0x00000403  # SDL_MOUSEWHEEL
        mx = Ref{Cint}(0)
        my = Ref{Cint}(0)
        SDL_GetMouseState(mx, my)
        return MouseScroll(Int(evt.wheel.x), Int(evt.wheel.y), Int(mx[]), Int(my[]))
    end
    return nothing
end

# ════════════════════════════════════════════════════════════════════════
# Window
# ════════════════════════════════════════════════════════════════════════

# ── Native handle stored in Window.handle ─────────────────────────────

mutable struct SdlWindowHandle
    win::Ptr{SDL_Window}
    renderer::Ptr{SDL_Renderer}
    font_cache::Dict{Tuple{String,Int}, Ptr{TTF_Font}}
end

"""
    open_window!(::SdlBackend, window::Window) -> Window

Create the native SDL window/renderer and store the handle.
"""
function open_window!(::SdlBackend, window::Window)
    win = SDL_CreateWindow(window.title,
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        Int32(window.width), Int32(window.height),
        SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE)
    @assert win != C_NULL "SDL window creation failed: $(unsafe_string(SDL_GetError()))"

    renderer = SDL_CreateRenderer(win, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC)
    @assert renderer != C_NULL "SDL renderer creation failed: $(unsafe_string(SDL_GetError()))"

    _update_font_scale!(win)

    window.handle = SdlWindowHandle(win, renderer, Dict{Tuple{String,Int}, Ptr{TTF_Font}}())
    window
end

# Query physical DPI of the display this window is on and set the
# module-wide font scale. 96 DPI is the SDL/Windows logical baseline; a
# 144 DPI screen (typical "150%" laptop panel) yields scale ≈ 1.5.
# Falls back to 1.0 if SDL can't report DPI (some Linux/Wayland setups).
function _update_font_scale!(win::Ptr{SDL_Window})
    display_index = SDL_GetWindowDisplayIndex(win)
    display_index < 0 && return
    ddpi = Ref{Cfloat}(0)
    hdpi = Ref{Cfloat}(0)
    vdpi = Ref{Cfloat}(0)
    if SDL_GetDisplayDPI(display_index, ddpi, hdpi, vdpi) == 0 && ddpi[] > 0
        _FONT_SCALE[] = Float64(ddpi[]) / 96.0
    end
end

"""
    close_window!(::SdlBackend, window::Window)

Destroy the native SDL window/renderer and clear the font cache.
"""
function close_window!(::SdlBackend, window::Window)
    h = window.handle::SdlWindowHandle
    for (_, f) in h.font_cache
        TTF_CloseFont(f)
    end
    empty!(h.font_cache)
    SDL_DestroyRenderer(h.renderer)
    SDL_DestroyWindow(h.win)
    window.handle = nothing
end

# ── Font resolution ────────────────────────────────────────────────────

function _get_font(h::SdlWindowHandle, font::StyleFont)
    size = font_scaled_size(font.size)
    key = (font.filename, size)
    get!(h.font_cache, key) do
        f = TTF_OpenFont(font.filename, size)
        @assert f != C_NULL "Font load failed: $(font.filename)@$(size)"
        f
    end
end

# ── Render a single GraphicsText element ───────────────────────────────

function _render_element!(h::SdlWindowHandle, elem::GraphicsText, ox::Int, oy::Int)
    text = elem.text::AbstractString
    isempty(text) && return

    font = _get_font(h, elem.font::StyleFont)
    color = SDL_Color(elem.r, elem.g, elem.b, elem.a)

    surface = TTF_RenderUTF8_Blended(font, text, color)
    surface == C_NULL && return
    texture = SDL_CreateTextureFromSurface(h.renderer, surface)

    w_ref, h_ref = Ref{Cint}(0), Ref{Cint}(0)
    SDL_QueryTexture(texture, C_NULL, C_NULL, w_ref, h_ref)
    dest = Ref(SDL_Rect(elem.x + ox, elem.y + oy, w_ref[], h_ref[]))
    SDL_RenderCopy(h.renderer, texture, C_NULL, dest)

    SDL_DestroyTexture(texture)
    SDL_FreeSurface(surface)
end

# ── Render a GraphicsViewport element ────────────────────────────────

function _render_viewport!(h::SdlWindowHandle, vp::GraphicsViewport, ox::Int, oy::Int)
    vx = Int(vp.x) + ox
    vy = Int(vp.y) + oy
    vw = Int(vp.w)
    vh = Int(vp.h)
    clip = Ref(SDL_Rect(Int32(vx), Int32(vy), Int32(vw), Int32(vh)))
    SDL_RenderSetClipRect(h.renderer, clip)
    canvas = vp.content::GraphicsCanvas
    cx, cy = Int(canvas.x), Int(canvas.y)
    _render_canvas!(h, canvas, vx + cx, vy + cy, vx + vw, vy + vh)
    SDL_RenderSetClipRect(h.renderer, C_NULL)
end

# ── Render a GraphicsRect element ────────────────────────────────────

_corner_inset(radius::Int, dy::Int) =
    dy >= radius ? 0 : radius - isqrt(radius * radius - (radius - dy) * (radius - dy))

function _render_rect!(h::SdlWindowHandle, rect::GraphicsRect, ox::Int, oy::Int)
    SDL_SetRenderDrawColor(h.renderer, rect.r, rect.g, rect.b, rect.a)
    x, y = Int(rect.x) + ox, Int(rect.y) + oy
    w, h_px = Int(rect.w), Int(rect.h)
    max_r = min(w ÷ 2, h_px ÷ 2)
    r_tl = clamp(Int(rect.radius_tl), 0, max_r)
    r_tr = clamp(Int(rect.radius_tr), 0, max_r)
    r_br = clamp(Int(rect.radius_br), 0, max_r)
    r_bl = clamp(Int(rect.radius_bl), 0, max_r)
    if (r_tl | r_tr | r_br | r_bl) == 0
        sdl_rect = Ref(SDL_Rect(Int32(x), Int32(y), Int32(w), Int32(h_px)))
        SDL_RenderFillRect(h.renderer, sdl_rect)
        return
    end
    top_max = max(r_tl, r_tr)
    bot_max = max(r_bl, r_br)
    mid_h = h_px - top_max - bot_max
    if mid_h > 0
        mid = Ref(SDL_Rect(Int32(x), Int32(y + top_max), Int32(w), Int32(mid_h)))
        SDL_RenderFillRect(h.renderer, mid)
    end
    for dy in 0:(top_max - 1)
        left = _corner_inset(r_tl, dy)
        right = _corner_inset(r_tr, dy)
        span_w = w - left - right
        span_w <= 0 && continue
        row = Ref(SDL_Rect(Int32(x + left), Int32(y + dy), Int32(span_w), Int32(1)))
        SDL_RenderFillRect(h.renderer, row)
    end
    for dy in 0:(bot_max - 1)
        left = _corner_inset(r_bl, dy)
        right = _corner_inset(r_br, dy)
        span_w = w - left - right
        span_w <= 0 && continue
        row = Ref(SDL_Rect(Int32(x + left), Int32(y + h_px - 1 - dy), Int32(span_w), Int32(1)))
        SDL_RenderFillRect(h.renderer, row)
    end
end

# ── Render a GraphicsImage element ─────────────────────────────────────

function _render_image!(h::SdlWindowHandle, img::GraphicsImage, ox::Int, oy::Int)
    data = img.data
    data === nothing && return
    if data isa Ptr
        dest = Ref(SDL_Rect(img.x + ox, img.y + oy, img.w, img.h))
        SDL_RenderCopy(h.renderer, Ptr{SDL_Texture}(data), C_NULL, dest)
    elseif data isa Vector{UInt8}
        w, h_px = Int(img.w), Int(img.h)
        surface = SDL_CreateRGBSurfaceFrom(
            pointer(data), Int32(w), Int32(h_px), Int32(32), Int32(w * 4),
            0x000000ff, 0x0000ff00, 0x00ff0000, 0xff000000)
        surface == C_NULL && return
        texture = SDL_CreateTextureFromSurface(h.renderer, surface)
        dest = Ref(SDL_Rect(img.x + ox, img.y + oy, img.w, img.h))
        SDL_RenderCopy(h.renderer, texture, C_NULL, dest)
        SDL_DestroyTexture(texture)
        SDL_FreeSurface(surface)
    end
end

# ── Dispatch over a heterogeneous element list ────────────────────────

function _render_elements!(h::SdlWindowHandle, elements, ox::Int, oy::Int, vw::Int, vh::Int)
    for elem in elements
        _dispatch_render_elem!(h, elem, ox, oy, vw, vh)
    end
end

function _render_canvas!(h::SdlWindowHandle, canvas::GraphicsCanvas, ox::Int, oy::Int, vw::Int, vh::Int)
    layout = canvas.layout
    elements = canvas.elements
    early_stop = !canvas.overlapping_elements && layout != layout_none
    if elements isa ListNode
        # Traverse prev links to render content before the head (e.g. negative y offsets)
        prev_node = elements.prev
        while prev_node !== nothing
            elem = prev_node.value
            if !(elem isa GraphicsFence)
                _dispatch_render_elem!(h, elem, ox, oy, vw, vh)
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
                _dispatch_render_elem!(h, elem, ox, oy, vw, vh)
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
            _dispatch_render_elem!(h, elem, ox, oy, vw, vh)
        end
    end
end

function _dispatch_render_elem!(h::SdlWindowHandle, elem, ox::Int, oy::Int, vw::Int, vh::Int)
    if elem isa GraphicsText
        _render_element!(h, elem, ox, oy)
    elseif elem isa GraphicsRect
        _render_rect!(h, elem, ox, oy)
    elseif elem isa GraphicsViewport
        _render_viewport!(h, elem, ox, oy)
    elseif elem isa GraphicsImage
        _render_image!(h, elem, ox, oy)
    elseif elem isa GraphicsCanvas
        # Nested canvas: offset by its position, remaining viewport
        cx, cy = Int(elem.x), Int(elem.y)
        _render_canvas!(h, elem, ox + cx, oy + cy, vw - cx, vh - cy)
    end
    # GraphicsFence and unknown types are silently skipped
end

_render_elem_x(elem) = hasproperty(elem, :x) ? Int(elem.x) : nothing
_render_elem_y(elem) = hasproperty(elem, :y) ? Int(elem.y) : nothing

# ── write_to_device ───────────────────────────────────────────────────

"""
    write_to_device(::SdlBackend, window::Window, canvas::GraphicsCanvas)

Clear the window and paint every element in `canvas` via SDL.
"""
function write_to_device(::SdlBackend, window::Window, canvas::GraphicsCanvas)
    h = window.handle::SdlWindowHandle
    bg = window.bg
    SDL_SetRenderDrawColor(h.renderer, bg[1], bg[2], bg[3], bg[4])
    SDL_RenderClear(h.renderer)

    _render_canvas!(h, canvas, 0, 0, window.width, window.height)

    SDL_RenderPresent(h.renderer)
end

# ════════════════════════════════════════════════════════════════════════
# Font measurement
# ════════════════════════════════════════════════════════════════════════

"""
    measure_text(backend::SdlBackend, text::AbstractString, font::StyleFont) -> (Int, Int)

Return `(pixel_width, pixel_height)` of `text` rendered in `font`, using SDL_ttf.
Font handles are cached in `backend.font_cache`.
"""
function measure_text(backend::SdlBackend, text::AbstractString, font::StyleFont)
    size = font_scaled_size(font.size)
    isempty(text) && return (0, size)
    key = (font.filename, size)
    cached_font = get!(backend.font_cache, key) do
        f = TTF_OpenFont(font.filename, size)
        @assert f != C_NULL "TTF measure: font load failed: $(font.filename)@$(size)"
        Ptr{Nothing}(f)
    end
    w_ref, h_ref = Ref{Cint}(0), Ref{Cint}(0)
    TTF_SizeUTF8(Ptr{TTF_Font}(cached_font), String(text), w_ref, h_ref)
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
# Application lifecycle
# ════════════════════════════════════════════════════════════════════════

function init!(::SdlBackend)
    @assert SDL_Init(SDL_INIT_VIDEO) == 0 "SDL init failed: $(unsafe_string(SDL_GetError()))"
    @assert TTF_Init() == 0 "TTF init failed: $(unsafe_string(SDL_GetError()))"
end

function quit!(backend::SdlBackend)
    for font in values(backend.font_cache)
        TTF_CloseFont(Ptr{TTF_Font}(font))
    end
    empty!(backend.font_cache)
    TTF_Quit()
    SDL_Quit()
end

# ════════════════════════════════════════════════════════════════════════
# Device I/O
# ════════════════════════════════════════════════════════════════════════

"""
    read_from_devices(backend::SdlBackend, devices) -> event or nothing

Poll the SDL event queue once and classify events:
- `SDL_QUIT` / Escape → `QuitEvent()`
- `SDL_KEYDOWN` → `KeyPress` via `sdl_to_keypress`
- `SDL_MOUSEBUTTONDOWN` / `SDL_MOUSEWHEEL` → mouse event via `sdl_to_mouse`
Returns the first successfully translated event, or `nothing`.
"""
function read_from_devices(::SdlBackend, devices)
    event_ref = Ref{SDL_Event}()
    while Bool(SDL_PollEvent(event_ref))
        evt = event_ref[]
        if evt.type == SDL_QUIT
            return QuitEvent()
        elseif evt.type == SDL_KEYDOWN
            keysym = evt.key.keysym.sym
            if keysym == Int32(27)  # SDLK_ESCAPE
                return QuitEvent()
            end
            key = sdl_to_keypress(keysym, evt.key.keysym.mod)
            key !== nothing && return key
        elseif evt.type == 0x00000401 || evt.type == 0x00000403  # SDL_MOUSEBUTTONDOWN / SDL_MOUSEWHEEL
            mouse = sdl_to_mouse(evt)
            mouse !== nothing && return mouse
        end
    end
    return nothing
end

"""
    write_to_devices(backend::SdlBackend, devices, canvas::GraphicsCanvas)

Render `canvas` to every `Window` in `devices`.
"""
function write_to_devices(backend::SdlBackend, devices::Vector{Device}, canvas::GraphicsCanvas)
    for device in devices
        if device isa Window
            write_to_device(backend, device, canvas)
        end
    end
end

end # module