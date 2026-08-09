"""
    Sdl

Opt-in package: the SDL display/input backend (window, GPU rendering, SDL_ttf text
rasterisation, offscreen image output). Depends on `ProjecturedDomain` +
SimpleDirectMediaLayer/SDL2_jll; `using ProjecturedSdl` provides the
render/decode/image seam methods. Exposes `SdlBackend`,
`GraphicsCanvasToImageFile`, and the `sdl_*` helpers. Also exports the offscreen
primitives (`_open_offscreen_renderer`, `_close_offscreen_renderer`, `_emit_frames!`)
that the opt-in `ProjecturedVideo` package builds `record_video` on (FFMPEG lives there,
not here).

Relocated from the former program/src/backend/Sdl.jl (SdlBackendModule); relative
submodule imports were rewritten to absolute ProjecturedDomain.* references.
"""
module ProjecturedSdl

using ProjecturedDomain


using SimpleDirectMediaLayer
using SimpleDirectMediaLayer.LibSDL2
# The backend + device contracts (AR-QUALIFIED-EXTENSION): bare `using`,
# extended by qualification below. A bare `using` of an alias binds the
# module's *real* name, so the extension sites read BackendModule.*;
# DeviceModule supplies the `Device` type used in the render signatures.
using ProjecturedDomain.BackendModule
using ProjecturedDomain.DeviceModule
import ProjecturedDomain.GraphicsModule: GraphicsCanvas, GraphicsText, GraphicsRect, GraphicsLine, GraphicsCircle,
                         GraphicsPolyline, GraphicsPolygon, GraphicsSpline, GraphicsViewport, GraphicsImage,
                         GraphicsFence, LayoutDirection, layout_none, layout_horizontal, layout_vertical,
                         _canvas_content_bounds, _accumulate_bounds!, _bounds_elem!,
                         tessellate_spline, polyline_arrowhead
import ProjecturedDomain.CollectionModule: ListNode, CellVector, ComputedCellVector
import ProjecturedDomain.GeometryModule: AffineTransform, affine_identity, affine_is_axis_aligned
import ProjecturedDomain.ColorModule: StyleColor
import ProjecturedDomain.FontModule: StyleFont, font_scaled_size, font_logical_size, font_device_size,
                         _DISPLAY_SCALE, _BASE_DISPLAY_SCALE, recompute_display_scale!,
                         adjust_user_zoom!, adjust_font_zoom!, _FONT_DIR
import ProjecturedDomain.EventModule: WindowQuit
import ProjecturedDomain.ScreenDocumentModule: ScreenDocument, WindowDocument
import ProjecturedDomain.EventModule: WindowInput, WindowClose, WindowResize, WindowDefocus
import ProjecturedDomain.EventModule: ModifierKeys
import ProjecturedDomain.EventModule: KeyDown, KeyUp, KeyPress
import ProjecturedDomain.EventModule: MouseDown, MouseUp, MousePress, MouseMove, MouseScroll
import ProjecturedDomain.ImageModule: ImageFile
import ProjecturedDomain.ProjectionApiModule: print_document, read_intent, Projection
import ProjecturedDomain.OperationModule: Operation, evaluate_operation
import ProjecturedDomain.OperationModule: AdjustZoomOperation, AdjustFontZoomOperation
import ProjecturedDomain.SelectionModule: clear_selection!, set_selection!
import ProjecturedDomain.PrinterContextModule: PrinterContext
import ProjecturedDomain.CellModule: Cell, ComputedCell, is_cell_up_to_date
import ProjecturedDomain.ReferenceModule: EmptyReference
import ProjecturedDomain.IoMapModule: SimpleIoMap

export SdlBackend, sdl_measure_text, sdl_render_canvas, sdl_display_size,
       write_image, GraphicsCanvasToImageFile,
       _open_offscreen_renderer, _close_offscreen_renderer, _emit_frames!,
       sdl_decode_image, decode_image_file!

# Pixel size of the primary monitor from xrandr's RandR 1.5
# `--listmonitors`. SDL can fold a multi-monitor X screen into a single
# "display" whose bounds span every monitor, hiding the per-monitor layout;
# xrandr still reports each monitor's own pixel size. Returns `(width,
# height)` for the monitor flagged primary (`*`), falling back to the first
# listed monitor. Returns `nothing` when DISPLAY is unset, xrandr is missing
# or unparseable, or — with `require_multi=true` — fewer than two monitors
# are present (so genuinely single-monitor setups keep SDL's usable bounds).
function _x11_primary_monitor_size(; require_multi::Bool=false)
    haskey(ENV, "DISPLAY") || return nothing
    try
        out = readchomp(pipeline(`xrandr --listmonitors`, stderr=devnull))
        mons = Tuple{Int,Int}[]
        primary = nothing
        for line in split(out, '\n')
            # e.g. " 0: +*DP-2 5120/600x2880/340+0+0  DP-2"
            m = match(r"^\s*\d+:\s+\+(\*?)\S+\s+(\d+)/\d+x(\d+)/\d+", line)
            m === nothing && continue
            wh = (parse(Int, m.captures[2]), parse(Int, m.captures[3]))
            push!(mons, wh)
            m.captures[1] == "*" && primary === nothing && (primary = wh)
        end
        isempty(mons) && return nothing
        require_multi && length(mons) < 2 && return nothing
        return primary === nothing ? mons[1] : primary
    catch
        # xrandr not installed, no RandR 1.5, or parse failure — fall through.
        return nothing
    end
end

"""
    sdl_display_size(; display::Integer=0) -> (width, height)

Return the usable size of the given display (default 0) in **logical** pixels —
the coordinate space window sizes are authored in. "Usable" means with
OS-reserved areas like the taskbar / menu bar subtracted; the right thing for
picking a default window size. The monitor's device-pixel size is divided by
[`_DISPLAY_SCALE`](@ref) so that a window sized to it fills exactly one monitor
once the backend scales it back to device pixels. Falls back to `(1280, 720)`
if SDL cannot answer (no display, headless run, etc.). The video subsystem and
the display scale are initialized lazily; safe to call before `initialize_backend!`.

On X11 SDL sometimes folds a multi-monitor screen into a single "display"
whose bounds span every monitor (e.g. 7290×4032 across two), which would
size the default window to the whole desktop. When SDL reports one display
but xrandr sees several, the primary monitor's size from xrandr is used
instead so the default fills one monitor, not the span.
"""
function sdl_display_size(; display::Integer=0)
    SDL_Init(SDL_INIT_VIDEO) == 0 || return (1280, 720)
    # Ensure the scale is known before converting device → logical, since this
    # may run before `initialize_backend!` (early detection is window-free: env
    # + Xft.dpi). The probe latches itself, so repeated calls cost nothing.
    _detect_display_scale!()

    # Detect the SDL-collapses-multiple-monitors case and prefer the real
    # primary-monitor size. Only when SDL reports a single display (so we do
    # not override a setup where SDL already enumerates monitors correctly).
    if display == 0 && SDL_GetNumVideoDisplays() <= 1
        mon = _x11_primary_monitor_size(; require_multi=true)
        mon === nothing || return (_to_logical(mon[1]), _to_logical(mon[2]))
    end

    rect = Ref(SDL_Rect(Int32(0), Int32(0), Int32(0), Int32(0)))
    rc = SDL_GetDisplayUsableBounds(Int32(display), rect)
    if rc != 0 || rect[].w <= 0 || rect[].h <= 0
        return (1280, 720)
    end
    (_to_logical(Int(rect[].w)), _to_logical(Int(rect[].h)))
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
    ss::Int              # supersample factor for anti-aliasing (1 = off)
    target::Ptr{SDL_Texture}  # offscreen SSAA render target (C_NULL until created)
    target_w::Int        # current target texture size (device px)
    target_h::Int
    # Dirty-rectangle partial repaint state.
    first_paint::Bool    # force a full repaint on the first frame / after target (re)creation
    dirty_bounds::Dict{UInt,NTuple{4,Int}}  # last-rendered absolute logical bounds, keyed by
                                            # objectid of each dirty-unit container/leaf (for old∪new)
    # Recent frames' logical dirty rects (x0,y0,x1,y1), most-recent first. The
    # target→window copy each frame refreshes the union of the last `buffer age`
    # of these: the back-buffer we draw into was last presented `age` frames ago
    # (queried via EGL/GLX buffer age), so everything that changed since then
    # must be re-copied or the older edits ghost on the alternate buffer(s).
    damage_history::Vector{NTuple{4,Int}}
end

"""
    SdlBackend()

SDL2 + SDL_ttf backend. Loaded TTF fonts are cached in the module-level
[`_font_cache`](@ref), shared across windows, measurement, and offscreen
image rendering.

The backend emits only raw input events; recognising composite gestures
(e.g. synthesising a `MousePress` click from a `MouseDown`/`MouseUp` pair) is
the editor's `GestureRecognizer`'s job, not the backend's.

`windows` is the live registry of native SDL windows, keyed by the
`WindowDocument.id` they mirror. `window_ids` is the reverse map from
SDL `windowID` to `WindowDocument.id`, used when translating raw SDL
events into `WindowInput`s. Both are reconciled by
`write_to_devices(::SdlBackend, devices, ::ScreenDocument)`.
"""
mutable struct SdlBackend <: Backend
    # Multi-window reconciliation state.
    windows::Dict{Symbol, SdlWindowResources}
    window_ids::Dict{UInt32, Symbol}
    # Render controls (diagnostics / benchmarking). `initialize_backend!` copies these into the
    # `_PARTIAL_RENDER` / `_DEBUG_DIRTY` globals the render path reads:
    #   partial_render — incremental dirty-rectangle repaint (false = full frame)
    #   debug_dirty    — outline the repainted region in red
    partial_render::Bool
    debug_dirty::Bool
end

# `partial_render` / `debug_dirty` default to the PROJECTURED_PARTIAL_RENDER /
# PROJECTURED_DEBUG_DIRTY env vars (via `_envflag`) when left as `nothing`, so a
# bare `SdlBackend()` keeps the env-driven defaults; pass an explicit `Bool` to
# override (e.g. from `run_example(; partial_render=false, debug_dirty=true)`).
SdlBackend(; partial_render::Union{Bool,Nothing} = nothing,
             debug_dirty::Union{Bool,Nothing}    = nothing) =
    SdlBackend(Dict{Symbol, SdlWindowResources}(),
               Dict{UInt32, Symbol}(),
               partial_render === nothing ? _envflag("PROJECTURED_PARTIAL_RENDER", false) : partial_render,
               debug_dirty    === nothing ? _envflag("PROJECTURED_DEBUG_DIRTY", false)    : debug_dirty)

# Module-level TTF font cache, keyed by (filename, scaled_size).
# Shared by window rendering, offscreen image rendering, and text measurement.
# Populated lazily by `_get_font`; freed by `quit_backend!`.
const _font_cache = Dict{Tuple{String,Int}, Ptr{TTF_Font}}()

# Module-level text-texture cache. Rendering a `GraphicsText` rasterizes the
# string (`TTF_RenderUTF8_Blended`), uploads a GPU texture, draws it, then
# destroys the texture — every span, every frame. When scrolling a static
# document the spans never change, so the rasterize/upload/destroy churn is the
# dominant render cost. We cache the uploaded texture (plus its device size, so
# `SDL_QueryTexture` is skipped too) keyed by renderer + text + font + colour and
# reuse it across frames. Textures are renderer-specific, so entries are evicted
# when their renderer is destroyed (`_close_native_window!`,
# `_close_offscreen_renderer`) and all are freed by `quit_backend!`.
struct _TextTextureKey
    renderer::Ptr{SDL_Renderer}
    text::String
    filename::String
    size::Int
    color::NTuple{4,UInt8}
end

struct _TextTexture
    texture::Ptr{SDL_Texture}
    dw::Int   # device px width  (logical size is recomputed per draw via _to_logical)
    dh::Int   # device px height
end

const _text_texture_cache = Dict{_TextTextureKey, _TextTexture}()

# Soft cap: a single document's distinct spans are bounded, but rendering many
# different documents over a session would grow this without limit. When the cap
# is hit, drop everything and start over — far simpler than an LRU and rare.
const _TEXT_TEXTURE_CACHE_CAP = 16384

# ── Dirty-rectangle partial repaint controls ─────────────────────────────
#
# Each editor frame currently repaints the whole window. Nothing needs to be
# repainted that has not been *invalidated* in the reactive graph, so we walk
# the canvas tree, find the smallest rectangle covering every invalidated
# graphic, clip to it and repaint only that region into a retained target.
#
# `_PARTIAL_RENDER` — master switch (false forces the original full-frame
#   repaint). `_DEBUG_DIRTY` — when on, outline the repainted region in red so it
#   is visible which part of the screen was painted.
#
# These globals are the values the render path reads; `initialize_backend!` sets them from the
# active `SdlBackend`'s `partial_render` / `debug_dirty` fields, which in turn
# default to the PROJECTURED_PARTIAL_RENDER / PROJECTURED_DEBUG_DIRTY env vars.
const _PARTIAL_RENDER = Ref(true)
const _DEBUG_DIRTY = Ref(true)

# How many recent frames' damage rects to retain for the partial target→window
# copy. The copy refreshes the union of the last `buffer age` of them; deeper
# swap chains than this fall back to a full copy. 8 is far beyond any real swap
# chain (double/triple buffering ⇒ age 2/3).
const _DAMAGE_HISTORY_CAP = 8

_envflag(name, default::Bool) =
    (v = lowercase(get(ENV, name, "")); v == "" ? default : v in ("1", "true", "yes", "on"))

function _clear_text_texture_cache!()
    for entry in values(_text_texture_cache)
        SDL_DestroyTexture(entry.texture)
    end
    empty!(_text_texture_cache)
end

# Drop (and free) every cached texture owned by `renderer`. Must run before the
# renderer itself is destroyed, otherwise the cached pointers dangle.
function _evict_renderer_textures!(renderer::Ptr{SDL_Renderer})
    for (k, entry) in _text_texture_cache
        k.renderer == renderer || continue
        SDL_DestroyTexture(entry.texture)
        delete!(_text_texture_cache, k)
    end
end

# ════════════════════════════════════════════════════════════════════════
# Modifier extraction
# ════════════════════════════════════════════════════════════════════════

"""
    sdl_modifiers(mod::UInt16) -> ModifierKeys

Decode an SDL modifier bitmask into a `ModifierKeys` struct.

Bitmask layout (same as SDL_Keymod):
- Ctrl  : bits 6–7   (KMOD_LCTRL=0x0040, KMOD_RCTRL=0x0080)
- Shift : bits 0–1   (KMOD_LSHIFT=0x0001, KMOD_RSHIFT=0x0002)
- Alt   : bits 8–9   (KMOD_LALT=0x0100, KMOD_RALT=0x0200)
- Meta  : bits 10–11 (KMOD_LGUI=0x0400, KMOD_RGUI=0x0800)
"""
function sdl_modifiers(mod::UInt16)::ModifierKeys
    ctrl  = (mod & UInt16(0x00C0)) != UInt16(0)  # KMOD_LCTRL | KMOD_RCTRL
    shift = (mod & UInt16(0x0003)) != UInt16(0)  # KMOD_LSHIFT | KMOD_RSHIFT
    alt   = (mod & UInt16(0x0300)) != UInt16(0)  # KMOD_LALT | KMOD_RALT
    meta  = (mod & UInt16(0x0C00)) != UInt16(0)  # KMOD_LGUI | KMOD_RGUI
    ModifierKeys(ctrl, shift, alt, meta)
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
    # Clipboard projection chords (ClipboardToAnyProjectionModule): the letter and
    # punctuation keys it binds need distinct symbols rather than the `:char`
    # fallback so `@event_case` can tell them apart under Ctrl.
    keysym == Int32(116)        && return :t        # Ctrl+T — open a pane tab
    keysym == Int32(119)        && return :w        # Ctrl+W — close a pane tab
    keysym == Int32(92)         && return :backslash # Ctrl+\\ — split a pane group
    keysym == Int32(99)         && return :c        # Ctrl+C — copy
    keysym == Int32(120)        && return :x        # Ctrl+X — cut
    keysym == Int32(118)        && return :v        # Ctrl+V — paste
    keysym == Int32(110)        && return :n        # Ctrl+N — note
    keysym == Int32(112)        && return :p        # Ctrl+Shift+P — the command palette
    keysym == Int32(115)        && return :s        # Ctrl+S — save, Ctrl+Shift+S — snapshot
    keysym == Int32(111)        && return :o        # Ctrl+O — reload from disk
    keysym == Int32(47)         && return :slash    # '/' — toggle slice display
    keysym == Int32(1073741908) && return :slash    # keypad '/'
    keysym == Int32(1073741909) && return :asterisk # keypad '*' — toggle collection display
    keysym == Int32(61)         && return :equals   # '=' — add to collection
    keysym == Int32(1073741911) && return :equals   # keypad '+'
    keysym == Int32(45)         && return :minus    # '-' — remove from collection
    keysym == Int32(1073741910) && return :minus    # keypad '-'
    keysym == Int32(48)         && return :zero     # '0' — reset transform/zoom (Ctrl+0 / Ctrl+Alt+0)
    keysym == Int32(1073741922) && return :zero     # keypad '0'
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
    # WindowDocument sizes are logical; the native window is device pixels.
    win = SDL_CreateWindow(w.title, px, py,
        Int32(max(_to_device(w.width), 1)), Int32(max(_to_device(w.height), 1)), flags)
    @assert win != C_NULL "SDL window creation failed: $(unsafe_string(SDL_GetError()))"

    # Linear filtering so the supersampled target downsamples smoothly.
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "1")
    renderer = SDL_CreateRenderer(win, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC)
    @assert renderer != C_NULL "SDL renderer creation failed: $(unsafe_string(SDL_GetError()))"
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)

    # Report which SDL render driver we actually got: a *software* driver
    # (e.g. llvmpipe under a VM/headless GL) makes the per-frame full-window
    # present CPU-rasterized and is the usual reason `print` is tens of ms even
    # when nothing recomputes.
    let ri = Ref{SDL_RendererInfo}()
        if SDL_GetRendererInfo(renderer, ri) == 0
            accel = (ri[].flags & SDL_RENDERER_ACCELERATED) != 0
            @info "[sdl] renderer" driver=unsafe_string(ri[].name) accelerated=accel
        end
    end

    _update_display_scale!(win, renderer)

    sdl_id = UInt32(SDL_GetWindowID(win))
    SdlWindowResources(win, renderer, w.id, sdl_id, w.title,
                       Int(w.width), Int(w.height), Int(w.x), Int(w.y),
                       w.style, w.bg, _window_supersample(), C_NULL, 0, 0,
                       true, Dict{UInt,NTuple{4,Int}}(), NTuple{4,Int}[])
end

# Supersample factor for live windows (anti-aliasing). Override with the
# PROJECTURED_SUPERSAMPLE env var; default 2. 1 disables it.
function _window_supersample()
    v = get(ENV, "PROJECTURED_SUPERSAMPLE", "")
    s = tryparse(Int, v)
    s === nothing ? 2 : clamp(s, 1, 4)
end

# ── Logical ↔ device pixel conversion ──────────────────────────────────
#
# Layout, documents and events are all in *logical* pixels; the window's
# backbuffer and the OS are in *device* pixels. These convert across the
# `_DISPLAY_SCALE` boundary. `_to_device` sizes native windows / SSAA targets;
# `_to_logical` maps incoming device-space input (mouse, resize) back to the
# logical space everything else lives in.
_to_device(px) = round(Int, px * _DISPLAY_SCALE[])
_to_logical(px) = round(Int, px / _DISPLAY_SCALE[])

# Idle (no-button) mouse motion is forwarded for hover features (e.g. the
# reference inspector) but rate-limited so a probe does not run on every pixel.
# Button-held motion (drag) is never throttled.
const _HOVER_MOTION_INTERVAL = 0.03   # seconds (~33 Hz)
const _LAST_HOVER_MOTION = Ref(0.0)

"""
    get_pointer_position(::SdlBackend) -> (x, y)

Current global mouse position in screen pixels (the same coordinate space as
`SDL_SetWindowPosition`, so the result can place a window directly). Not run
through `_to_logical`: window positions and global mouse coordinates are both
in SDL screen coordinates.
"""
function BackendModule.get_pointer_position(::SdlBackend)
    x_ref, y_ref = Ref{Cint}(0), Ref{Cint}(0)
    SDL_GetGlobalMouseState(x_ref, y_ref)
    (Int(x_ref[]), Int(y_ref[]))
end

# Detect the effective display scale and update the module-wide font scale.
#
# Two-phase detection:
#
#   _detect_display_scale!() — called from initialize_backend! and from
#   sdl_display_size, before any window exists:
#     1. PROJECTURED_DISPLAY_SCALE env var — explicit override, always respected.
#     2. Xft.dpi from X resources — reliable on X11/XWayland (GNOME writes
#        Xft.dpi = 96 × scale, e.g. 192 for 200%).
#
#   _update_display_scale!(win, renderer) — called when a window opens, only if
#   the window-free phase found nothing:
#     3. SDL renderer-output / window-size ratio — macOS Retina, native Wayland.
#     4. SDL_GetDisplayDPI / 96 — Windows fallback.
#
# Falls back to _DISPLAY_SCALE = 1.0 (no scaling) if nothing fires.
#
# Both phases are latched, because the scale value alone cannot say whether a
# probe already ran: a 1× display detects as exactly 1.0, which is also the
# default. Without the latches every caller re-runs `xrdb`, and phase 4
# overwrites a correct 1.0 with SDL's slightly-off DPI ratio (e.g. 96.04 / 96).
#
#   _DISPLAY_SCALE_PROBED   — the window-free probe ran; do not spawn xrdb again.
#   _DISPLAY_SCALE_DETECTED — a real scale was found; no later phase may change it.
const _DISPLAY_SCALE_PROBED   = Ref(false)
const _DISPLAY_SCALE_DETECTED = Ref(false)

function _detect_display_scale!()
    _DISPLAY_SCALE_PROBED[] && return _DISPLAY_SCALE_DETECTED[]
    _DISPLAY_SCALE_PROBED[] = true

    # 1. Explicit override.
    env_val = get(ENV, "PROJECTURED_DISPLAY_SCALE", "")
    if !isempty(env_val)
        scale = tryparse(Float64, env_val)
        if scale !== nothing && scale > 0
            _BASE_DISPLAY_SCALE[] = scale; recompute_display_scale!()
            _DISPLAY_SCALE_DETECTED[] = true
            println("Display scale: $(_BASE_DISPLAY_SCALE[]) (PROJECTURED_DISPLAY_SCALE)")
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
                    _BASE_DISPLAY_SCALE[] = xft_dpi / 96.0; recompute_display_scale!()
                    _DISPLAY_SCALE_DETECTED[] = true
                    println("Display scale: $(_BASE_DISPLAY_SCALE[]) (Xft.dpi = $xft_dpi)")
                    return true
                end
            end
        catch
            # xrdb not installed or failed — fall through.
        end
    end

    return false
end

function _update_display_scale!(win::Ptr{SDL_Window}, renderer::Ptr{SDL_Renderer})
    # Skip if a window-free phase already found the scale.
    _DISPLAY_SCALE_DETECTED[] && return

    # SDL renderer output size vs logical window size.
    dw = Ref{Cint}(0); dh = Ref{Cint}(0)
    ww = Ref{Cint}(0); wh = Ref{Cint}(0)
    SDL_GetRendererOutputSize(renderer, dw, dh)
    SDL_GetWindowSize(win, ww, wh)
    if ww[] > 0 && dw[] > ww[]
        _BASE_DISPLAY_SCALE[] = Float64(dw[]) / Float64(ww[]); recompute_display_scale!()
        _DISPLAY_SCALE_DETECTED[] = true
        println("Display scale: $(_BASE_DISPLAY_SCALE[]) (SDL renderer ratio)")
        return
    end

    # SDL DPI fallback (Windows / some X11 setups).
    display_index = SDL_GetWindowDisplayIndex(win)
    display_index < 0 && return
    ddpi = Ref{Cfloat}(0)
    hdpi = Ref{Cfloat}(0)
    vdpi = Ref{Cfloat}(0)
    if SDL_GetDisplayDPI(display_index, ddpi, hdpi, vdpi) == 0 && ddpi[] > 0
        _BASE_DISPLAY_SCALE[] = Float64(ddpi[]) / 96.0; recompute_display_scale!()
        _DISPLAY_SCALE_DETECTED[] = true
        println("Display scale: $(_BASE_DISPLAY_SCALE[]) (SDL DPI = $(ddpi[]))")
    end
end

# Destroy one native SDL window. Loaded fonts persist in the
# module-level cache until `quit_backend!`.
function _close_native_window!(res::SdlWindowResources)
    res.target != C_NULL && SDL_DestroyTexture(res.target)
    _evict_renderer_textures!(res.renderer)
    SDL_DestroyRenderer(res.renderer)
    SDL_DestroyWindow(res.win)
end

# ── Font resolution ────────────────────────────────────────────────────

function _get_font(font::StyleFont)
    size = font_device_size(font)
    key = (font.filename, size)
    get!(_font_cache, key) do
        f = TTF_OpenFont(font.filename, size)
        @assert f != C_NULL "Font load failed: $(font.filename)@$(size)"
        f
    end
end

# ── Emoji fallback font ────────────────────────────────────────────────
#
# The bundled text fonts (Ubuntu, DejaVu, Liberation) carry no emoji glyphs, and
# SDL2_ttf has no fallback-font mechanism, so emoji codepoints would otherwise
# rasterize as `.notdef` boxes. We bundle a *monochrome* emoji font — it renders
# through the same blended path, with none of SDL2's fragile colour-emoji
# plumbing — and route glyphs the primary font lacks to it (see `_font_runs`).
const _EMOJI_FONT_FILE = joinpath(_FONT_DIR, "NotoEmoji-Regular.ttf")

# Open (and cache) the emoji font at `size` device px. Returns C_NULL when the
# font is absent or fails to load, so callers transparently degrade to the
# primary font (i.e. today's box behaviour) instead of erroring.
function _get_emoji_font(size::Int)
    key = (_EMOJI_FONT_FILE, size)
    get!(_font_cache, key) do
        isfile(_EMOJI_FONT_FILE) ? TTF_OpenFont(_EMOJI_FONT_FILE, size) : Ptr{TTF_Font}(C_NULL)
    end
end

# Which font should render codepoint `cp`? SDL2_ttf does no shaping and
# `TTF_GlyphIsProvided` is BMP-only (UInt16), so: astral-plane codepoints (nearly
# all pictographic emoji) go to the emoji font; for BMP codepoints we keep glyphs
# the primary font actually has (✓ ★ → and box-drawing render best there) and
# fall back to the emoji font only for the ones it lacks.
@inline function _glyph_font(cp::UInt32, primary::Ptr{TTF_Font}, emoji::Ptr{TTF_Font})
    emoji == C_NULL && return primary
    if cp > 0xFFFF
        return emoji
    elseif TTF_GlyphIsProvided(primary, UInt16(cp)) != 0
        return primary
    elseif TTF_GlyphIsProvided(emoji, UInt16(cp)) != 0
        return emoji
    else
        return primary
    end
end

# Split `text` into maximal consecutive runs that share one font. Variation
# selectors (U+FE0E/U+FE0F) are dropped — zero-width presentation hints that
# would otherwise draw a stray box in the emoji font; ZWJ (U+200D) and skin-tone
# modifiers stay in the current run so they bind to the preceding emoji. With no
# emoji font loaded this returns a single primary-font run (the fast path). Note:
# without shaping, ZWJ/skin-tone sequences render as their separate base glyphs.
function _font_runs(text::AbstractString, primary::Ptr{TTF_Font}, emoji::Ptr{TTF_Font})
    runs = Tuple{Ptr{TTF_Font},String}[]
    if emoji == C_NULL
        push!(runs, (primary, String(text)))
        return runs
    end
    buf = IOBuffer()
    cur = primary
    started = false
    for ch in text
        cp = UInt32(ch)
        (cp == 0xFE0E || cp == 0xFE0F) && continue          # drop variation selectors
        sticky = started && (cp == 0x200D || 0x1F3FB <= cp <= 0x1F3FF)
        f = sticky ? cur : _glyph_font(cp, primary, emoji)
        if !started
            cur = f
        elseif f !== cur
            push!(runs, (cur, String(take!(buf))))
            cur = f
        end
        print(buf, ch)
        started = true
    end
    started && push!(runs, (cur, String(take!(buf))))
    return runs
end

# Rasterize multi-font `runs` into one blended surface, laid out left-to-right and
# aligned on the text baseline (each run's surface sits its glyphs on the baseline
# at `TTF_FontAscent` from its top). Returns C_NULL if nothing rendered. The
# caller treats the result exactly like a single `TTF_RenderUTF8_Blended` surface
# (upload, query size, free).
function _render_runs_blended(runs::Vector{Tuple{Ptr{TTF_Font},String}}, color::NTuple{4,UInt8})
    col = SDL_Color(color...)
    pieces = Tuple{Ptr{SDL_Surface},Int,Int,Int}[]   # (surface, w, h, ascent)
    total_w = 0; max_ascent = 0; max_below = 0
    for (f, s) in runs
        isempty(s) && continue
        srf = TTF_RenderUTF8_Blended(f, s, col)
        srf == C_NULL && continue
        su = unsafe_load(srf)
        asc = Int(TTF_FontAscent(f))
        push!(pieces, (srf, Int(su.w), Int(su.h), asc))
        total_w += Int(su.w)
        max_ascent = max(max_ascent, asc)
        max_below = max(max_below, Int(su.h) - asc)
    end
    isempty(pieces) && return Ptr{SDL_Surface}(C_NULL)
    height = max_ascent + max_below
    combined = SDL_CreateRGBSurfaceWithFormat(UInt32(0), Cint(total_w), Cint(height),
                                              Cint(32), UInt32(SDL_PIXELFORMAT_ARGB8888))
    if combined == C_NULL
        for (srf, _, _, _) in pieces
            SDL_FreeSurface(srf)
        end
        return Ptr{SDL_Surface}(C_NULL)
    end
    x = 0
    for (srf, w, h, asc) in pieces
        SDL_SetSurfaceBlendMode(srf, SDL_BLENDMODE_NONE)     # straight RGBA copy, no over-blend
        dst = Ref(SDL_Rect(Cint(x), Cint(max_ascent - asc), Cint(w), Cint(h)))
        SDL_BlitSurface(srf, C_NULL, combined, dst)
        x += w
        SDL_FreeSurface(srf)
    end
    return combined
end

# Convert a domain `StyleColor` (Float64 RGBA in [0,1]) to SDL's device bytes.
_rgba8(c::StyleColor) = (UInt8(round(c.red * 255)), UInt8(round(c.green * 255)),
                         UInt8(round(c.blue * 255)), UInt8(round(c.alpha * 255)))

# ── Render a single GraphicsText element ───────────────────────────────

function _render_element!(renderer::Ptr{SDL_Renderer}, elem::GraphicsText, ox::Int, oy::Int)
    text = elem.text::AbstractString
    isempty(text) && return

    font_style = elem.font::StyleFont
    color = _rgba8(elem.color)
    key = _TextTextureKey(renderer, String(text), font_style.filename,
                          font_device_size(font_style), color)

    # Reuse the uploaded texture for an unchanged (text, font, colour) span;
    # rasterize + upload only on a cache miss. The texture is rasterized at
    # device size and freed when its renderer is torn down.
    entry = get(_text_texture_cache, key, nothing)
    if entry === nothing
        font = _get_font(font_style)
        emoji = _get_emoji_font(font_device_size(font_style))
        runs = _font_runs(text, font, emoji)
        surface = length(runs) == 1 ?
            TTF_RenderUTF8_Blended(runs[1][1], runs[1][2], SDL_Color(color...)) :
            _render_runs_blended(runs, color)
        surface == C_NULL && return
        texture = SDL_CreateTextureFromSurface(renderer, surface)
        w_ref, h_ref = Ref{Cint}(0), Ref{Cint}(0)
        SDL_QueryTexture(texture, C_NULL, C_NULL, w_ref, h_ref)
        SDL_FreeSurface(surface)
        length(_text_texture_cache) >= _TEXT_TEXTURE_CACHE_CAP && _clear_text_texture_cache!()
        entry = _TextTexture(texture, Int(w_ref[]), Int(h_ref[]))
        _text_texture_cache[key] = entry
    end

    # The destination rect is in logical pixels (= device size ÷ scale). The
    # renderer scale then maps it back to device pixels, so the texture lands
    # 1:1 and stays crisp.
    dest = Ref(SDL_Rect(elem.x + ox, elem.y + oy,
                        Int32(_to_logical(entry.dw)), Int32(_to_logical(entry.dh))))
    SDL_RenderCopy(renderer, entry.texture, C_NULL, dest)
end

# ── Render a GraphicsViewport element ────────────────────────────────

function _render_viewport!(renderer::Ptr{SDL_Renderer}, vp::GraphicsViewport, ox::Int, oy::Int)
    vx = Int(vp.x) + ox
    vy = Int(vp.y) + oy
    vw = Int(vp.w)
    vh = Int(vp.h)
    canvas = vp.content::GraphicsCanvas
    cx, cy = Int(canvas.x), Int(canvas.y)
    M = vp.transform::AffineTransform
    if M === affine_identity || (M.a == 1.0 && M.d == 1.0 && M.e == 0.0 && M.f == 0.0 &&
                                 affine_is_axis_aligned(M))
        # Fast path: identity transform — clip + draw exactly as before.
        clip = Ref(SDL_Rect(Int32(vx), Int32(vy), Int32(vw), Int32(vh)))
        SDL_RenderSetClipRect(renderer, clip)
        _render_canvas!(renderer, canvas, vx + cx, vy + cy, vx + vw, vy + vh)
        SDL_RenderSetClipRect(renderer, C_NULL)
        return
    end
    # Translate+scale path. Rotation/shear (off-diagonal) is dropped for now —
    # only the scale (a, d) and translation (e, f) are honoured.
    sx = M.a == 0.0 ? 1.0 : M.a
    sy = M.d == 0.0 ? 1.0 : M.d
    tx = M.e
    ty = M.f
    # Compose the content scale onto the active render scale. Reading the
    # current scale keeps this correct under the display scale and the
    # offscreen supersample factor (see `_render_window!` / `write_image`).
    fx = Ref{Cfloat}(0); fy = Ref{Cfloat}(0)
    SDL_RenderGetScale(renderer, fx, fy)
    base_x = Float64(fx[]); base_x <= 0 && (base_x = 1.0)
    base_y = Float64(fy[]); base_y <= 0 && (base_y = 1.0)
    SDL_RenderSetScale(renderer, Cfloat(base_x * sx), Cfloat(base_y * sy))
    # Set the clip *after* the scale change, expressed in the new logical units
    # (old-logical ÷ scale), so it lands on the same device rectangle as the
    # viewport box regardless of the content scale.
    clip = Ref(SDL_Rect(Int32(round(vx / sx)), Int32(round(vy / sy)),
                        Int32(round(vw / sx)), Int32(round(vh / sy))))
    SDL_RenderSetClipRect(renderer, clip)
    # A content-local element coord `l` must land at viewport-space `t + s*(c+l)`;
    # under the scaled renderer the passed origin is therefore `(v+t)/s + c`.
    org_x = round(Int, (vx + tx) / sx) + cx
    org_y = round(Int, (vy + ty) / sy) + cy
    clip_r = round(Int, (vx + vw) / sx)
    clip_b = round(Int, (vy + vh) / sy)
    _render_canvas!(renderer, canvas, org_x, org_y, clip_r, clip_b)
    SDL_RenderSetClipRect(renderer, C_NULL)
    SDL_RenderSetScale(renderer, Cfloat(base_x), Cfloat(base_y))
end

# ── Render a GraphicsRect element ────────────────────────────────────

# Horizontal inset of a quarter-circle of device-radius `rdev` at device row
# `dydev` (distance from the flat edge). Float so the curve can be sampled at
# device resolution rather than logical-pixel steps.
_corner_inset_dev(rdev::Float64, dydev::Float64) =
    dydev >= rdev ? 0.0 : rdev - sqrt(rdev * rdev - (rdev - dydev) * (rdev - dydev))

# Fill one rounded corner band (top or bottom) one *device* row at a time, so
# the curve is quantized at the renderer's device resolution and the supersample
# downsample anti-aliases it — instead of drawing a logical-resolution staircase
# that `RenderSetScale` then magnifies. `f` = device pixels per logical pixel.
function _fill_corner_band!(renderer::Ptr{SDL_Renderer}, x::Int, y_edge::Int, w::Int,
                            r_left::Int, r_right::Int, band::Int, f::Float64, bottom::Bool)
    band <= 0 && return
    rl = r_left * f
    rr = r_right * f
    n = max(0, round(Int, band * f))
    for i in 0:(n - 1)
        dydev = i + 0.5
        il = _corner_inset_dev(rl, dydev) / f
        ir = _corner_inset_dev(rr, dydev) / f
        span = w - il - ir
        span <= 0 && continue
        ylog = bottom ? (y_edge - (i + 1) / f) : (y_edge + i / f)
        fr = Ref(SDL_FRect(Cfloat(x + il), Cfloat(ylog), Cfloat(span), Cfloat(1.0 / f)))
        SDL_RenderFillRectF(renderer, fr)
    end
end

# Fill a rounded rectangle (per-corner radii) with the renderer's current draw
# color. Shared by GraphicsRect fill and border.
function _fill_rounded!(renderer::Ptr{SDL_Renderer}, x::Int, y::Int, w::Int, h_px::Int,
                        r_tl::Int, r_tr::Int, r_br::Int, r_bl::Int)
    (w <= 0 || h_px <= 0) && return
    max_r = min(w ÷ 2, h_px ÷ 2)
    r_tl = clamp(r_tl, 0, max_r); r_tr = clamp(r_tr, 0, max_r)
    r_br = clamp(r_br, 0, max_r); r_bl = clamp(r_bl, 0, max_r)
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
    # Device pixels per logical pixel (the active RenderSetScale).
    fx = Ref{Cfloat}(0); fy = Ref{Cfloat}(0)
    SDL_RenderGetScale(renderer, fx, fy)
    f = Float64(fx[]); f <= 0 && (f = 1.0)
    _fill_corner_band!(renderer, x, y,        w, r_tl, r_tr, top_max, f, false)
    _fill_corner_band!(renderer, x, y + h_px, w, r_bl, r_br, bot_max, f, true)
end

# Fill one rounded corner band of a border *ring* — the outer shape minus the
# one inset by `bw` — sampling device rows exactly as `_fill_corner_band!` does.
# A row still inside the border thickness is solid across the outer span; below
# that the row emits two spans (left/right), leaving the interior unpainted.
function _fill_ring_band!(renderer::Ptr{SDL_Renderer}, x::Int, y_edge::Int, w::Int,
                          r_left::Int, r_right::Int, band::Int, bw::Int,
                          f::Float64, bottom::Bool)
    band <= 0 && return
    rl = r_left * f
    rr = r_right * f
    rl_in = max(0, r_left - bw) * f
    rr_in = max(0, r_right - bw) * f
    bw_dev = bw * f
    n = max(0, round(Int, band * f))
    for i in 0:(n - 1)
        dydev = i + 0.5
        il = _corner_inset_dev(rl, dydev) / f
        ir = _corner_inset_dev(rr, dydev) / f
        outer_l = x + il
        outer_r = x + w - ir
        outer_r <= outer_l && continue
        ylog = bottom ? (y_edge - (i + 1) / f) : (y_edge + i / f)
        hlog = 1.0 / f
        dy_in = dydev - bw_dev
        if dy_in <= 0
            fr = Ref(SDL_FRect(Cfloat(outer_l), Cfloat(ylog),
                               Cfloat(outer_r - outer_l), Cfloat(hlog)))
            SDL_RenderFillRectF(renderer, fr)
            continue
        end
        inner_l = x + bw + _corner_inset_dev(rl_in, dy_in) / f
        inner_r = x + w - bw - _corner_inset_dev(rr_in, dy_in) / f
        if inner_l - outer_l > 0
            fr = Ref(SDL_FRect(Cfloat(outer_l), Cfloat(ylog),
                               Cfloat(inner_l - outer_l), Cfloat(hlog)))
            SDL_RenderFillRectF(renderer, fr)
        end
        if outer_r - inner_r > 0
            fr = Ref(SDL_FRect(Cfloat(inner_r), Cfloat(ylog),
                               Cfloat(outer_r - inner_r), Cfloat(hlog)))
            SDL_RenderFillRectF(renderer, fr)
        end
    end
end

# Fill the border ring of a rounded rectangle (per-corner radii) of thickness
# `bw` with the renderer's current draw color, leaving the interior untouched.
function _stroke_rounded_ring!(renderer::Ptr{SDL_Renderer}, x::Int, y::Int, w::Int, h_px::Int,
                               r_tl::Int, r_tr::Int, r_br::Int, r_bl::Int, bw::Int)
    (w <= 0 || h_px <= 0 || bw <= 0) && return
    max_r = min(w ÷ 2, h_px ÷ 2)
    bw = min(bw, max_r)
    bw <= 0 && return
    r_tl = clamp(r_tl, 0, max_r); r_tr = clamp(r_tr, 0, max_r)
    r_br = clamp(r_br, 0, max_r); r_bl = clamp(r_bl, 0, max_r)
    if (r_tl | r_tr | r_br | r_bl) == 0
        # Four edge rectangles that tile the ring without overlapping, so a
        # translucent border color does not double-blend at the corners.
        SDL_RenderFillRect(renderer, Ref(SDL_Rect(Int32(x), Int32(y), Int32(w), Int32(bw))))
        SDL_RenderFillRect(renderer, Ref(SDL_Rect(Int32(x), Int32(y + h_px - bw),
                                                  Int32(w), Int32(bw))))
        side_h = h_px - 2bw
        if side_h > 0
            SDL_RenderFillRect(renderer, Ref(SDL_Rect(Int32(x), Int32(y + bw),
                                                      Int32(bw), Int32(side_h))))
            SDL_RenderFillRect(renderer, Ref(SDL_Rect(Int32(x + w - bw), Int32(y + bw),
                                                      Int32(bw), Int32(side_h))))
        end
        return
    end
    # The corner bands run to at least the border thickness, so a border wider
    # than its radius still gets its straight part painted there rather than
    # falling into the gap between the bands and the side spans.
    top_band = max(max(r_tl, r_tr), bw)
    bot_band = max(max(r_bl, r_br), bw)
    mid_h = h_px - top_band - bot_band
    if mid_h > 0
        left = Ref(SDL_Rect(Int32(x), Int32(y + top_band), Int32(bw), Int32(mid_h)))
        SDL_RenderFillRect(renderer, left)
        right = Ref(SDL_Rect(Int32(x + w - bw), Int32(y + top_band), Int32(bw), Int32(mid_h)))
        SDL_RenderFillRect(renderer, right)
    end
    fx = Ref{Cfloat}(0); fy = Ref{Cfloat}(0)
    SDL_RenderGetScale(renderer, fx, fy)
    f = Float64(fx[]); f <= 0 && (f = 1.0)
    _fill_ring_band!(renderer, x, y,        w, r_tl, r_tr, top_band, bw, f, false)
    _fill_ring_band!(renderer, x, y + h_px, w, r_bl, r_br, bot_band, bw, f, true)
end

function _render_rect!(renderer::Ptr{SDL_Renderer}, rect::GraphicsRect, ox::Int, oy::Int)
    x, y = Int(rect.x) + ox, Int(rect.y) + oy
    w, h_px = Int(rect.w), Int(rect.h)
    r_tl, r_tr = Int(rect.radius_tl), Int(rect.radius_tr)
    r_br, r_bl = Int(rect.radius_br), Int(rect.radius_bl)
    bw = Int(rect.border_width)
    if bw > 0 && rect.border_color.alpha > 0
        if rect.color.alpha >= 1
            # Opaque fill: outer border-colored rounded rect, then the fill inset
            # by the border width (radii shrink to stay concentric), so the two
            # shapes' anti-aliased seam blends fill over border.
            SDL_SetRenderDrawColor(renderer, _rgba8(rect.border_color)...)
            _fill_rounded!(renderer, x, y, w, h_px, r_tl, r_tr, r_br, r_bl)
            SDL_SetRenderDrawColor(renderer, _rgba8(rect.color)...)
            _fill_rounded!(renderer, x + bw, y + bw, w - 2bw, h_px - 2bw,
                           max(0, r_tl - bw), max(0, r_tr - bw),
                           max(0, r_br - bw), max(0, r_bl - bw))
        else
            # Translucent (or absent) fill: the border has to be a true ring, or
            # the fill would composite against the border color instead of
            # against whatever is behind the rect.
            if rect.color.alpha > 0
                SDL_SetRenderDrawColor(renderer, _rgba8(rect.color)...)
                _fill_rounded!(renderer, x + bw, y + bw, w - 2bw, h_px - 2bw,
                               max(0, r_tl - bw), max(0, r_tr - bw),
                               max(0, r_br - bw), max(0, r_bl - bw))
            end
            SDL_SetRenderDrawColor(renderer, _rgba8(rect.border_color)...)
            _stroke_rounded_ring!(renderer, x, y, w, h_px, r_tl, r_tr, r_br, r_bl, bw)
        end
    else
        SDL_SetRenderDrawColor(renderer, _rgba8(rect.color)...)
        _fill_rounded!(renderer, x, y, w, h_px, r_tl, r_tr, r_br, r_bl)
    end
end

# ── Render a GraphicsLine element ────────────────────────────────────

# Draw one straight stroke span from (x1,y1) to (x2,y2) of width `wdt` using the
# renderer's current draw color. Axis-aligned spans render as a crisp filled
# rect; diagonals as an anti-aliased quad. Shared by solid and dashed lines.
function _draw_line_span!(renderer::Ptr{SDL_Renderer}, x1::Int, y1::Int, x2::Int, y2::Int,
                          wdt::Int, r::UInt8, g::UInt8, b::UInt8, a::UInt8)
    if y1 == y2          # horizontal rule
        SDL_RenderFillRect(renderer, Ref(SDL_Rect(Int32(min(x1, x2)), Int32(y1 - wdt ÷ 2),
                                                  Int32(abs(x2 - x1) + 1), Int32(wdt))))
    elseif x1 == x2      # vertical rule
        SDL_RenderFillRect(renderer, Ref(SDL_Rect(Int32(x1 - wdt ÷ 2), Int32(min(y1, y2)),
                                                  Int32(wdt), Int32(abs(y2 - y1) + 1))))
    else                 # diagonal: one filled quad (two triangles)
        # SDL's line primitive is not anti-aliased. Draw the stroke as a quad
        # whose edges are rasterized at device resolution, so the supersample
        # downsample anti-aliases them — O(1) regardless of length.
        _fill_thick_line!(renderer, Float64(x1), Float64(y1), Float64(x2), Float64(y2),
                          Float64(wdt), r, g, b, a)
    end
end

function _render_line!(renderer::Ptr{SDL_Renderer}, line::GraphicsLine, ox::Int, oy::Int)
    lr, lg, lb, la = _rgba8(line.color)
    SDL_SetRenderDrawColor(renderer, lr, lg, lb, la)
    x1, y1 = Int(line.x1) + ox, Int(line.y1) + oy
    x2, y2 = Int(line.x2) + ox, Int(line.y2) + oy
    wdt = max(1, Int(line.width))
    dash = line.dash
    if dash === nothing
        _draw_line_span!(renderer, x1, y1, x2, y2, wdt, lr, lg, lb, la)
    else
        # Step the (on, off) pattern along the line, emitting one span per "on"
        # run. Rounding the endpoints keeps axis-aligned dashes crisp (one of
        # the unit components is exactly zero) and lets diagonals follow the slope.
        on, off = max(1, Int(dash[1])), max(1, Int(dash[2]))
        dx, dy = x2 - x1, y2 - y1
        len = sqrt(Float64(dx * dx + dy * dy))
        if len == 0
            _draw_line_span!(renderer, x1, y1, x2, y2, wdt, lr, lg, lb, la)
        else
            ux, uy = dx / len, dy / len
            pos = 0.0
            while pos < len
                e = min(pos + on, len)
                sx = round(Int, x1 + ux * pos); sy = round(Int, y1 + uy * pos)
                ex = round(Int, x1 + ux * e);   ey = round(Int, y1 + uy * e)
                _draw_line_span!(renderer, sx, sy, ex, ey, wdt, lr, lg, lb, la)
                pos = e + off
            end
        end
    end
end

# Filled, square-capped thick line from (x1,y1) to (x2,y2) of width `wdt`, drawn
# as two triangles via SDL_RenderGeometry. Square caps (endpoints extended by
# half the width) make joined segments — chevrons, checkmarks — meet cleanly.
function _fill_thick_line!(renderer::Ptr{SDL_Renderer}, x1::Float64, y1::Float64,
                           x2::Float64, y2::Float64, wdt::Float64,
                           r::UInt8, g::UInt8, b::UInt8, a::UInt8)
    dx = x2 - x1; dy = y2 - y1
    len = sqrt(dx * dx + dy * dy)
    len == 0 && return
    hw = wdt / 2
    ux = dx / len; uy = dy / len          # unit along the line
    px = -uy * hw;  py = ux * hw           # perpendicular half-width
    ex = ux * hw;   ey = uy * hw           # square-cap extension
    x1c = x1 - ex; y1c = y1 - ey
    x2c = x2 + ex; y2c = y2 + ey
    col = SDL_Color(r, g, b, a)
    z = SDL_FPoint(0.0f0, 0.0f0)
    verts = SDL_Vertex[
        SDL_Vertex(SDL_FPoint(Cfloat(x1c - px), Cfloat(y1c - py)), col, z),
        SDL_Vertex(SDL_FPoint(Cfloat(x1c + px), Cfloat(y1c + py)), col, z),
        SDL_Vertex(SDL_FPoint(Cfloat(x2c + px), Cfloat(y2c + py)), col, z),
        SDL_Vertex(SDL_FPoint(Cfloat(x2c - px), Cfloat(y2c - py)), col, z),
    ]
    idx = Cint[0, 1, 2, 0, 2, 3]
    GC.@preserve verts idx begin
        SDL_RenderGeometry(renderer, Ptr{SDL_Texture}(C_NULL),
                           pointer(verts), Cint(4), pointer(idx), Cint(6))
    end
end

# ── Render polyline / spline edges (+ arrowheads) ────────────────────

# Fill the triangle `verts` (three (x,y) floats) with the current draw color.
function _fill_triangle!(renderer::Ptr{SDL_Renderer}, verts3,
                         r::UInt8, g::UInt8, b::UInt8, a::UInt8)
    col = SDL_Color(r, g, b, a)
    z = SDL_FPoint(0.0f0, 0.0f0)
    verts = SDL_Vertex[
        SDL_Vertex(SDL_FPoint(Cfloat(verts3[1][1]), Cfloat(verts3[1][2])), col, z),
        SDL_Vertex(SDL_FPoint(Cfloat(verts3[2][1]), Cfloat(verts3[2][2])), col, z),
        SDL_Vertex(SDL_FPoint(Cfloat(verts3[3][1]), Cfloat(verts3[3][2])), col, z),
    ]
    idx = Cint[0, 1, 2]
    GC.@preserve verts idx begin
        SDL_RenderGeometry(renderer, Ptr{SDL_Texture}(C_NULL),
                           pointer(verts), Cint(3), pointer(idx), Cint(3))
    end
end

# Draw a connected polyline of (x,y) floats with stroke width `wdt`, honouring
# an (on, off) dash pattern. The on/off cycle is stepped once across the whole
# path — `remaining` carries over from one segment to the next — so a corner
# falls wherever the cycle happens to land rather than restarting the pattern
# at each vertex.
function _stroke_polyline_dashed!(renderer::Ptr{SDL_Renderer}, pts, wdt::Float64,
                                  r::UInt8, g::UInt8, b::UInt8, a::UInt8,
                                  on::Int, off::Int)
    n = length(pts)
    on_run = true
    remaining = Float64(on)
    for i in 1:(n-1)
        x1, y1 = Float64(pts[i][1]), Float64(pts[i][2])
        x2, y2 = Float64(pts[i+1][1]), Float64(pts[i+1][2])
        dx, dy = x2 - x1, y2 - y1
        seglen = sqrt(dx * dx + dy * dy)
        seglen == 0 && continue
        ux, uy = dx / seglen, dy / seglen
        pos = 0.0
        while pos < seglen
            if remaining <= 0
                on_run = !on_run
                remaining = on_run ? Float64(on) : Float64(off)
            end
            step = min(remaining, seglen - pos)
            if on_run
                sx = x1 + ux * pos;          sy = y1 + uy * pos
                ex = x1 + ux * (pos + step); ey = y1 + uy * (pos + step)
                _fill_thick_line!(renderer, sx, sy, ex, ey, wdt, r, g, b, a)
            end
            pos += step
            remaining -= step
        end
    end
end

# Draw a connected polyline of (x,y) floats with stroke width `wdt`, plus
# optional arrowheads and an optional (on, off) dash pattern. Each solid
# segment is a filled quad (anti-aliased by the supersample downsample),
# matching the diagonal-GraphicsLine path. Arrowheads are always solid.
function _stroke_polyline!(renderer::Ptr{SDL_Renderer}, pts, wdt::Int,
                           r::UInt8, g::UInt8, b::UInt8, a::UInt8,
                           start_arrow::Bool, end_arrow::Bool, arrow_size::Int,
                           dash=nothing)
    n = length(pts)
    n == 0 && return
    SDL_SetRenderDrawColor(renderer, r, g, b, a)
    w = Float64(max(1, wdt))
    if dash === nothing
        for i in 1:(n-1)
            x1, y1 = Float64(pts[i][1]), Float64(pts[i][2])
            x2, y2 = Float64(pts[i+1][1]), Float64(pts[i+1][2])
            _fill_thick_line!(renderer, x1, y1, x2, y2, w, r, g, b, a)
        end
    else
        on, off = max(1, Int(dash[1])), max(1, Int(dash[2]))
        _stroke_polyline_dashed!(renderer, pts, w, r, g, b, a, on, off)
    end
    if end_arrow
        tri = polyline_arrowhead(pts, arrow_size; at_end=true)
        isempty(tri) || _fill_triangle!(renderer, tri, r, g, b, a)
    end
    if start_arrow
        tri = polyline_arrowhead(pts, arrow_size; at_end=false)
        isempty(tri) || _fill_triangle!(renderer, tri, r, g, b, a)
    end
end

function _render_polyline!(renderer::Ptr{SDL_Renderer}, pl::GraphicsPolyline, ox::Int, oy::Int)
    pl.color.alpha == 0 && return
    pts = [(Int(p[1]) + ox, Int(p[2]) + oy) for p in pl.points]
    _stroke_polyline!(renderer, pts, Int(pl.width), _rgba8(pl.color)...,
                      pl.start_arrow, pl.end_arrow, Int(pl.arrow_size), pl.dash)
end

# ── Render a GraphicsPolygon element ─────────────────────────────────

# Twice the signed area of the polygon `pts` (the shoelace sum). Its sign is the
# winding order.
function _polygon_area2(pts)
    n = length(pts)
    a = 0.0
    for i in 1:n
        j = i == n ? 1 : i + 1
        a += pts[i][1] * pts[j][2] - pts[j][1] * pts[i][2]
    end
    a
end

# Cross product of (b - a) × (c - a): positive when a→b→c turns the same way as
# a polygon whose shoelace area is positive.
_polygon_cross(a, b, c) =
    (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1])

# True when `p` is inside (or on) the triangle a-b-c, which must be wound so its
# cross products are positive.
function _point_in_triangle(p, a, b, c)
    _polygon_cross(a, b, p) >= 0 && _polygon_cross(b, c, p) >= 0 &&
        _polygon_cross(c, a, p) >= 0
end

# Triangulate the simple polygon `pts` by ear clipping, returning triangles as
# 1-based index triples into `pts`. A triangle fan would only cover convex
# outlines and a star marker is concave, so the ears are found the general way:
# repeatedly clip a convex vertex whose triangle holds no other vertex. Either
# winding order is accepted — the vertex order is reversed when needed so the
# convexity test has one sign to look for.
function _polygon_triangles(pts)
    n = length(pts)
    n < 3 && return Tuple{Int,Int,Int}[]
    remaining = _polygon_area2(pts) < 0 ? collect(n:-1:1) : collect(1:n)
    tris = Tuple{Int,Int,Int}[]
    while length(remaining) > 3
        m = length(remaining)
        clipped = false
        for k in 1:m
            i0 = remaining[k == 1 ? m : k - 1]
            i1 = remaining[k]
            i2 = remaining[k == m ? 1 : k + 1]
            a = pts[i0]; b = pts[i1]; c = pts[i2]
            _polygon_cross(a, b, c) <= 0 && continue      # reflex or collinear
            blocked = false
            for q in remaining
                (q == i0 || q == i1 || q == i2) && continue
                if _point_in_triangle(pts[q], a, b, c)
                    blocked = true
                    break
                end
            end
            blocked && continue
            push!(tris, (i0, i1, i2))
            deleteat!(remaining, k)
            clipped = true
            break
        end
        if !clipped
            # No ear left: the outline self-intersects or is degenerate. Fan the
            # rest so the shape still paints something instead of looping.
            for k in 2:(length(remaining) - 1)
                push!(tris, (remaining[1], remaining[k], remaining[k + 1]))
            end
            return tris
        end
    end
    push!(tris, (remaining[1], remaining[2], remaining[3]))
    tris
end

# Fill the closed polygon `pts` ((x,y) floats) as one SDL_RenderGeometry batch
# over its ear-clipped triangles.
function _fill_polygon!(renderer::Ptr{SDL_Renderer}, pts,
                        r::UInt8, g::UInt8, b::UInt8, a::UInt8)
    tris = _polygon_triangles(pts)
    isempty(tris) && return
    col = SDL_Color(r, g, b, a)
    z = SDL_FPoint(0.0f0, 0.0f0)
    verts = SDL_Vertex[SDL_Vertex(SDL_FPoint(Cfloat(p[1]), Cfloat(p[2])), col, z) for p in pts]
    idx = Cint[]
    for t in tris
        push!(idx, Cint(t[1] - 1), Cint(t[2] - 1), Cint(t[3] - 1))
    end
    GC.@preserve verts idx begin
        SDL_RenderGeometry(renderer, Ptr{SDL_Texture}(C_NULL),
                           pointer(verts), Cint(length(verts)),
                           pointer(idx), Cint(length(idx)))
    end
end

function _render_polygon!(renderer::Ptr{SDL_Renderer}, pg::GraphicsPolygon, ox::Int, oy::Int)
    pts = [(Float64(p[1]) + ox, Float64(p[2]) + oy) for p in pg.points]
    length(pts) < 3 && return
    pg.color.alpha > 0 && _fill_polygon!(renderer, pts, _rgba8(pg.color)...)
    bw = Int(pg.border_width)
    if bw > 0 && pg.border_color.alpha > 0
        # Repeat the first vertex so the stroke closes the outline.
        _stroke_polyline!(renderer, push!(copy(pts), pts[1]), bw,
                          _rgba8(pg.border_color)..., false, false, 0)
    end
end

function _render_spline!(renderer::Ptr{SDL_Renderer}, sp::GraphicsSpline, ox::Int, oy::Int)
    sp.color.alpha == 0 && return
    tess = tessellate_spline(sp.points, sp.kind, sp.segments)
    pts = [(p[1] + ox, p[2] + oy) for p in tess]
    _stroke_polyline!(renderer, pts, Int(sp.width), _rgba8(sp.color)...,
                      sp.start_arrow, sp.end_arrow, Int(sp.arrow_size), sp.dash)
end

# ── Render a GraphicsCircle element ──────────────────────────────────

# Fill a disc of `rad` centered at (cx,cy) using the current draw color.
# Scanlines are sampled at the renderer's *device* resolution (one float rect
# per device row) so the supersample downsample anti-aliases the circumference,
# rather than drawing a logical-resolution staircase that RenderSetScale then
# magnifies.
function _fill_disc!(renderer::Ptr{SDL_Renderer}, cx::Int, cy::Int, rad::Int)
    rad <= 0 && return
    fx = Ref{Cfloat}(0); fy = Ref{Cfloat}(0)
    SDL_RenderGetScale(renderer, fx, fy)
    f = Float64(fx[]); f <= 0 && (f = 1.0)
    n = round(Int, rad * f)               # device rows from centre to edge
    for k in -n:(n - 1)
        yc = (k + 0.5) / f                # logical y offset at the device-row centre
        half = sqrt(max(0.0, rad * rad - yc * yc))
        half <= 0 && continue
        fr = Ref(SDL_FRect(Cfloat(cx - half), Cfloat(cy + k / f),
                           Cfloat(2 * half), Cfloat(1.0 / f)))
        SDL_RenderFillRectF(renderer, fr)
    end
end

# Stroke a ring (annulus) of border `bw` at outer radius `rad`, current draw
# color. Like `_fill_disc!` it samples one float rect per *device* row so the
# supersample downsample anti-aliases both edges; rows that clear the inner
# radius emit two bands (left/right) leaving the centre transparent.
function _stroke_ring!(renderer::Ptr{SDL_Renderer}, cx::Int, cy::Int, rad::Int, bw::Int)
    rad <= 0 && return
    bw = clamp(bw, 1, rad)
    rin = rad - bw
    fx = Ref{Cfloat}(0); fy = Ref{Cfloat}(0)
    SDL_RenderGetScale(renderer, fx, fy)
    f = Float64(fx[]); f <= 0 && (f = 1.0)
    n = round(Int, rad * f)
    for k in -n:(n - 1)
        yc = (k + 0.5) / f
        outer = sqrt(max(0.0, rad * rad - yc * yc))
        outer <= 0 && continue
        ylog = cy + k / f
        h = 1.0 / f
        if rin <= 0 || abs(yc) >= rin
            SDL_RenderFillRectF(renderer, Ref(SDL_FRect(Cfloat(cx - outer), Cfloat(ylog),
                                                        Cfloat(2 * outer), Cfloat(h))))
        else
            inner = sqrt(max(0.0, rin * rin - yc * yc))
            band = outer - inner
            band <= 0 && continue
            SDL_RenderFillRectF(renderer, Ref(SDL_FRect(Cfloat(cx - outer), Cfloat(ylog),
                                                        Cfloat(band), Cfloat(h))))
            SDL_RenderFillRectF(renderer, Ref(SDL_FRect(Cfloat(cx + inner), Cfloat(ylog),
                                                        Cfloat(band), Cfloat(h))))
        end
    end
end

function _render_circle!(renderer::Ptr{SDL_Renderer}, circ::GraphicsCircle, ox::Int, oy::Int)
    cx, cy = Int(circ.cx) + ox, Int(circ.cy) + oy
    rad = Int(circ.radius)
    bw = Int(circ.border_width)
    if bw > 0 && circ.border_color.alpha > 0
        SDL_SetRenderDrawColor(renderer, _rgba8(circ.border_color)...)
        if circ.color.alpha > 0
            # Opaque fill: paint the border-colored disc, then the fill inset by
            # the border so a solid rim remains.
            _fill_disc!(renderer, cx, cy, rad)
            SDL_SetRenderDrawColor(renderer, _rgba8(circ.color)...)
            _fill_disc!(renderer, cx, cy, rad - bw)
        else
            # Transparent fill: a true hollow ring, leaving the centre unpainted.
            _stroke_ring!(renderer, cx, cy, rad, bw)
        end
    else
        SDL_SetRenderDrawColor(renderer, _rgba8(circ.color)...)
        _fill_disc!(renderer, cx, cy, rad)
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
    elseif elem isa GraphicsLine
        _render_line!(renderer, elem, ox, oy)
    elseif elem isa GraphicsPolyline
        _render_polyline!(renderer, elem, ox, oy)
    elseif elem isa GraphicsPolygon
        _render_polygon!(renderer, elem, ox, oy)
    elseif elem isa GraphicsSpline
        _render_spline!(renderer, elem, ox, oy)
    elseif elem isa GraphicsCircle
        _render_circle!(renderer, elem, ox, oy)
    elseif elem isa GraphicsViewport
        _render_viewport!(renderer, elem, ox, oy)
    elseif elem isa GraphicsImage
        _render_image!(renderer, elem, ox, oy)
    elseif elem isa GraphicsCanvas
        # Nested canvas: offset its origin by its position. `vw`/`vh` are the
        # *absolute* screen-space clip edges (right/bottom) used only by the
        # early-stop culling, so they are passed through unchanged — a child's
        # local offset moves `oy` (and thus the element's absolute y), not the
        # clip bound. Subtracting the offset here culled lower/deeper content
        # prematurely (e.g. chat-bubble bodies past the first viewport-height).
        cx, cy = Int(elem.x), Int(elem.y)
        _render_canvas!(renderer, elem, ox + cx, oy + cy, vw, vh)
    end
    # GraphicsFence and unknown types are silently skipped
end

_render_elem_x(elem) = hasproperty(elem, :x) ? Int(elem.x) : nothing
_render_elem_y(elem) = hasproperty(elem, :y) ? Int(elem.y) : nothing

# ── Per-window paint ──────────────────────────────────────────────────

# Clear and repaint one native window's canvas. Called by the
# reconciler once per WindowDocument per frame.
# Ensure the SSAA render target exists and matches the device backbuffer size
# times the supersample factor (`width*scale*ss × height*scale*ss`), recreating
# it on size change. Returns true if a usable target is in place.
function _ensure_ss_target!(res::SdlWindowResources)
    tw, th = _to_device(res.width) * res.ss, _to_device(res.height) * res.ss
    (tw <= 0 || th <= 0) && return false
    if res.target != C_NULL && (res.target_w != tw || res.target_h != th)
        SDL_DestroyTexture(res.target); res.target = C_NULL
    end
    if res.target == C_NULL
        res.target = SDL_CreateTexture(res.renderer, UInt32(SDL_PIXELFORMAT_RGBA8888),
                                       Int32(SDL_TEXTUREACCESS_TARGET), Int32(tw), Int32(th))
        res.target == C_NULL && return false
        res.target_w, res.target_h = tw, th
        # A fresh target holds undefined pixels and invalidates any cached
        # dirty-unit bounds — repaint the whole window next frame.
        res.first_paint = true
        empty!(res.dirty_bounds)
    end
    true
end

# ── Dirty-rectangle analysis ─────────────────────────────────────────────
#
# Walk the canvas tree (mirroring `_render_canvas!`'s offset accumulation) and
# return the smallest absolute logical rectangle covering every *invalidated*
# graphic, or `nothing` if nothing changed. Detection keys on the reactive
# `valid` flag of the relevant cells, tested via `is_cell_up_to_date` *before* the value
# is read (reading recomputes). Because writing a primitive cell marks it valid
# (only its dependents go stale), the detectable dirty units are the *computed*
# container cells the projection pipeline invalidates — a canvas whose
# `CellVector`-backed `elements` (or geometry) cell is stale, or a `ListNode`
# whose spine / value cells are stale — plus any leaf whose own field cell is
# stale (in-place mutation). For each dirty unit we union its *new* bounds with
# its *previous* rendered bounds (cached in `res.dirty_bounds`, keyed by
# `objectid`) so content that moved, shrank or was removed still clears its
# vacated pixels.

# Mutable accumulator for a union of absolute logical bounds.
mutable struct _DirtyAcc
    minx::Int; miny::Int; maxx::Int; maxy::Int
end
_DirtyAcc() = _DirtyAcc(typemax(Int), typemax(Int), typemin(Int), typemin(Int))
_acc_extend!(a::_DirtyAcc, b::NTuple{4,Int}) =
    (a.minx = min(a.minx, b[1]); a.miny = min(a.miny, b[2]);
     a.maxx = max(a.maxx, b[3]); a.maxy = max(a.maxy, b[4]); nothing)
_acc_empty(a::_DirtyAcc) = a.maxx == typemin(Int)
_acc_tuple(a::_DirtyAcc) = (a.minx, a.miny, a.maxx, a.maxy)

# True if any of `elem`'s own visual field cells is stale. `:selection` is the
# reader's reference (not rendered) and `:prev`/`:next` are the list spine
# (handled separately), so they never force a repaint on their own.
function _node_dirty(elem)::Bool
    for f in fieldnames(typeof(elem))
        (f === :selection || f === :prev || f === :next) && continue
        c = getfield(elem, f)
        c isa Cell || continue
        is_cell_up_to_date(c) || return true
    end
    false
end

# Bounds of a single element / a whole canvas / a set of list-node values,
# returned as an absolute logical `(x0,y0,x1,y1)` tuple or `nothing` if empty.
# These reuse the existing `_bounds_elem!` / `_accumulate_bounds!` machinery
# (and so recompute the cells they read — exactly what we want, since the unit
# is about to be repainted).
function _bounds_of_elem(elem, ox::Int, oy::Int)
    mnx = Ref(typemax(Int)); mny = Ref(typemax(Int))
    mxx = Ref(typemin(Int)); mxy = Ref(typemin(Int))
    _bounds_elem!(elem, ox, oy, sdl_measure_text, mnx, mny, mxx, mxy)
    mxx[] == typemin(Int) ? nothing : (mnx[], mny[], mxx[], mxy[])
end

function _bounds_of_canvas(canvas::GraphicsCanvas, ox::Int, oy::Int)
    mnx = Ref(typemax(Int)); mny = Ref(typemax(Int))
    mxx = Ref(typemin(Int)); mxy = Ref(typemin(Int))
    _accumulate_bounds!(canvas, ox, oy, sdl_measure_text, mnx, mny, mxx, mxy)
    mxx[] == typemin(Int) ? nothing : (mnx[], mny[], mxx[], mxy[])
end

# Union a dirty unit's previous (cached) and new bounds into `acc`, then refresh
# the cache so this frame's bounds become next frame's "previous". `new` may be
# `nothing` when the unit now renders nothing (content removed) — its cached old
# extent is still cleared, then the stale entry is dropped.
function _union_unit!(res::SdlWindowResources, acc::_DirtyAcc, key::UInt,
                      new::Union{Nothing,NTuple{4,Int}})
    old = get(res.dirty_bounds, key, nothing)
    old === nothing || _acc_extend!(acc, old)
    if new === nothing
        delete!(res.dirty_bounds, key)
    else
        _acc_extend!(acc, new)
        res.dirty_bounds[key] = new
    end
end

# Recurse into a canvas at content origin `(ox, oy)`. `(vw, vh)` is the viewport
# extent in this canvas's coordinate space, threaded exactly as in
# `_render_canvas!` so the dirty walk reads precisely the cells the renderer
# reads — in particular it honours the same layout early-stop, so off-screen
# `ListNode` tail cells (which the renderer leaves lazily invalid) are not
# misread as "dirty" every frame. Accumulates into `acc`.
function _collect_canvas_dirty!(res::SdlWindowResources, canvas::GraphicsCanvas,
                                ox::Int, oy::Int, vw::Int, vh::Int, acc::_DirtyAcc)
    elements_cell = getfield(canvas, :elements)
    # A canvas's painted content depends only on its elements and its own x/y
    # offset — not on w/h/layout (those are metadata for parents/scroll that the
    # renderer never reads, so their cells may stay perpetually invalid and must
    # not be mistaken for "dirty").
    unit = !is_cell_up_to_date(elements_cell) ||
           !is_cell_up_to_date(getfield(canvas, :x)) || !is_cell_up_to_date(getfield(canvas, :y))
    ev = elements_cell[]                 # read after capturing validity above
    if !unit && ev isa CellVector && !is_cell_up_to_date(getfield(ev, :elements))
        unit = true                      # the regenerated element vector changed
    end
    if unit
        _union_unit!(res, acc, objectid(canvas), _bounds_of_canvas(canvas, ox, oy))
        return
    end
    layout = canvas.layout
    early = !canvas.overlapping_elements && layout != layout_none
    if ev isa ListNode
        _collect_listnode_dirty!(res, ev, ox, oy, vw, vh, layout, early, acc)
    else
        for elem in ev
            elem isa GraphicsFence && continue
            if early
                if layout == layout_vertical
                    ey = _render_elem_y(elem)
                    ey !== nothing && (ey + oy) > vh && break
                elseif layout == layout_horizontal
                    ex = _render_elem_x(elem)
                    ex !== nothing && (ex + ox) > vw && break
                end
            end
            _collect_dirty_elem!(res, elem, ox, oy, vw, vh, acc)
        end
    end
    nothing
end

function _collect_dirty_elem!(res::SdlWindowResources, elem, ox::Int, oy::Int,
                              vw::Int, vh::Int, acc::_DirtyAcc)
    elem isa GraphicsFence && return
    if elem isa GraphicsCanvas
        cx, cy = Int(elem.x), Int(elem.y)
        _collect_canvas_dirty!(res, elem, ox + cx, oy + cy, vw - cx, vh - cy, acc)
    elseif elem isa GraphicsViewport
        _collect_viewport_dirty!(res, elem, ox, oy, acc)
    elseif _node_dirty(elem)
        # Leaf with an in-place-mutated (stale) field cell.
        _union_unit!(res, acc, objectid(elem), _bounds_of_elem(elem, ox, oy))
    end
    nothing
end

# A viewport clips its content, so its dirty contribution is clamped to its own
# box. If the viewport itself moved/resized, the whole box is dirty.
function _collect_viewport_dirty!(res::SdlWindowResources, vp::GraphicsViewport,
                                  ox::Int, oy::Int, acc::_DirtyAcc)
    vx, vy = ox + Int(vp.x), oy + Int(vp.y)
    vw, vh = Int(vp.w), Int(vp.h)
    if _node_dirty(vp)
        _acc_extend!(acc, (vx, vy, vx + vw, vy + vh))
        return
    end
    # Under a non-identity transform the content's dirty region is in unscaled
    # content space; rather than map every sub-rect through the transform, treat
    # any dirty content as dirtying the whole (clipped) viewport box. Correct,
    # and zoom/pan repaints the whole pane anyway.
    if (vp.transform::AffineTransform) !== affine_identity
        tmp = _DirtyAcc()
        content0 = vp.content::GraphicsCanvas
        _collect_canvas_dirty!(res, content0, vx, vy, vx + vw, vy + vh, tmp)
        _acc_empty(tmp) || _acc_extend!(acc, (vx, vy, vx + vw, vy + vh))
        return
    end
    content = vp.content::GraphicsCanvas
    cx, cy = Int(content.x), Int(content.y)
    tmp = _DirtyAcc()
    # Mirror `_render_viewport!`: content extent is the absolute viewport box.
    _collect_canvas_dirty!(res, content, vx + cx, vy + cy, vx + vw, vy + vh, tmp)
    _acc_empty(tmp) && return
    # Intersect the content's dirty region with the viewport box.
    ix0 = max(tmp.minx, vx); iy0 = max(tmp.miny, vy)
    ix1 = min(tmp.maxx, vx + vw); iy1 = min(tmp.maxy, vy + vh)
    (ix1 > ix0 && iy1 > iy0) && _acc_extend!(acc, (ix0, iy0, ix1, iy1))
    nothing
end

# Walk a `ListNode`-backed element list the same way `_render_canvas!` does
# (prev links, then next links, with the layout early-stop), visiting only the
# nodes the renderer would draw. A change confined to one node's value is a
# per-node dirty unit (one edited line stays tight, with old∪new bounds so a
# shrinking line clears its tail). A spine change (line inserted/removed)
# reflows everything below it, so the dirty region is extended down to the
# viewport bottom — which also clears a removed last line's vacated pixels.
function _collect_listnode_dirty!(res::SdlWindowResources, head::ListNode,
                                  ox::Int, oy::Int, vw::Int, vh::Int,
                                  layout::LayoutDirection, early::Bool, acc::_DirtyAcc)
    visited = Tuple{ListNode,Any,Bool}[]   # (node, value, value_is_stale)
    spine_dirty = false

    # Prev links (negative offsets): process, then early-stop (as in render).
    pcell = getfield(head, :prev)
    is_cell_up_to_date(pcell) || (spine_dirty = true)
    node = pcell[]
    while node !== nothing
        vcell = getfield(node, :value)
        vstale = !is_cell_up_to_date(vcell)
        elem = vcell[]
        if !(elem isa GraphicsFence)
            push!(visited, (node, elem, vstale))
            if early
                if layout == layout_vertical
                    ey = _render_elem_y(elem); ey !== nothing && (ey + oy) < 0 && break
                elseif layout == layout_horizontal
                    ex = _render_elem_x(elem); ex !== nothing && (ex + ox) < 0 && break
                end
            end
        end
        pc = getfield(node, :prev)
        is_cell_up_to_date(pc) || (spine_dirty = true)
        node = pc[]
    end

    # Next links from head: early-stop, then process (as in render).
    node = head
    while node !== nothing
        vcell = getfield(node, :value)
        vstale = !is_cell_up_to_date(vcell)
        elem = vcell[]
        if !(elem isa GraphicsFence)
            if early
                if layout == layout_vertical
                    ey = _render_elem_y(elem); ey !== nothing && (ey + oy) > vh && break
                elseif layout == layout_horizontal
                    ex = _render_elem_x(elem); ex !== nothing && (ex + ox) > vw && break
                end
            end
            push!(visited, (node, elem, vstale))
        end
        nc = getfield(node, :next)
        is_cell_up_to_date(nc) || (spine_dirty = true)
        node = nc[]
    end

    if spine_dirty
        wb = _DirtyAcc()
        for (_, val, _) in visited
            b = _bounds_of_elem(val, ox, oy)
            b === nothing || _acc_extend!(wb, b)
        end
        if !_acc_empty(wb)
            # Reflow runs to the viewport bottom (vertical) / right (horizontal).
            bottom = layout == layout_horizontal ? wb.maxy : max(wb.maxy, vh)
            right  = layout == layout_horizontal ? max(wb.maxx, vw) : wb.maxx
            _acc_extend!(acc, (wb.minx, wb.miny, right, bottom))
        end
        return
    end

    for (n, val, vstale) in visited
        if vstale
            _union_unit!(res, acc, objectid(n), _bounds_of_elem(val, ox, oy))
        else
            _collect_dirty_elem!(res, val, ox, oy, vw, vh, acc)
        end
    end
    nothing
end

# Compute the dirty rectangle for `canvas` (the whole window content), clamped
# to the window and padded a couple of logical pixels so anti-aliased glyph
# edges straddling the clip boundary are not clipped. Returns `(x0,y0,x1,y1)`,
# or `nothing` when nothing is invalidated. Populating `res.dirty_bounds` is a
# side effect, so this is also called (its rect ignored) on the first full paint
# to seed each unit's previous bounds.
function _compute_dirty_rect(res::SdlWindowResources, canvas::GraphicsCanvas)
    acc = _DirtyAcc()
    _collect_canvas_dirty!(res, canvas, 0, 0, res.width, res.height, acc)
    _acc_empty(acc) && return nothing
    pad = 2
    x0 = clamp(acc.minx - pad, 0, res.width)
    y0 = clamp(acc.miny - pad, 0, res.height)
    x1 = clamp(acc.maxx + pad, 0, res.width)
    y1 = clamp(acc.maxy + pad, 0, res.height)
    (x1 <= x0 || y1 <= y0) ? nothing : (x0, y0, x1, y1)
end

# ── Swap-chain buffer age ──────────────────────────────────────────────────
#
# Copying only the damaged sub-rectangle to the window is correct only if we
# refresh everything that changed since the back-buffer we are drawing into was
# last presented — the last 2 frames for a double-buffered swap chain, 3 for
# triple-buffered, etc. `EGL_EXT_buffer_age` / `GLX_EXT_buffer_age` report that
# "age" for the current drawable. SDL's 2D renderer hides its GL context, but the
# *current* EGL surface / GLX drawable is queryable from whatever context SDL has
# made current during rendering (we query right after switching back to the
# window framebuffer). Returns the age (≥1), or 0 when the buffer is undefined or
# the extension is unavailable — the caller then does a full copy, so this is
# correct for any swap-chain depth and degrades safely.
const _EGL_AVAILABLE = Ref{Union{Nothing,Bool}}(nothing)
const _GLX_AVAILABLE = Ref{Union{Nothing,Bool}}(nothing)

function _egl_buffer_age()::Int
    _EGL_AVAILABLE[] === false && return -1
    try
        dpy = ccall((:eglGetCurrentDisplay, "libEGL.so.1"), Ptr{Cvoid}, ())
        _EGL_AVAILABLE[] = true
        dpy == C_NULL && return -1                                          # not the EGL path
        surf = ccall((:eglGetCurrentSurface, "libEGL.so.1"), Ptr{Cvoid}, (Cint,), Cint(0x3059))  # EGL_DRAW
        surf == C_NULL && return -1
        age = Ref{Cint}(0)
        ok = ccall((:eglQuerySurface, "libEGL.so.1"), Cint,
                   (Ptr{Cvoid}, Ptr{Cvoid}, Cint, Ptr{Cint}),
                   dpy, surf, Cint(0x313D), age)                            # EGL_BUFFER_AGE_EXT
        return ok != 0 ? Int(age[]) : -1
    catch
        _EGL_AVAILABLE[] = false
        return -1
    end
end

function _glx_buffer_age()::Int
    _GLX_AVAILABLE[] === false && return -1
    try
        dpy = ccall((:glXGetCurrentDisplay, "libGL.so.1"), Ptr{Cvoid}, ())
        _GLX_AVAILABLE[] = true
        dpy == C_NULL && return -1                                          # not the GLX path
        draw = ccall((:glXGetCurrentDrawable, "libGL.so.1"), Culong, ())
        draw == 0 && return -1
        age = Ref{Cuint}(0)
        ccall((:glXQueryDrawable, "libGL.so.1"), Cvoid,
              (Ptr{Cvoid}, Culong, Cint, Ptr{Cuint}),
              dpy, draw, Cint(0x20F4), age)                                 # GLX_BACK_BUFFER_AGE_EXT
        return Int(age[])
    catch
        _GLX_AVAILABLE[] = false
        return -1
    end
end

# Age of the current window back-buffer, or 0 when unknown (⇒ full copy).
function _back_buffer_age()::Int
    a = _egl_buffer_age(); a >= 0 && return a
    a = _glx_buffer_age(); a >= 0 && return a
    return 0
end

# ── Per-window paint ──────────────────────────────────────────────────────

# Repaint `canvas` into the window, restricting the work to the invalidated
# region when partial rendering is enabled. Everything is rendered into the
# retained `res.target` texture (which keeps its pixels across frames); only the
# dirty sub-rectangle of that texture is re-rendered, then the damaged region
# (this frame's dirty rect unioned with the last `buffer age` frames' — see
# `damage_history` / `_back_buffer_age`) is copied to the window and presented.
# Copying only the damage instead of the whole target keeps the scaled blit
# proportional to the edit.
function _render_window!(res::SdlWindowResources, canvas::GraphicsCanvas)
    bg = res.bg
    renderer = res.renderer
    scale = Float32(_DISPLAY_SCALE[])

    if !_ensure_ss_target!(res)
        # No usable retained target — fall back to the classic full repaint
        # straight to the window backbuffer.
        SDL_RenderSetScale(renderer, scale, scale)
        SDL_SetRenderDrawColor(renderer, bg[1], bg[2], bg[3], bg[4])
        SDL_RenderClear(renderer)
        _render_canvas!(renderer, canvas, 0, 0, res.width, res.height)
        SDL_RenderSetScale(renderer, 1.0f0, 1.0f0)
        SDL_RenderPresent(renderer)
        return
    end

    # Decide the region to repaint.
    if !_PARTIAL_RENDER[]
        dirty = (0, 0, res.width, res.height)
    else
        # Always walk: this seeds `res.dirty_bounds` with each unit's current
        # extent so the *next* edit can clear vacated pixels (old∪new). On the
        # first paint the whole window must be cleared (the target is undefined
        # and margins outside the content have no element to mark them dirty),
        # so the computed rect is widened to the full window — but the walk's
        # cache-seeding side effect is kept.
        computed = _compute_dirty_rect(res, canvas)
        if res.first_paint
            dirty = (0, 0, res.width, res.height)
        else
            computed === nothing && return   # nothing invalidated — skip paint/present
            dirty = computed
        end
    end
    res.first_paint = false

    rss = Float32(res.ss) * scale
    dx, dy = dirty[1], dirty[2]
    dw, dh = dirty[3] - dirty[1], dirty[4] - dirty[2]
    clip = Ref(SDL_Rect(Int32(dx), Int32(dy), Int32(dw), Int32(dh)))

    SDL_SetRenderTarget(renderer, res.target)
    SDL_RenderSetScale(renderer, rss, rss)
    SDL_RenderSetClipRect(renderer, clip)
    # Not SDL_RenderClear: it ignores the clip rect and would wipe the retained
    # pixels outside the dirty region. Repaint the dirty background by hand.
    SDL_SetRenderDrawColor(renderer, bg[1], bg[2], bg[3], bg[4])
    SDL_RenderFillRect(renderer, clip)
    _render_canvas!(renderer, canvas, 0, 0, res.width, res.height)
    SDL_RenderSetClipRect(renderer, C_NULL)
    SDL_RenderSetScale(renderer, 1.0f0, 1.0f0)
    SDL_SetRenderTarget(renderer, C_NULL)

    # Copy only the damaged region from the retained target to the window
    # back-buffer, rather than the whole (supersampled) target, so the scaled
    # blit tracks the edit instead of the window. The back-buffer we just rendered
    # into was last presented `age` frames ago (EGL/GLX buffer age, queried now
    # that the window framebuffer is current), so to bring it current we re-copy
    # every frame's damage since then — the union of the last `age` dirty rects.
    # Age 0 means undefined contents; an unsupported extension, age 0, or too
    # little history all fall back to a full copy. This is correct for any
    # swap-chain depth (no fixed double-buffer assumption).
    age = _back_buffer_age()
    if !_PARTIAL_RENDER[] || _DEBUG_DIRTY[] || age <= 0 || (age - 1) > length(res.damage_history)
        # Full copy. Under `debug_dirty` we always copy the whole target so the
        # previous frames' red outlines — drawn straight onto the window
        # back-buffer below, never retained in `res.target` nor recorded in
        # `damage_history` — are painted over instead of accumulating into a
        # trail. The current frame's dirty region is still shown by its outline.
        SDL_RenderCopy(renderer, res.target, C_NULL, C_NULL)
    else
        cx0, cy0, cx1, cy1 = dirty
        for i in 1:(age - 1)
            r = res.damage_history[i]
            cx0 = min(cx0, r[1]); cy0 = min(cy0, r[2]); cx1 = max(cx1, r[3]); cy1 = max(cy1, r[4])
        end
        src = Ref(SDL_Rect(round(Int32, cx0 * rss),   round(Int32, cy0 * rss),
                           round(Int32, (cx1 - cx0) * rss), round(Int32, (cy1 - cy0) * rss)))
        dst = Ref(SDL_Rect(round(Int32, cx0 * scale), round(Int32, cy0 * scale),
                           round(Int32, (cx1 - cx0) * scale), round(Int32, (cy1 - cy0) * scale)))
        SDL_RenderCopy(renderer, res.target, src, dst)
    end
    # Record this frame's content damage (most-recent first) for future unions.
    pushfirst!(res.damage_history, dirty)
    length(res.damage_history) > _DAMAGE_HISTORY_CAP && resize!(res.damage_history, _DAMAGE_HISTORY_CAP)

    if _DEBUG_DIRTY[]
        # Outline this frame's repainted region on the window. The box is drawn
        # straight onto the back-buffer (not into `res.target`), so it would ghost
        # across frames; the forced full copy above repaints over the previous
        # frame's outline, leaving only the current one visible.
        SDL_RenderSetScale(renderer, scale, scale)
        SDL_SetRenderDrawColor(renderer, 0xff, 0x00, 0x00, 0xff)
        SDL_RenderDrawRect(renderer, clip)
        SDL_RenderSetScale(renderer, 1.0f0, 1.0f0)
    end
    SDL_RenderPresent(renderer)
end

# ════════════════════════════════════════════════════════════════════════
# Font measurement
# ════════════════════════════════════════════════════════════════════════

"""
    measure_text(backend::SdlBackend, text::AbstractString, font::StyleFont) -> (Int, Int)

Return the `(width, height)` of `text` rendered in `font`, in **logical**
pixels — the space all layout lives in. The glyphs are rasterized at device
size (for crispness) and the device measurement is divided back by
[`_DISPLAY_SCALE`](@ref). Font handles are cached in the module-level
[`_font_cache`](@ref).
"""
function BackendModule.measure_text(::SdlBackend, text::AbstractString, font::StyleFont)
    isempty(text) && return (0, font_logical_size(font))
    primary = _get_font(font)
    emoji = _get_emoji_font(font_device_size(font))
    runs = _font_runs(text, primary, emoji)
    # Fast path: a single run — all-text (the common case, font == primary) or
    # all-emoji. Measure with that run's own font, not `primary`, otherwise a
    # pure-emoji span would be sized from the text font's `.notdef` box.
    if length(runs) == 1
        f, s = runs[1]
        w_ref, h_ref = Ref{Cint}(0), Ref{Cint}(0)
        TTF_SizeUTF8(f, s, w_ref, h_ref)
        return (_to_logical(Int(w_ref[])), _to_logical(Int(h_ref[])))
    end
    # Mixed-font span: sum per-run widths and baseline-align heights, matching the
    # composite produced by `_render_runs_blended`.
    total_w = 0; max_ascent = 0; max_below = 0
    for (f, s) in runs
        isempty(s) && continue
        w_ref, h_ref = Ref{Cint}(0), Ref{Cint}(0)
        TTF_SizeUTF8(f, s, w_ref, h_ref)
        asc = Int(TTF_FontAscent(f))
        total_w += Int(w_ref[])
        max_ascent = max(max_ascent, asc)
        max_below = max(max_below, Int(h_ref[]) - asc)
    end
    return (_to_logical(total_w), _to_logical(max_ascent + max_below))
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

# Backend-interface methods: let callers reach SDL rendering/decoding/display
# through the generic BackendModule seams without naming SdlBackendModule, so the
# SDL backend can move into an optional extension.
BackendModule.render_canvas(canvas::GraphicsCanvas) = sdl_render_canvas(canvas)

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
# Box-downsample a 32-bit ARGB software `big` surface (S× oversized) into a fresh
# `width × height` surface by averaging each S×S block — true anti-aliasing,
# independent of SDL's software scaler. Returns the new surface (caller frees).
function _downsample_surface(big::Ptr{SDL_Surface}, width::Int, height::Int, S::Int)
    bs = unsafe_load(big)
    bigpix = Ptr{UInt32}(bs.pixels)
    bigstride = Int(bs.pitch) ÷ 4
    small = SDL_CreateRGBSurface(UInt32(0), Int32(width), Int32(height), Int32(32),
                                 UInt32(0x00FF0000), UInt32(0x0000FF00),
                                 UInt32(0x000000FF), UInt32(0xFF000000))
    @assert small != C_NULL "SDL downsample surface creation failed"
    ss = unsafe_load(small)
    smallpix = Ptr{UInt32}(ss.pixels)
    smallstride = Int(ss.pitch) ÷ 4
    n = S * S
    for yy in 0:(height - 1)
        for xx in 0:(width - 1)
            ar = ag = ab = aa = 0
            for sy in 0:(S - 1), sx in 0:(S - 1)
                px = unsafe_load(bigpix, (yy * S + sy) * bigstride + (xx * S + sx) + 1)
                aa += Int((px >> 24) & 0xff); ar += Int((px >> 16) & 0xff)
                ag += Int((px >> 8) & 0xff);  ab += Int(px & 0xff)
            end
            outp = (UInt32(aa ÷ n) << 24) | (UInt32(ar ÷ n) << 16) |
                   (UInt32(ag ÷ n) << 8)  |  UInt32(ab ÷ n)
            unsafe_store!(smallpix, outp, yy * smallstride + xx + 1)
        end
    end
    small
end

# ── Reusable offscreen renderer ──────────────────────────────────────────
#
# Opening an SDL surface + software renderer is expensive (SDL_Init, TTF_Init,
# allocating an S²-oversized buffer). `write_image` does it once per call, but
# `record_video` renders hundreds-to-thousands of frames at a fixed size, so the
# setup/teardown is factored out here and reused across every frame.

# Open an offscreen, `supersample`-oversized software renderer for a logical
# `width × height` canvas drawn at export `scale`. Returns a handle holding the
# big surface, its renderer, and the sizing it was built with. `width`/`height`
# are the canvas's logical size; the saved image is that times `scale` (device
# pixels), so output stays crisp on HiDPI displays independent of the generating
# machine. The caller must eventually pass the handle to
# `_close_offscreen_renderer`.
function _open_offscreen_renderer(width::Integer, height::Integer;
                                  supersample::Integer = 2, scale::Real = 1)
    SDL_Init(SDL_INIT_VIDEO)
    TTF_Init()
    S  = max(1, Int(supersample))
    sc = Float64(scale)
    out_w = max(1, round(Int, width  * sc))
    out_h = max(1, round(Int, height * sc))
    surface = SDL_CreateRGBSurface(UInt32(0), Int32(out_w * S), Int32(out_h * S), Int32(32),
                                   UInt32(0x00FF0000), UInt32(0x0000FF00),
                                   UInt32(0x000000FF), UInt32(0xFF000000))
    @assert surface != C_NULL "SDL surface creation failed: $(unsafe_string(SDL_GetError()))"
    renderer = SDL_CreateSoftwareRenderer(surface)
    @assert renderer != C_NULL "SDL software renderer creation failed: $(unsafe_string(SDL_GetError()))"
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
    SDL_RenderSetScale(renderer, Float32(sc * S), Float32(sc * S))
    (surface = surface, renderer = renderer, S = S, sc = sc, out_w = out_w, out_h = out_h)
end

# Clear `off` to `background` and render `canvas` (logical size `width × height`)
# into it. `_DISPLAY_SCALE` is set so glyphs rasterize at device size, matching
# the renderer's scale.
function _render_canvas_offscreen!(off, canvas::GraphicsCanvas, width::Integer,
                                   height::Integer, background::NTuple{4,UInt8})
    old_scale = _DISPLAY_SCALE[]
    _DISPLAY_SCALE[] = off.sc
    try
        r, g, b, a = background
        SDL_SetRenderDrawColor(off.renderer, r, g, b, a)
        SDL_RenderClear(off.renderer)
        _render_canvas!(off.renderer, canvas, 0, 0, Int(width), Int(height))
    finally
        _DISPLAY_SCALE[] = old_scale
    end
    nothing
end

# The surface to save: the box-downsampled output when supersampling (a fresh
# surface the caller must `SDL_FreeSurface`), or the big surface itself when not
# (do not free it separately — `_close_offscreen_renderer` owns it).
function _offscreen_output_surface(off)
    off.S > 1 ? _downsample_surface(off.surface, off.out_w, off.out_h, off.S) : off.surface
end

# Save a surface to a BMP file.
function _save_surface_bmp(surface::Ptr{SDL_Surface}, filename::AbstractString)
    rw = SDL_RWFromFile(filename, "wb")
    @assert rw != C_NULL "Failed to open output file: $filename"
    SDL_SaveBMP_RW(surface, rw, Int32(1))   # freedst=1 — SDL closes the RW handle
    nothing
end

# Tear down a renderer+surface pair opened by `_open_offscreen_renderer`.
function _close_offscreen_renderer(off)
    _evict_renderer_textures!(off.renderer)
    SDL_DestroyRenderer(off.renderer)
    SDL_FreeSurface(off.surface)
    nothing
end

function BackendModule.write_image(canvas::GraphicsCanvas, filename::AbstractString;
                     width::Integer = 800,
                     height::Integer = 600,
                     background::NTuple{4,UInt8} = (0xfd, 0xf6, 0xe3, 0xff),
                     supersample::Integer = 2,
                     scale::Real = 1)
    off = _open_offscreen_renderer(width, height; supersample=supersample, scale=scale)
    try
        _render_canvas_offscreen!(off, canvas, width, height, background)
        out_surface = _offscreen_output_surface(off)
        try
            ext = lowercase(splitext(filename)[2])
            if ext == ".bmp"
                _save_surface_bmp(out_surface, filename)
            elseif ext == ".png"
                if IMG_SavePNG(out_surface, filename) != 0
                    error("write_image: IMG_SavePNG failed for $filename: $(unsafe_string(SDL_GetError()))")
                end
            else
                error("write_image: unsupported format \"$ext\" (only .bmp and .png are supported)")
            end
        finally
            out_surface !== off.surface && SDL_FreeSurface(out_surface)
        end
    finally
        _close_offscreen_renderer(off)
    end
    ImageFile(filename)
end

# ── Content bounds ──────────────────────────────────────────────────────
#
# `_canvas_content_bounds` / `_accumulate_bounds!` / `_bounds_elem!` now live in
# `GraphicsModule` (pure geometry over a `measure` callback, no SDL), imported
# above and shared with the PDF backend. `write_image` passes `sdl_measure_text`.

"""
    write_image(document, projection, filename::AbstractString;
                width=nothing, height=nothing,
                max_width::Integer = 1200, max_height::Integer = 800,
                background::NTuple{4,UInt8} = (0xfd, 0xf6, 0xe3, 0xff)) -> ImageFile

Run `print_document(projection, document)` to obtain a `GraphicsCanvas`,
render it offscreen and save to `filename` (BMP or PNG). Returns an `ImageFile`.

Image sizing, per axis:

- If `width` (resp. `height`) is given, the image is exactly that size and the
  content is laid out within it (the classic fixed-size behavior).
- If it is omitted, the content is first laid out *unbounded* and the image is
  sized to its natural extent. Should that extent exceed `max_width`
  (resp. `max_height`), the axis is capped at the max and the content is
  re-printed so the layout can reflow (e.g. word wrapping), then the image is
  sized to the now-bounded content.

So an omitted axis yields an image that hugs the content, never larger than the
corresponding `max_*`.

```julia
proj = ChainingProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure=sdl_measure_text),
)
write_image(doc, proj, "snapshot.png")                          # fits content ≤ 1200×800
write_image(doc, proj, "snapshot.png"; width=1200, height=800)  # fixed 1200×800
```

Throws if the projection output is not a `GraphicsCanvas`.
"""
function BackendModule.write_image(document, projection, filename::AbstractString;
                     width::Union{Nothing,Integer} = nothing,
                     height::Union{Nothing,Integer} = nothing,
                     max_width::Integer = 1200,
                     max_height::Integer = 800,
                     background::NTuple{4,UInt8} = (0xfd, 0xf6, 0xe3, 0xff),
                     supersample::Integer = 2,
                     scale::Real = 1)
    # Initialize before printing: the projection measures text (opening fonts),
    # which requires SDL_ttf to be up.
    SDL_Init(SDL_INIT_VIDEO)
    TTF_Init()

    print_canvas = (aw, ah) -> begin
        ctx = PrinterContext(EmptyReference(), aw, ah, Dict{Symbol,Any}())
        iomap = print_document(projection, nothing, document, ctx)
        canvas = iomap.output
        canvas isa GraphicsCanvas ||
            error("write_image: projection output is $(typeof(canvas)), expected GraphicsCanvas")
        canvas
    end

    # Pass 1: constrain only the explicitly-given axes; leave omitted axes
    # unbounded so the content lays out at its natural size.
    aw = width  === nothing ? nothing : Cell(Int(width))
    ah = height === nothing ? nothing : Cell(Int(height))
    canvas = print_canvas(aw, ah)
    # `_canvas_content_bounds` returns (minx, miny, maxx, maxy). The natural size
    # must span the full extent — including any content at negative coordinates —
    # so subtract a negative min rather than dropping it.
    minx, miny, maxx, maxy = _canvas_content_bounds(canvas, sdl_measure_text)
    nw = maxx - min(minx, 0)
    nh = maxy - min(miny, 0)

    # Pass 2: if an omitted axis overran its max, cap it at max and re-print so
    # the layout can reflow (e.g. word wrapping), then re-measure.
    cap_w = width  === nothing && nw > max_width
    cap_h = height === nothing && nh > max_height
    if cap_w || cap_h
        aw2 = cap_w ? Cell(Int(max_width))  : aw
        ah2 = cap_h ? Cell(Int(max_height)) : ah
        canvas = print_canvas(aw2, ah2)
        minx, miny, maxx, maxy = _canvas_content_bounds(canvas, sdl_measure_text)
        nw = maxx - min(minx, 0)
        nh = maxy - min(miny, 0)
    end

    out_w = width  === nothing ? clamp(nw, 1, Int(max_width))  : Int(width)
    out_h = height === nothing ? clamp(nh, 1, Int(max_height)) : Int(height)

    # The renderer draws from the origin, so content extending into negative
    # coordinates would be clipped. Shift it into view by wrapping the canvas in
    # an outer canvas whose single child carries the (positive) offset.
    ox = -min(minx, 0)
    oy = -min(miny, 0)
    if ox > 0 || oy > 0
        shifted = GraphicsCanvas(ox, oy, canvas.elements, canvas.layout, canvas.overlapping_elements)
        canvas = GraphicsCanvas(CellVector(Cell[Cell(shifted)]), layout_none)
    end

    write_image(canvas, filename; width=out_w, height=out_h,
                background=background, supersample=supersample, scale=scale)
end

"""
    GraphicsCanvasToImageFile(filename; width=800, height=600,
                               background=(0xfd,0xf6,0xe3,0xff))

Printer-only projection. On `print_document` it renders the input
`GraphicsCanvas` offscreen and saves to `filename` (BMP). The `output` field
of the returned `SimpleIoMap` is an `ImageFile` document. Has no reader.

```julia
proj = ChainingProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure=sdl_measure_text),
    GraphicsCanvasToImageFile("output.bmp"; width=1200, height=800),
)
iomap = print_document(proj, doc)   # writes output.bmp
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

function print_document(p::GraphicsCanvasToImageFile,
                           recursion, canvas::GraphicsCanvas, ctx)
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
# Offscreen frame emission — the rendering primitive for headless video.
# (`record_video` itself lives in the opt-in `ProjecturedVideo` package, which
#  pulls FFMPEG; this package exports the offscreen primitives it builds on.)
# ════════════════════════════════════════════════════════════════════════


# Render `canvas` once and write `count` identical BMP frames (the post-event
# state held on screen for `count` frames of video time), advancing `frame`.
function _emit_frames!(off, canvas::GraphicsCanvas, width::Integer, height::Integer,
                       background::NTuple{4,UInt8}, tmpdir::AbstractString,
                       frame::Ref{Int}, count::Integer)
    count <= 0 && return nothing
    _render_canvas_offscreen!(off, canvas, width, height, background)
    out_surface = _offscreen_output_surface(off)
    try
        for _ in 1:count
            frame[] += 1
            # PNG (lossless, compressed) rather than raw BMP: UI frames are mostly
            # flat colour and compress ~10-50x, so the frame pile stays small
            # instead of filling the disk quota on a long high-resolution recording.
            fn = joinpath(tmpdir, "frame_$(lpad(frame[], 6, '0')).png")
            IMG_SavePNG(out_surface, fn) == 0 ||
                error("_emit_frames!: IMG_SavePNG failed for $fn: $(unsafe_string(SDL_GetError()))")
        end
    finally
        out_surface !== off.surface && SDL_FreeSurface(out_surface)
    end
    nothing
end


# ════════════════════════════════════════════════════════════════════════
# Application lifecycle
# ════════════════════════════════════════════════════════════════════════

function BackendModule.initialize_backend!(backend::SdlBackend)
    @assert SDL_Init(SDL_INIT_VIDEO) == 0 "SDL init failed: $(unsafe_string(SDL_GetError()))"
    @assert TTF_Init() == 0 "TTF init failed: $(unsafe_string(SDL_GetError()))"
    SDL_StartTextInput()   # enable SDL_TEXTINPUT events (explicit for portability)
    _detect_display_scale!()
    _PARTIAL_RENDER[] = backend.partial_render
    _DEBUG_DIRTY[]    = backend.debug_dirty
end

function BackendModule.quit_backend!(::SdlBackend)
    SDL_StopTextInput()
    # Free cached textures while their renderers are still alive (before SDL_Quit).
    _clear_text_texture_cache!()
    for font in values(_font_cache)
        # `_get_emoji_font` caches C_NULL when the emoji font is absent; skip those
        # (TTF_CloseFont(NULL) dereferences a null pointer).
        font != C_NULL && TTF_CloseFont(font)
    end
    empty!(_font_cache)
    TTF_Quit()
    SDL_Quit()
end

# ════════════════════════════════════════════════════════════════════════
# Device I/O
# ════════════════════════════════════════════════════════════════════════

"""
    read_from_devices(backend::SdlBackend, devices) -> WindowInput or nothing

Poll the SDL event queue once and return an `WindowInput` wrapping a
backend-agnostic inner event:
- `SDL_QUIT`                           → `WindowInput(:none, WindowQuit())`
- `SDL_WINDOWEVENT_CLOSE` for a window → `WindowInput(<id>, WindowClose())`
- `SDL_WINDOWEVENT_RESIZED`            → `WindowInput(<id>, WindowResize(w, h))`
- `SDL_KEYDOWN`                        → `WindowInput(<id>, KeyDown)` (Escape included)
- `SDL_KEYUP`                          → `WindowInput(<id>, KeyUp)`
- `SDL_TEXTINPUT`                      → `WindowInput(<id>, KeyPress)`
- `SDL_MOUSEBUTTONDOWN`                → `WindowInput(<id>, MouseDown)`
- `SDL_MOUSEBUTTONUP`                  → `WindowInput(<id>, MouseUp)`
- `SDL_MOUSEMOTION` (btn held)         → `WindowInput(<id>, MouseMove)`
- `SDL_MOUSEWHEEL`                     → `WindowInput(<id>, MouseScroll)`

`<id>` is the `WindowDocument.id` of the originating window (looked up
in `backend.window_ids`), or `:none` if the SDL event carries no window
id or refers to a window the backend does not track.

The backend emits only raw events; the `MousePress` click is synthesised from
the `MouseDown`/`MouseUp` pair by the editor's `GestureRecognizer`, not here.
"""
function BackendModule.read_from_devices(backend::SdlBackend, devices)
    event_ref = Ref{SDL_Event}()
    while Bool(SDL_PollEvent(event_ref))
        evt = event_ref[]
        t = evt.type

        if t == SDL_QUIT
            return WindowInput(:none, WindowQuit())

        elseif t == 0x00000200  # SDL_WINDOWEVENT
            # event byte 1 = SDL_WindowEventID
            sub = evt.window.event
            wid = _lookup_window_id(backend, evt.window.windowID)
            if sub == UInt8(14)  # SDL_WINDOWEVENT_CLOSE
                return WindowInput(wid, WindowClose())
            elseif sub == UInt8(12)  # SDL_WINDOWEVENT_FOCUS_LOST
                return WindowInput(wid, WindowDefocus())
            elseif sub == UInt8(5)  # SDL_WINDOWEVENT_RESIZED (external/user only)
                # SDL reports device pixels; the document works in logical pixels.
                nw = _to_logical(Int(evt.window.data1))
                nh = _to_logical(Int(evt.window.data2))
                # Mark the resource as already at this size so the reconciler's
                # _update_window_geometry! doesn't issue a redundant
                # SDL_SetWindowSize back at the OS (which would fight the drag).
                res = get(backend.windows, wid, nothing)
                if res !== nothing
                    res.width = nw
                    res.height = nh
                end
                return WindowInput(wid, WindowResize(nw, nh))
            end
            # Other window events are not currently surfaced; keep polling.
            continue

        elseif t == SDL_KEYDOWN
            keysym = evt.key.keysym.sym
            wid = _lookup_window_id(backend, evt.key.windowID)
            # Escape is an ordinary key here. A backend reports what happened and
            # decides no meaning, so it must not turn one key into a quit before any
            # reader has seen it — that is what made Esc unreachable for the dialog,
            # the insertion, the command palette and every other reader that binds
            # it. The editor loop quits on an Escape that nothing handled.
            is_repeat = evt.key.repeat != 0
            return WindowInput(wid, sdl_to_keydown(keysym, evt.key.keysym.mod, is_repeat))

        elseif t == 0x00000301  # SDL_KEYUP
            wid = _lookup_window_id(backend, evt.key.windowID)
            return WindowInput(wid, sdl_to_keyup(evt.key.keysym.sym, evt.key.keysym.mod))

        elseif t == 0x00000303  # SDL_TEXTINPUT
            kp = sdl_to_keypress(evt)
            kp === nothing && continue
            wid = _lookup_window_id(backend, evt.text.windowID)
            return WindowInput(wid, kp)

        elseif t == 0x00000401  # SDL_MOUSEBUTTONDOWN
            button = _sdl_button_sym(evt.button.button)
            mods = _current_modifiers()
            x, y = _to_logical(Int(evt.button.x)), _to_logical(Int(evt.button.y))
            wid = _lookup_window_id(backend, evt.button.windowID)
            return WindowInput(wid, MouseDown(button, x, y, mods))

        elseif t == 0x00000402  # SDL_MOUSEBUTTONUP
            button = _sdl_button_sym(evt.button.button)
            mods = _current_modifiers()
            x, y = _to_logical(Int(evt.button.x)), _to_logical(Int(evt.button.y))
            wid = _lookup_window_id(backend, evt.button.windowID)
            return WindowInput(wid, MouseUp(button, x, y, mods))

        elseif t == 0x00000400  # SDL_MOUSEMOTION
            mx_ref, my_ref = Ref{Cint}(0), Ref{Cint}(0)
            bstate = UInt32(SDL_GetMouseState(mx_ref, my_ref))
            buttons = _held_button(bstate)
            # Idle (no-button) motion drives hover features but is rate-limited
            # so a hover probe does not run on every pixel; drag motion (a
            # button held) is forwarded unthrottled.
            if buttons == :none
                now = time()
                (now - _LAST_HOVER_MOTION[]) < _HOVER_MOTION_INTERVAL && continue
                _LAST_HOVER_MOTION[] = now
            end
            mods = _current_modifiers()
            wid = _lookup_window_id(backend, evt.motion.windowID)
            return WindowInput(wid,
                MouseMove(_to_logical(Int(evt.motion.x)), _to_logical(Int(evt.motion.y)),
                          buttons, mods))

        elseif t == 0x00000403  # SDL_MOUSEWHEEL
            mx_ref, my_ref = Ref{Cint}(0), Ref{Cint}(0)
            SDL_GetMouseState(mx_ref, my_ref)
            mods = _current_modifiers()
            wid = _lookup_window_id(backend, evt.wheel.windowID)
            dx, dy = Int(evt.wheel.x), Int(evt.wheel.y)
            if mods.shift && dx == 0
                dx, dy = dy, 0
            end
            return WindowInput(wid,
                MouseScroll(dx, dy, _to_logical(Int(mx_ref[])), _to_logical(Int(my_ref[])), mods))
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
least one `Display` entry — `Display` itself carries no per-window
state and exists only to indicate that the editor wants to render
onto a display.
"""
function BackendModule.write_to_devices(backend::SdlBackend, devices::Vector{Device}, screen::ScreenDocument)
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
        SDL_SetWindowSize(res.win, Int32(max(_to_device(w.width), 1)),
                                   Int32(max(_to_device(w.height), 1)))
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
# Readability zoom (Ctrl+=/-/0 uniform, Ctrl+Alt+=/-/0 font-only)
# ════════════════════════════════════════════════════════════════════════
#
# The gesture is recognised editor-globally in the kernel's `read!`; here the SDL
# backend supplies the concrete behaviour. `AdjustZoomOperation` rescales the
# display factor (everything magnifies) and reflows the logical viewport — no
# re-projection. `AdjustFontZoomOperation` writes the `_FONT_ZOOM` cell, which
# relayouts text-derived geometry that is held in cells (TextToGraphics), but the
# widget layer measures content *eagerly* during `print_document` and bakes
# constant sizes (WidgetToGraphics' `_make_canvas`), so those boxes only re-fit
# the larger text when the tree is re-projected. Dropping `editor.iomap` forces
# `print!` to re-run `print_document` with the new zoom; this is safe because
# window resources reconcile by `WindowDocument.id`, transient widget state
# (scroll/hover/selection) lives on the document, and the SDL caches are
# content-keyed and bounded (so nothing leaks). Both ops force a full repaint
# because a zoom change moves every pixel, defeating the dirty-rect path.

# Mark every open window so its next paint repaints in full.
function _force_full_repaint!(editor)
    be = editor.backend
    be isa SdlBackend || return
    for res in values(be.windows)
        res.first_paint = true
    end
    nothing
end

# Keep each window's *device* size fixed across a uniform-zoom change: scale its
# logical `width`/`height` by `old/new` so `_to_device(new) == old_device`. The
# OS window therefore does not resize, while the content relayouts to the new
# logical viewport — those cells are the printer's `available_width/height`, so
# the write reflows reactively (no re-projection), exactly like a user resize.
function _reflow_for_scale!(editor, ratio::Float64)
    (ratio == 1.0 || !isfinite(ratio)) && return
    out = editor.iomap === nothing ? nothing : editor.iomap.output
    out isa ScreenDocument || return
    for w in out.windows
        w isa WindowDocument || continue
        w.width  = max(1, round(Int, Int(w.width)  * ratio))
        w.height = max(1, round(Int, Int(w.height) * ratio))
    end
    nothing
end

function evaluate_operation(editor, op::AdjustZoomOperation)
    old = _DISPLAY_SCALE[]
    adjust_user_zoom!(op.delta)
    new = _DISPLAY_SCALE[]
    _reflow_for_scale!(editor, old / new)
    _force_full_repaint!(editor)
    nothing
end

function evaluate_operation(editor, op::AdjustFontZoomOperation)
    adjust_font_zoom!(op.delta)   # writes the _FONT_ZOOM cell → text-layout cells invalidate
    editor.iomap = nothing        # re-project so eagerly-measured widget boxes re-fit the new text size
    _force_full_repaint!(editor)
    nothing
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

# Image decode via the generic seam.
BackendModule.decode_image(filename::AbstractString) = sdl_decode_image(filename)

# Display size via the generic seam (delegates to the SDL-specific query).
BackendModule.get_display_size(::SdlBackend; display::Integer=0) =
    sdl_display_size(; display=display)

# Populate the Display devices with the real display geometry and HiDPI scale
# discovered at start-up (called after `initialize_backend!`, so the scale is
# already detected). Mouse/Keyboard are left at their defaults — SDL2 cannot
# reliably report button count or keyboard layout.
function BackendModule.configure_devices!(::SdlBackend, devices)
    width, height = sdl_display_size()
    scale = _DISPLAY_SCALE[]
    for device in devices
        device isa Display || continue
        device.width  = width
        device.height = height
        device.scale  = scale
    end
    return nothing
end

end # module Sdl
