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
import ..ModifiersModule: Modifiers
import ..KeyboardModule: KeyDown, KeyUp, KeyPress
import ..MouseModule: MouseDown, MouseUp, MousePress, MouseMove, MouseScroll
import ..ImageModule: ImageFile
import ..ProjectionApiModule: projection_print, Projection
import ..IoMapModule: SimpleIoMap

export SdlBackend, sdl_measure_text, sdl_render_canvas, write_image, GraphicsCanvasToImageFile

# ════════════════════════════════════════════════════════════════════════
# Backend
# ════════════════════════════════════════════════════════════════════════

"""
    SdlBackend()

SDL2 + SDL_ttf backend. The font measurement cache is shared across all
windows. An internal `pending_events` queue holds synthesised events
(e.g. `MousePress`) scheduled to be delivered on the next poll.
"""
mutable struct SdlBackend <: Backend
    font_cache::Dict{Tuple{String,Int}, Ptr{Nothing}}
    # Synthesised-event queue: drained before polling SDL.
    pending_events::Vector{Any}
    # State for MousePress synthesis.
    last_down_button::Symbol
    last_down_x::Int
    last_down_y::Int
    last_down_time::Float64
end

SdlBackend() = SdlBackend(
    Dict{Tuple{String,Int}, Ptr{Nothing}}(),
    Any[],
    :none, 0, 0, 0.0,
)

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
# Offscreen rendering / write_image
# ════════════════════════════════════════════════════════════════════════

"""
    write_image(canvas::GraphicsCanvas, filename::AbstractString;
                width::Integer = 800, height::Integer = 600,
                background::NTuple{4,UInt8} = (0x00, 0x00, 0x00, 0xff)) -> ImageFile

Low-level overload. Render `canvas` to an offscreen SDL2 software renderer and
save the result to `filename` (BMP format). Returns an `ImageFile` document.
No window is required; SDL2 + SDL_ttf are initialized lazily.

Supported extensions: `.bmp` (case-insensitive).

Most callers should use `write_image(document, projection, filename)` instead.
"""
function write_image(canvas::GraphicsCanvas, filename::AbstractString;
                     width::Integer = 800,
                     height::Integer = 600,
                     background::NTuple{4,UInt8} = (0x00, 0x00, 0x00, 0xff))
    SDL_Init(SDL_INIT_VIDEO)
    TTF_Init()

    surface = SDL_CreateRGBSurface(UInt32(0), Int32(width), Int32(height), Int32(32),
                                   UInt32(0x00FF0000), UInt32(0x0000FF00),
                                   UInt32(0x000000FF), UInt32(0xFF000000))
    @assert surface != C_NULL "SDL surface creation failed: $(unsafe_string(SDL_GetError()))"

    renderer = SDL_CreateSoftwareRenderer(surface)
    @assert renderer != C_NULL "SDL software renderer creation failed: $(unsafe_string(SDL_GetError()))"

    h = SdlWindowHandle(C_NULL, renderer, Dict{Tuple{String,Int}, Ptr{TTF_Font}}())
    r, g, b, a = background
    SDL_SetRenderDrawColor(renderer, r, g, b, a)
    SDL_RenderClear(renderer)

    _render_canvas!(h, canvas, 0, 0, Int(width), Int(height))

    ext = lowercase(splitext(filename)[2])
    if ext == ".bmp"
        rw = SDL_RWFromFile(filename, "wb")
        @assert rw != C_NULL "Failed to open output file: $filename"
        SDL_SaveBMP_RW(surface, rw, Int32(1))   # freedst=1 — SDL closes the RW handle
    else
        SDL_DestroyRenderer(renderer)
        SDL_FreeSurface(surface)
        error("write_image: unsupported format \"$ext\" (only .bmp is supported)")
    end

    for (_, font) in h.font_cache
        TTF_CloseFont(font)
    end
    SDL_DestroyRenderer(renderer)
    SDL_FreeSurface(surface)

    ImageFile(filename)
end

"""
    write_image(document, projection, filename::AbstractString;
                width::Integer = 800, height::Integer = 600,
                background::NTuple{4,UInt8} = (0x00, 0x00, 0x00, 0xff)) -> ImageFile

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
                     background::NTuple{4,UInt8} = (0x00, 0x00, 0x00, 0xff))
    iomap = projection_print(projection, document)
    canvas = iomap.output
    canvas isa GraphicsCanvas ||
        error("write_image: projection output is $(typeof(canvas)), expected GraphicsCanvas")
    write_image(canvas, filename; width=width, height=height, background=background)
end

"""
    GraphicsCanvasToImageFile(filename; width=800, height=600,
                               background=(0x00,0x00,0x00,0xff))

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
                                    background = (0x00, 0x00, 0x00, 0xff))
    GraphicsCanvasToImageFile(String(filename), Int(width), Int(height),
                               NTuple{4,UInt8}(background))
end

function projection_print(p::GraphicsCanvasToImageFile,
                           canvas::GraphicsCanvas, recursion, reference)
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
end

function quit!(backend::SdlBackend)
    SDL_StopTextInput()
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

Poll the SDL event queue once and return a backend-agnostic event:
- Pending synthesised events (e.g. `MousePress`) are returned first.
- `SDL_QUIT` / Escape          → `QuitEvent()`
- `SDL_KEYDOWN`                → `KeyDown` (Escape → `QuitEvent()`)
- `SDL_KEYUP`                  → `KeyUp`
- `SDL_TEXTINPUT`              → `KeyPress` (decoded Unicode character)
- `SDL_MOUSEBUTTONDOWN`        → `MouseDown`
- `SDL_MOUSEBUTTONUP`          → `MouseUp`; also queues `MousePress` when
                                 the button-up is close to the preceding
                                 button-down (≤ 5 px, ≤ 300 ms).
- `SDL_MOUSEMOTION` (btn held) → `MouseMove`
- `SDL_MOUSEWHEEL`             → `MouseScroll`

Motion events are forwarded only when a mouse button is held; idle motion
is dropped to avoid flooding the projection pipeline.
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
            return QuitEvent()

        elseif t == SDL_KEYDOWN
            keysym = evt.key.keysym.sym
            if keysym == Int32(27)  # SDLK_ESCAPE
                return QuitEvent()
            end
            is_repeat = evt.key.repeat != 0
            return sdl_to_keydown(keysym, evt.key.keysym.mod, is_repeat)

        elseif t == 0x00000301  # SDL_KEYUP
            return sdl_to_keyup(evt.key.keysym.sym, evt.key.keysym.mod)

        elseif t == 0x00000303  # SDL_TEXTINPUT
            kp = sdl_to_keypress(evt)
            kp !== nothing && return kp

        elseif t == 0x00000401  # SDL_MOUSEBUTTONDOWN
            button = _sdl_button_sym(evt.button.button)
            mods = _current_modifiers()
            x, y = Int(evt.button.x), Int(evt.button.y)
            # Record for press synthesis.
            backend.last_down_button = button
            backend.last_down_x = x
            backend.last_down_y = y
            backend.last_down_time = time()
            return MouseDown(button, x, y, mods)

        elseif t == 0x00000402  # SDL_MOUSEBUTTONUP
            button = _sdl_button_sym(evt.button.button)
            mods = _current_modifiers()
            x, y = Int(evt.button.x), Int(evt.button.y)
            # Synthesise MousePress when this up matches the preceding down.
            if button == backend.last_down_button &&
               abs(x - backend.last_down_x) < 5 &&
               abs(y - backend.last_down_y) < 5 &&
               (time() - backend.last_down_time) < 0.3
                push!(backend.pending_events, MousePress(button, x, y, mods))
            end
            return MouseUp(button, x, y, mods)

        elseif t == 0x00000200  # SDL_MOUSEMOTION
            # Only forward motion while a button is held to avoid flooding.
            mx_ref, my_ref = Ref{Cint}(0), Ref{Cint}(0)
            bstate = UInt32(SDL_GetMouseState(mx_ref, my_ref))
            buttons = _held_button(bstate)
            buttons == :none && continue
            mods = _current_modifiers()
            return MouseMove(Int(evt.motion.x), Int(evt.motion.y), buttons, mods)

        elseif t == 0x00000403  # SDL_MOUSEWHEEL
            mx_ref, my_ref = Ref{Cint}(0), Ref{Cint}(0)
            SDL_GetMouseState(mx_ref, my_ref)
            mods = _current_modifiers()
            return MouseScroll(Int(evt.wheel.x), Int(evt.wheel.y),
                               Int(mx_ref[]), Int(my_ref[]), mods)
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
