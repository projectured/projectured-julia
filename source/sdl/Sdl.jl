# A backend's public surface is the generic it extends, not the helper behind
# it: `BackendModule.render_canvas`, `decode_image` and `get_display_size` are
# how a caller reaches this backend. The helpers stay module-internal.
#
# `measure_sdl_text` is the exception and is exported, because a caller hands it
# on by value — `TextToGraphics(measure = measure_sdl_text)` — and a generic can
# not be passed that way. It pairs with `measure_truetype_text`.
export SdlBackend, measure_sdl_text,
       write_image, GraphicsCanvasToImageFile,
       _open_offscreen_renderer, _close_offscreen_renderer

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
    get_sdl_display_size(; display::Integer=0) -> (width, height)

Return the usable size of the given display (default 0) in **logical** pixels —
the coordinate space window sizes are authored in. "Usable" means with
OS-reserved areas like the taskbar / menu bar subtracted; the right thing for
picking a default window size. The monitor's device-pixel size is divided by
the scale that the probe of the display finds, so that a window sized to it fills
exactly one monitor once the backend scales it back to device pixels. Falls back
to `(1280, 720)`
if SDL cannot answer (no display, headless run, etc.). The video subsystem and
the display scale are initialized lazily; safe to call before `initialize_backend!`.

On X11 SDL sometimes folds a multi-monitor screen into a single "display"
whose bounds span every monitor (e.g. 7290×4032 across two), which would
size the default window to the whole desktop. When SDL reports one display
but xrandr sees several, the primary monitor's size from xrandr is used
instead so the default fills one monitor, not the span.
"""
function get_sdl_display_size(; display::Integer=0)
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
        mon === nothing || return (_to_logical(mon[1], _PROBED_DISPLAY_SCALE[]),
                                   _to_logical(mon[2], _PROBED_DISPLAY_SCALE[]))
    end

    rect = Ref(SDL_Rect(Int32(0), Int32(0), Int32(0), Int32(0)))
    rc = SDL_GetDisplayUsableBounds(Int32(display), rect)
    if rc != 0 || rect[].w <= 0 || rect[].h <= 0
        return (1280, 720)
    end
    (_to_logical(Int(rect[].w), _PROBED_DISPLAY_SCALE[]),
     _to_logical(Int(rect[].h), _PROBED_DISPLAY_SCALE[]))
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
    ratio::Float64       # last applied device pixel ratio of the backend's Display
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

`pending_input` and `pending_motion` are the one-event buffers
`read_from_devices` needs to collapse a run of pointer motion into its newest
sample, and `last_hover_motion` is the time of the rate limit of idle motion.
They live on the backend rather than at module level, so two backends in one
process never hand each other an event or a delay. `partial_render` and
`debug_dirty` are read for each window of this backend alone.

`display` is the `Display` that the backend draws on. Its device pixel ratio
sizes the windows, rasterizes the text and converts the input coordinates. A new
backend has a `Display()` of its own, and `initialize_backend!` gives it the
scale that the probe finds. `configure_devices!` replaces it with the `Display`
of the editor, so the zoom of that `Display` is the zoom of the windows.
"""
mutable struct SdlBackend <: Backend
    # Multi-window reconciliation state.
    windows::Dict{Symbol, SdlWindowResources}
    window_ids::Dict{UInt32, Symbol}
    # Render controls (diagnostics / benchmarking), which `_render_window!` reads
    # for each window of this backend:
    #   partial_render — incremental dirty-rectangle repaint (false = full frame)
    #   debug_dirty    — outline the repainted region in red
    partial_render::Bool
    debug_dirty::Bool
    # Input coalescing state (see `read_from_devices`):
    #   pending_input  — the event that arrived behind a held motion, owed next call
    #   pending_motion — the newest motion sample not yet delivered
    #   last_hover_motion — when the last idle motion was delivered (`time()`),
    #                       for the rate limit of idle motion
    pending_input::Union{WindowInput, Nothing}
    pending_motion::Union{WindowInput, Nothing}
    last_hover_motion::Float64
    # The SDL user-event type `wake_backend!` pushes to end a wait in
    # progress. Zero until `initialize_backend!` registers one; a wake on an
    # uninitialized backend is a no-op.
    wake_event_type::UInt32
    # The display the windows are drawn on (see the docstring).
    display::Display
end

# `partial_render` / `debug_dirty` default to the PROJECTURED_PARTIAL_RENDER /
# PROJECTURED_DEBUG_DIRTY env vars (via `_envflag`) when left as `nothing`, so a
# bare `SdlBackend()` keeps the env-driven defaults; pass an explicit `Bool` to
# override (e.g. `run_example(...; backend=SdlBackend(partial_render=false,
# debug_dirty=true))` — `run_example` itself takes no such keywords).
SdlBackend(; partial_render::Union{Bool,Nothing} = nothing,
             debug_dirty::Union{Bool,Nothing}    = nothing) =
    SdlBackend(Dict{Symbol, SdlWindowResources}(),
               Dict{UInt32, Symbol}(),
               partial_render === nothing ? _envflag("PROJECTURED_PARTIAL_RENDER", false) : partial_render,
               debug_dirty    === nothing ? _envflag("PROJECTURED_DEBUG_DIRTY", false)    : debug_dirty,
               nothing, nothing, 0.0, UInt32(0), Display())

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
    dw::Int   # device px width  (the logical size follows at each draw, from the ratio)
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
# `partial_render` of the backend is the master switch (false forces the
# full-frame repaint). `debug_dirty` of the backend, when on, outlines the
# repainted region in red so it is visible which part of the screen was painted.
# Both default to the PROJECTURED_PARTIAL_RENDER / PROJECTURED_DEBUG_DIRTY env
# vars, and `_render_window!` reads them from the backend of the window.

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
    # Clipboard projection chords (ClipboardModule): the letter and
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

# The buttons that the mask of `SDL_GetMouseState` holds.
_get_held_mouse_buttons(bstate::UInt32) =
    MouseButtons((bstate & UInt32(0x01)) != UInt32(0),
                 (bstate & UInt32(0x02)) != UInt32(0),
                 (bstate & UInt32(0x04)) != UInt32(0))

# ════════════════════════════════════════════════════════════════════════
# Native window lifecycle (internal helpers; driven by the reconciler in
# `write_to_devices(::SdlBackend, devices, ::ScreenDocument)`).
# ════════════════════════════════════════════════════════════════════════

# The flags a window of each style is created with. **Named, not numbered.** The
# tooltip and the floating style both carried `0x00000400` under a comment that
# called it `SDL_WINDOW_ALWAYS_ON_TOP`. It is `SDL_WINDOW_MOUSE_FOCUS`, which SDL
# REPORTS about a window and never accepts when one is made, so neither style was
# ever on top and neither flag set said what its comment said.
const _WINDOW_FLAGS_DEFAULT  = SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI
# A tooltip belongs to the window under it: it stays above, it is not a task of
# its own, and `SDL_WINDOW_TOOLTIP` is what tells the window manager to treat it
# as one and leave the keyboard where it is.
const _WINDOW_FLAGS_TOOLTIP  = SDL_WINDOW_SHOWN | SDL_WINDOW_BORDERLESS |
                               SDL_WINDOW_ALWAYS_ON_TOP | SDL_WINDOW_SKIP_TASKBAR |
                               SDL_WINDOW_TOOLTIP | SDL_WINDOW_ALLOW_HIGHDPI
const _WINDOW_FLAGS_FLOATING = SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE |
                               SDL_WINDOW_ALWAYS_ON_TOP | SDL_WINDOW_ALLOW_HIGHDPI

function _window_flags(style::Symbol)
    style === :tooltip  && return _WINDOW_FLAGS_TOOLTIP
    style === :floating && return _WINDOW_FLAGS_FLOATING
    return _WINDOW_FLAGS_DEFAULT
end

# The same flags, with the window held back until it holds a frame. A window
# that is shown before it is painted holds an undefined back buffer, and the
# compositor draws that black, so a tooltip flashes black and fills in after.
_hidden_window_flags(style::Symbol) =
    (UInt32(_window_flags(style)) & ~UInt32(SDL_WINDOW_SHOWN)) | UInt32(SDL_WINDOW_HIDDEN)

# Open one native SDL window for a WindowDocument and return the resource record.
# The window is drawn at the device pixel ratio of the `Display` of `backend`.
function _open_native_window!(backend::SdlBackend, w::WindowDocument; hidden::Bool = false)
    px = w.x < 0 ? SDL_WINDOWPOS_CENTERED : Int32(w.x)
    py = w.y < 0 ? SDL_WINDOWPOS_CENTERED : Int32(w.y)
    flags = hidden ? _hidden_window_flags(w.style) : UInt32(_window_flags(w.style))
    ratio = get_device_pixel_ratio(backend.display)
    # WindowDocument sizes are logical; the native window is device pixels.
    win = SDL_CreateWindow(w.title, px, py,
        Int32(max(_to_device(w.width, ratio), 1)),
        Int32(max(_to_device(w.height, ratio), 1)), flags)
    @assert win != C_NULL "SDL window creation failed: $(unsafe_string(SDL_GetError()))"

    # Linear filtering so the supersampled target downsamples smoothly.
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "1")
    renderer = SDL_CreateRenderer(win, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC)
    # A machine with no accelerated driver — a headless build, a virtual machine
    # without GL, the dummy video driver — has a software one, and drawing
    # slowly is better than not drawing.
    renderer == C_NULL && (renderer = SDL_CreateRenderer(win, -1, 0))
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
    _drop_pathological_vsync!(renderer)

    if _update_display_scale!(win, renderer)
        backend.display.scale = _PROBED_DISPLAY_SCALE[]
        ratio = get_device_pixel_ratio(backend.display)
    end

    sdl_id = UInt32(SDL_GetWindowID(win))
    SdlWindowResources(win, renderer, w.id, sdl_id, w.title,
                       Int(w.width), Int(w.height), Int(w.x), Int(w.y),
                       w.style, w.bg, _window_supersample(), ratio, C_NULL, 0, 0,
                       true, Dict{UInt,NTuple{4,Int}}(), NTuple{4,Int}[])
end

# ── Vsync, where it works ──────────────────────────────────────────────
#
# The renderer above asks for `SDL_RENDERER_PRESENTVSYNC`, which is right on a
# display that has a vertical blank: `SDL_RenderPresent` waits for it, the frame
# rate settles at the refresh rate, and nothing tears.
#
# **On a display that has no vertical blank, that wait is not a frame — it is a
# timeout.** A headless or virtual X server (`xrandr` shows a screen and no
# output) makes each present block for about a second, measured here. The editor
# then draws ONE FRAME A SECOND however cheap its frame is, because it spends
# 989 ms of every second inside the present and 0.5 ms drawing. Everything
# animated stops looking animated, and nothing above this line can tell.
#
# So the present is TIMED once, at the window that is about to use it, and vsync
# is switched off when the number is impossible. The threshold is far above any
# real refresh — 24 Hz is 42 ms and the slowest real panel is nowhere near a
# tenth of a second — and far below the fault, which is twenty times it.
const _VSYNC_PRESENT_LIMIT = 0.1     # seconds; above this, a present is not a refresh
const _VSYNC_PROBE_FRAMES  = 3

function _drop_pathological_vsync!(renderer)
    # The first present of a fresh renderer sets things up and says nothing
    # about the ones after it, so it is taken and discarded.
    SDL_RenderPresent(renderer)
    # The probe ENDS at the first bad one rather than taking all three, because
    # the bad case is the expensive one: three probes of a second each would be
    # three seconds of startup on exactly the display this is here to rescue. A
    # healthy display pays the whole probe, which is three refreshes — 50 ms at
    # 60 Hz, once per window.
    for _ in 1:_VSYNC_PROBE_FRAMES
        started = time_ns()
        SDL_RenderPresent(renderer)
        elapsed = (time_ns() - started) / 1e9
        elapsed <= _VSYNC_PRESENT_LIMIT && continue
        took = round(elapsed * 1000; digits = 1)
        if SDL_RenderSetVSync(renderer, Cint(0)) == 0
            @warn "[sdl] vsync off — a present took $(took) ms, which is a timeout " *
                  "and not a refresh (this display has no vertical blank)"
        else
            # Older SDL has no runtime toggle. Say so rather than leave a person
            # wondering why the editor draws once a second.
            @warn "[sdl] a present took $(took) ms, which is a timeout and not a " *
                  "refresh, and this SDL cannot switch vsync off at runtime — " *
                  "the editor will draw about one frame a second"
        end
        return renderer
    end
    renderer
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
# backbuffer and the OS are in *device* pixels. `ratio` is the number of device
# pixels in one logical pixel. `_to_device` sizes native windows / SSAA targets;
# `_to_logical` maps incoming device-space input (mouse, resize) back to the
# logical space everything else lives in.
_to_device(px, ratio::Float64) = round(Int, px * ratio)
_to_logical(px, ratio::Float64) = round(Int, px / ratio)

# Idle (no-button) mouse motion is forwarded for hover features (e.g. the
# reference inspector) but rate-limited so a probe does not run on every pixel.
# Button-held motion (drag) is never throttled. Each backend keeps the time of
# its last idle motion in `last_hover_motion`.
const _HOVER_MOTION_INTERVAL = 0.03   # seconds (~33 Hz)

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

# Find the scale of the display: the number of device pixels in one logical pixel
# of the hardware. The scale is a fact of the machine, not of an editor, so the
# probe runs once in a process and keeps its result in `_PROBED_DISPLAY_SCALE`.
# `configure_devices!` copies it into the `Display` of each editor.
#
# Two-phase detection:
#
#   _detect_display_scale!() — called from initialize_backend! and from
#   get_sdl_display_size, before any window exists:
#     1. PROJECTURED_DISPLAY_SCALE env var — explicit override, always respected.
#     2. Xft.dpi from X resources — reliable on X11/XWayland (GNOME writes
#        Xft.dpi = 96 × scale, e.g. 192 for 200%).
#
#   _update_display_scale!(win, renderer) — called when a window opens, only if
#   the window-free phase found nothing:
#     3. SDL renderer-output / window-size ratio — macOS Retina, native Wayland.
#     4. SDL_GetDisplayDPI / 96 — Windows fallback.
#
# Falls back to 1.0 (no scaling) if nothing fires.
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
const _PROBED_DISPLAY_SCALE   = Ref(1.0)

function _detect_display_scale!()
    _DISPLAY_SCALE_PROBED[] && return _DISPLAY_SCALE_DETECTED[]
    _DISPLAY_SCALE_PROBED[] = true

    # 1. Explicit override.
    env_val = get(ENV, "PROJECTURED_DISPLAY_SCALE", "")
    if !isempty(env_val)
        scale = tryparse(Float64, env_val)
        if scale !== nothing && scale > 0
            _PROBED_DISPLAY_SCALE[] = scale
            _DISPLAY_SCALE_DETECTED[] = true
            println("Display scale: $(_PROBED_DISPLAY_SCALE[]) (PROJECTURED_DISPLAY_SCALE)")
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
                    _PROBED_DISPLAY_SCALE[] = xft_dpi / 96.0
                    _DISPLAY_SCALE_DETECTED[] = true
                    println("Display scale: $(_PROBED_DISPLAY_SCALE[]) (Xft.dpi = $xft_dpi)")
                    return true
                end
            end
        catch
            # xrdb not installed or failed — fall through.
        end
    end

    return false
end

# Answers `true` when this call found the scale.
function _update_display_scale!(win::Ptr{SDL_Window}, renderer::Ptr{SDL_Renderer})
    # Skip if a window-free phase already found the scale.
    _DISPLAY_SCALE_DETECTED[] && return false

    # SDL renderer output size vs logical window size.
    dw = Ref{Cint}(0); dh = Ref{Cint}(0)
    ww = Ref{Cint}(0); wh = Ref{Cint}(0)
    SDL_GetRendererOutputSize(renderer, dw, dh)
    SDL_GetWindowSize(win, ww, wh)
    if ww[] > 0 && dw[] > ww[]
        _PROBED_DISPLAY_SCALE[] = Float64(dw[]) / Float64(ww[])
        _DISPLAY_SCALE_DETECTED[] = true
        println("Display scale: $(_PROBED_DISPLAY_SCALE[]) (SDL renderer ratio)")
        return true
    end

    # SDL DPI fallback (Windows / some X11 setups).
    display_index = SDL_GetWindowDisplayIndex(win)
    display_index < 0 && return false
    ddpi = Ref{Cfloat}(0)
    hdpi = Ref{Cfloat}(0)
    vdpi = Ref{Cfloat}(0)
    if SDL_GetDisplayDPI(display_index, ddpi, hdpi, vdpi) == 0 && ddpi[] > 0
        _PROBED_DISPLAY_SCALE[] = Float64(ddpi[]) / 96.0
        _DISPLAY_SCALE_DETECTED[] = true
        println("Display scale: $(_PROBED_DISPLAY_SCALE[]) (SDL DPI = $(ddpi[]))")
        return true
    end
    false
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

# The handle of `font` at the device size for `ratio`.
function _get_font(font::StyleFont, ratio::Float64)
    size = font_device_size(font, ratio)
    key = (font.filename, size)
    get!(_font_cache, key) do
        # `font_file` and not `font.filename`: the name a `StyleFont` carries is
        # where the font was when the style package was compiled, and a bundle
        # copied to another machine has it somewhere else. The metrics reader
        # resolves the same way, so SDL and it always open one file.
        path = font_file(font.filename)
        f = TTF_OpenFont(path, size)
        @assert f != C_NULL "Font load failed: $path@$(size)"
        f
    end
end

# ── Fallback fonts ─────────────────────────────────────────────────────
#
# SDL2_ttf draws a character only in the font it is given, and a font it lacks
# draws as a `.notdef` box. So a text is split into runs, one per font, and
# `find_glyph_font_file` says which font draws each character. The measurer
# `measure_truetype_text` asks the same question, so a line is drawn as wide as
# the layout measured it. The fallback fonts are monochrome, so every run draws
# through the same blended path.

# Open (and cache) the font file at `path` at `size` device px. C_NULL when the
# file is absent or fails to load, so a caller draws in the primary font.
function _get_fallback_font(path::String, size::Int)
    key = (path, size)
    get!(_font_cache, key) do
        file = font_file(path)
        isfile(file) ? TTF_OpenFont(file, size) : Ptr{TTF_Font}(C_NULL)
    end
end

# The font that draws codepoint `cp` in a text set in `font`, whose handle is
# `primary`, at the device size for `ratio`.
function _glyph_font(cp::UInt32, font::StyleFont, primary::Ptr{TTF_Font}, ratio::Float64)
    file = find_glyph_font_file(font.filename, cp)
    (file === nothing || file == font.filename) && return primary
    handle = _get_fallback_font(file, font_device_size(font, ratio))
    handle == C_NULL ? primary : handle
end

# Split `text` into maximal consecutive runs that share one font. Presentation
# selectors (U+FE0E/U+FE0F) are dropped — zero-width hints that would otherwise
# draw a stray box; ZWJ (U+200D) and skin-tone modifiers stay in the current run
# so they bind to the preceding emoji. A text the primary font carries in full is
# a single run. Without shaping, ZWJ and skin-tone sequences draw as their
# separate base glyphs. A fallback font opens at the device size for `ratio`.
function _font_runs(text::AbstractString, font::StyleFont, primary::Ptr{TTF_Font},
                    ratio::Float64)
    runs = Tuple{Ptr{TTF_Font},String}[]
    carried = load_truetype_font(font.filename)
    buf = IOBuffer()
    cur = primary
    started = false
    for ch in text
        cp = UInt32(ch)
        is_presentation_selector(cp) && continue
        sticky = started && (cp == 0x200D || 0x1F3FB <= cp <= 0x1F3FF)
        f = sticky ? cur :
            (cp <= 0xFFFF && has_font_glyph(carried, cp)) ? primary :
            _glyph_font(cp, font, primary, ratio)
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

# `ratio` is the number of device pixels in one logical pixel of the render.
function _render_element!(renderer::Ptr{SDL_Renderer}, elem::GraphicsText, ox::Int, oy::Int,
                          ratio::Float64)
    text = elem.text::AbstractString
    isempty(text) && return

    font_style = elem.font::StyleFont
    color = _rgba8(elem.color)
    key = _TextTextureKey(renderer, String(text), font_style.filename,
                          font_device_size(font_style, ratio), color)

    # Reuse the uploaded texture for an unchanged (text, font, colour) span;
    # rasterize + upload only on a cache miss. The texture is rasterized at
    # device size and freed when its renderer is torn down.
    entry = get(_text_texture_cache, key, nothing)
    if entry === nothing
        font = _get_font(font_style, ratio)
        runs = _font_runs(text, font_style, font, ratio)
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

    # The destination rect is in logical pixels (= device size ÷ ratio). The
    # renderer scale then maps it back to device pixels, so the texture lands
    # 1:1 and stays crisp.
    dest = Ref(SDL_Rect(elem.x + ox, elem.y + oy,
                        Int32(_to_logical(entry.dw, ratio)),
                        Int32(_to_logical(entry.dh, ratio))))
    SDL_RenderCopy(renderer, entry.texture, C_NULL, dest)
end

# ── Render a GraphicsViewport element ────────────────────────────────

# The intersection of two clip rectangles, empty when they do not meet.
function _clip_intersect(a::SDL_Rect, b::SDL_Rect)
    x1 = max(a.x, b.x)
    y1 = max(a.y, b.y)
    x2 = min(a.x + a.w, b.x + b.w)
    y2 = min(a.y + a.h, b.y + b.h)
    SDL_Rect(Int32(x1), Int32(y1), Int32(max(0, x2 - x1)), Int32(max(0, y2 - y1)))
end

# The clip rectangle in force, or `nothing` when there is none.
function _clip_current(renderer::Ptr{SDL_Renderer})
    SDL_RenderIsClipEnabled(renderer) == SDL_FALSE && return nothing
    r = Ref(SDL_Rect(Int32(0), Int32(0), Int32(0), Int32(0)))
    SDL_RenderGetClipRect(renderer, r)
    r[]
end

# Put back the clip that was in force, or remove clipping when there was none.
_clip_restore!(renderer::Ptr{SDL_Renderer}, prev::Nothing) =
    SDL_RenderSetClipRect(renderer, C_NULL)
_clip_restore!(renderer::Ptr{SDL_Renderer}, prev::SDL_Rect) =
    SDL_RenderSetClipRect(renderer, Ref(prev))

# Viewports nest, and SDL's clip rectangle does not. `SDL_RenderSetClipRect`
# REPLACES what is in force, and clearing it with `C_NULL` removes clipping
# altogether rather than putting the enclosing one back. Left to SDL, a viewport
# inside a viewport would widen the clip to its own box on the way in and remove
# it entirely on the way out: everything drawn after an inner viewport, still
# inside the outer one, would be unclipped, and a tab page holding a scroll pane
# would draw its later content over the tab strip and outside the page.
#
# So a viewport intersects with the clip in force, and restores it afterwards.
function _render_viewport!(renderer::Ptr{SDL_Renderer}, vp::GraphicsViewport, ox::Int, oy::Int,
                          ratio::Float64)
    vx = Int(vp.x) + ox
    vy = Int(vp.y) + oy
    vw = Int(vp.w)
    vh = Int(vp.h)
    canvas = vp.content::GraphicsCanvas
    cx, cy = Int(canvas.x), Int(canvas.y)
    M = vp.transform::AffineTransform
    prev = _clip_current(renderer)
    if M === affine_identity || (M.a == 1.0 && M.d == 1.0 && M.e == 0.0 && M.f == 0.0 &&
                                 is_affine_axis_aligned(M))
        # Fast path: identity transform — clip + draw exactly as before.
        box = SDL_Rect(Int32(vx), Int32(vy), Int32(vw), Int32(vh))
        SDL_RenderSetClipRect(renderer, Ref(prev === nothing ? box : _clip_intersect(box, prev)))
        _render_canvas!(renderer, canvas, vx + cx, vy + cy, vx + vw, vy + vh, ratio)
        _clip_restore!(renderer, prev)
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
    # viewport box regardless of the content scale. The intersection is taken in
    # the OLD units, where the enclosing clip is expressed, and converted after.
    box = SDL_Rect(Int32(vx), Int32(vy), Int32(vw), Int32(vh))
    box = prev === nothing ? box : _clip_intersect(box, prev)
    clip = Ref(SDL_Rect(Int32(round(box.x / sx)), Int32(round(box.y / sy)),
                        Int32(round(box.w / sx)), Int32(round(box.h / sy))))
    SDL_RenderSetClipRect(renderer, clip)
    # A content-local element coord `l` must land at viewport-space `t + s*(c+l)`;
    # under the scaled renderer the passed origin is therefore `(v+t)/s + c`.
    org_x = round(Int, (vx + tx) / sx) + cx
    org_y = round(Int, (vy + ty) / sy) + cy
    clip_r = round(Int, (vx + vw) / sx)
    clip_b = round(Int, (vy + vh) / sy)
    _render_canvas!(renderer, canvas, org_x, org_y, clip_r, clip_b, ratio)
    SDL_RenderSetScale(renderer, Cfloat(base_x), Cfloat(base_y))
    _clip_restore!(renderer, prev)
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
        tri = build_polyline_arrowhead(pts, arrow_size; at_end=true)
        isempty(tri) || _fill_triangle!(renderer, tri, r, g, b, a)
    end
    if start_arrow
        tri = build_polyline_arrowhead(pts, arrow_size; at_end=false)
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

# `ratio` is the number of device pixels in one logical pixel of the render. Only
# a text reads it: it rasterizes its glyphs at the device size.
function _render_canvas!(renderer::Ptr{SDL_Renderer}, canvas::GraphicsCanvas, ox::Int, oy::Int,
                         vw::Int, vh::Int, ratio::Float64)
    layout = canvas.layout
    elements = canvas.elements
    early_stop = !canvas.overlapping_elements && layout != layout_none
    if elements isa ListNode
        # Traverse prev links to render content before the head (e.g. negative y offsets)
        prev_node = elements.prev
        while prev_node !== nothing
            elem = prev_node.value
            if !(elem isa GraphicsFence)
                _dispatch_render_elem!(renderer, elem, ox, oy, vw, vh, ratio)
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
                _dispatch_render_elem!(renderer, elem, ox, oy, vw, vh, ratio)
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
            _dispatch_render_elem!(renderer, elem, ox, oy, vw, vh, ratio)
        end
    end
end

function _dispatch_render_elem!(renderer::Ptr{SDL_Renderer}, elem, ox::Int, oy::Int,
                                vw::Int, vh::Int, ratio::Float64)
    if elem isa GraphicsText
        _render_element!(renderer, elem, ox, oy, ratio)
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
        _render_viewport!(renderer, elem, ox, oy, ratio)
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
        _render_canvas!(renderer, elem, ox + cx, oy + cy, vw, vh, ratio)
    end
    # GraphicsFence and unknown types are silently skipped
end

_render_elem_x(elem) = hasproperty(elem, :x) ? Int(elem.x) : nothing
_render_elem_y(elem) = hasproperty(elem, :y) ? Int(elem.y) : nothing

# ── Per-window paint ──────────────────────────────────────────────────

# Clear and repaint one native window's canvas. Called by the
# reconciler once per WindowDocument per frame.
# Ensure the SSAA render target exists and matches the device backbuffer size
# times the supersample factor (`width*ratio*ss × height*ratio*ss`), recreating
# it on size change. Returns true if a usable target is in place.
function _ensure_ss_target!(res::SdlWindowResources)
    tw = _to_device(res.width, res.ratio) * res.ss
    th = _to_device(res.height, res.ratio) * res.ss
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
# A text is measured at `ratio`, the ratio it is drawn at, so its bounds cover
# every pixel that the render gives it.
# These reuse the existing `_bounds_elem!` / `_accumulate_bounds!` machinery
# (and so recompute the cells they read — exactly what we want, since the unit
# is about to be repainted).
function _bounds_of_elem(elem, ox::Int, oy::Int, ratio::Float64)
    mnx = Ref(typemax(Int)); mny = Ref(typemax(Int))
    mxx = Ref(typemin(Int)); mxy = Ref(typemin(Int))
    measure = (text, font) -> _measure_sdl_text(text, font, ratio)
    _bounds_elem!(elem, ox, oy, measure, mnx, mny, mxx, mxy)
    mxx[] == typemin(Int) ? nothing : (mnx[], mny[], mxx[], mxy[])
end

function _bounds_of_canvas(canvas::GraphicsCanvas, ox::Int, oy::Int, ratio::Float64)
    mnx = Ref(typemax(Int)); mny = Ref(typemax(Int))
    mxx = Ref(typemin(Int)); mxy = Ref(typemin(Int))
    measure = (text, font) -> _measure_sdl_text(text, font, ratio)
    _accumulate_bounds!(canvas, ox, oy, measure, mnx, mny, mxx, mxy)
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
        _union_unit!(res, acc, objectid(canvas), _bounds_of_canvas(canvas, ox, oy, res.ratio))
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
        _union_unit!(res, acc, objectid(elem), _bounds_of_elem(elem, ox, oy, res.ratio))
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
            b = _bounds_of_elem(val, ox, oy, res.ratio)
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
            _union_unit!(res, acc, objectid(n), _bounds_of_elem(val, ox, oy, res.ratio))
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
function _render_window!(backend::SdlBackend, res::SdlWindowResources,
                         canvas::GraphicsCanvas)
    partial = backend.partial_render
    debug = backend.debug_dirty
    bg = res.bg
    renderer = res.renderer
    scale = Float32(res.ratio)

    if !_ensure_ss_target!(res)
        # No usable retained target — fall back to the classic full repaint
        # straight to the window backbuffer.
        SDL_RenderSetScale(renderer, scale, scale)
        SDL_SetRenderDrawColor(renderer, bg[1], bg[2], bg[3], bg[4])
        SDL_RenderClear(renderer)
        _render_canvas!(renderer, canvas, 0, 0, res.width, res.height, res.ratio)
        SDL_RenderSetScale(renderer, 1.0f0, 1.0f0)
        SDL_RenderPresent(renderer)
        return
    end

    # Decide the region to repaint.
    if !partial
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
    _render_canvas!(renderer, canvas, 0, 0, res.width, res.height, res.ratio)
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
    if !partial || debug || age <= 0 || (age - 1) > length(res.damage_history)
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

    if debug
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
pixels — the space all layout lives in. The glyphs are rasterized at the device
size for the device pixel ratio of the `Display` of `backend` (for crispness),
and the device measurement is divided back by that ratio. Font handles are
cached in the module-level [`_font_cache`](@ref).
"""
BackendModule.measure_text(backend::SdlBackend, text::AbstractString, font::StyleFont) =
    _measure_sdl_text(text, font, get_device_pixel_ratio(backend.display))

# The logical size of `text` in `font`, measured at the device size for `ratio`.
function _measure_sdl_text(text::AbstractString, font::StyleFont, ratio::Float64)
    isempty(text) && return (0, font_logical_size(font))
    primary = _get_font(font, ratio)
    runs = _font_runs(text, font, primary, ratio)
    # Fast path: a single run — all in the primary font (the common case) or all
    # in one fallback font. Measure with that run's own font, not `primary`,
    # otherwise a pure-emoji span would be sized from the text font's `.notdef` box.
    if length(runs) == 1
        f, s = runs[1]
        w_ref, h_ref = Ref{Cint}(0), Ref{Cint}(0)
        TTF_SizeUTF8(f, s, w_ref, h_ref)
        return (_to_logical(Int(w_ref[]), ratio), _to_logical(Int(h_ref[]), ratio))
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
    return (_to_logical(total_w, ratio), _to_logical(max_ascent + max_below, ratio))
end

# ── Standalone convenience function ──────────────────────────────────

"""
    measure_sdl_text(text, font) -> (Int, Int)

Standalone text measurement using SDL_ttf. Returns `(pixel_width, pixel_height)`
in logical pixels, measured at the device pixel ratio 1, so the result does not
depend on the display of the machine. Uses a module-level font cache.
"""
measure_sdl_text(text, font) = _measure_sdl_text(text, font, 1.0)

# ── Canvas rasterization ──────────────────────────────────────────────

"""
    render_sdl_canvas(canvas::GraphicsCanvas) -> GraphicsImage

Render `canvas` to an offscreen SDL texture and return a `GraphicsImage`
holding the texture pointer as `data`. The caller is responsible for
eventually destroying the texture. Has the `(canvas) -> GraphicsImage`
signature expected by `GraphicsCaching`.

NOTE: requires an active SDL window/renderer. Currently uses the renderer
of the first open window — a proper implementation will accept a renderer
parameter or use a shared offscreen context.
"""
function render_sdl_canvas(canvas::GraphicsCanvas)
    GraphicsImage(Int32(0), Int32(0), Int32(0), Int32(0), nothing)
end

# Backend-interface methods: let callers reach SDL rendering/decoding/display
# through the generic BackendModule seams without naming ProjecturedSdl, so the
# SDL backend can move into an optional extension.
BackendModule.render_canvas(canvas::GraphicsCanvas) = render_sdl_canvas(canvas)

# ════════════════════════════════════════════════════════════════════════
# Offscreen rendering / write_image
# ════════════════════════════════════════════════════════════════════════

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
# into it. The glyphs rasterize at the device size for the export scale `off.sc`,
# which matches the scale of the renderer.
function _render_canvas_offscreen!(off, canvas::GraphicsCanvas, width::Integer,
                                   height::Integer, background::NTuple{4,UInt8})
    r, g, b, a = background
    SDL_SetRenderDrawColor(off.renderer, r, g, b, a)
    SDL_RenderClear(off.renderer)
    _render_canvas!(off.renderer, canvas, 0, 0, Int(width), Int(height), off.sc)
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
# `get_canvas_content_bounds` / `_accumulate_bounds!` / `_bounds_elem!` now live in
# `GraphicsModule` (pure geometry over a `measure` callback, no SDL), imported
# above and shared with the PDF backend. `write_image` passes `measure_sdl_text`.

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
    TextToGraphics(measure=measure_sdl_text),
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
    # `get_canvas_content_bounds` returns (minx, miny, maxx, maxy). The natural size
    # must span the full extent — including any content at negative coordinates —
    # so subtract a negative min rather than dropping it.
    minx, miny, maxx, maxy = get_canvas_content_bounds(canvas, measure_sdl_text)
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
        minx, miny, maxx, maxy = get_canvas_content_bounds(canvas, measure_sdl_text)
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
        shifted = GraphicsCanvas(canvas.elements; x = ox, y = oy, layout = canvas.layout,
                                 overlapping = canvas.overlapping_elements)
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
    TextToGraphics(measure=measure_sdl_text),
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
    backend.display.scale = _PROBED_DISPLAY_SCALE[]
    # Start with no input owed: a backend that is opened again must not answer
    # with an event left over from its last life.
    backend.pending_input = nothing
    backend.pending_motion = nothing
    # The wake event, registered once per SDL life. `SDL_RegisterEvents`
    # answers `(Cuint)-1` when the pool is exhausted; the wait then degrades
    # to its timeout slices and nothing else is lost.
    registered = SDL_RegisterEvents(Int32(1))
    backend.wake_event_type = registered == typemax(UInt32) ? UInt32(0) : registered
    nothing
end

function BackendModule.quit_backend!(backend::SdlBackend)
    backend.pending_input = nothing
    backend.pending_motion = nothing
    SDL_StopTextInput()
    # Free cached textures while their renderers are still alive (before SDL_Quit).
    _clear_text_texture_cache!()
    for font in values(_font_cache)
        # `_get_fallback_font` caches C_NULL when a fallback font is absent; skip
        # those (TTF_CloseFont(NULL) dereferences a null pointer).
        font != C_NULL && TTF_CloseFont(font)
    end
    empty!(_font_cache)
    TTF_Quit()
    SDL_Quit()
    # The first SDL video init registers this process with LaunchServices as a
    # Foreground GUI app (dock icon, Force Quit entry). That registration is
    # one-way — `SDL_Quit` never lowers it back down — so once the last window
    # is gone and nothing pumps Cocoa's event loop any more, macOS flags the
    # process "not responding": a permanent beachball on the dock icon even
    # though the REPL underneath is perfectly healthy. Drop the policy back to
    # Accessory so macOS stops expecting a foreground app to answer. SDL's
    # video init raises it back to Regular on its own the next time a backend
    # is opened, so this only needs to run on the way out.
    Sys.isapple() && _macos_drop_activation_policy_to_accessory!()
end

# NSApplicationActivationPolicyAccessory: no dock icon, no menu bar, no Force
# Quit entry — the identity a process with no open windows should have.
const _NS_ACTIVATION_POLICY_ACCESSORY = 1

# ccall's library expression must be a literal or a global constant — never a
# local variable — so the ObjC runtime's path is hoisted out of the function.
const _LIBOBJC = "libobjc.A.dylib"

# Equivalent to the Objective-C call
# `[[NSApplication sharedApplication] setActivationPolicy:NSApplicationActivationPolicyAccessory]`,
# made through the ObjC runtime C API since this file has no Cocoa/AppKit
# binding to call it through directly. `id` and `Class` are opaque pointers
# and `SEL` is an opaque pointer; `NSApplicationActivationPolicy` is an
# `NSInteger` (`Clong`, 8 bytes on arm64/x86_64) and `setActivationPolicy:`
# returns `BOOL` (1 byte) — the return value is unused here.
function _macos_drop_activation_policy_to_accessory!()
    ns_application = ccall((:objc_getClass, _LIBOBJC), Ptr{Cvoid}, (Cstring,), "NSApplication")
    sel_shared_application = ccall((:sel_registerName, _LIBOBJC), Ptr{Cvoid}, (Cstring,), "sharedApplication")
    shared_application = ccall((:objc_msgSend, _LIBOBJC), Ptr{Cvoid},
                                (Ptr{Cvoid}, Ptr{Cvoid}), ns_application, sel_shared_application)
    sel_set_activation_policy = ccall((:sel_registerName, _LIBOBJC), Ptr{Cvoid}, (Cstring,), "setActivationPolicy:")
    ccall((:objc_msgSend, _LIBOBJC), Cuchar, (Ptr{Cvoid}, Ptr{Cvoid}, Clong),
          shared_application, sel_set_activation_policy, _NS_ACTIVATION_POLICY_ACCESSORY)
    nothing
end

# ════════════════════════════════════════════════════════════════════════
# Device I/O
# ════════════════════════════════════════════════════════════════════════

# The library handle the GC-safe wait calls into directly: the generated
# LibSDL2 wrapper carries no `gc_safe` option, and a collection on another
# thread must not stall behind a blocked wait.
const _LIBSDL2 = SimpleDirectMediaLayer.LibSDL2.libsdl2

# How long one wait slice blocks this thread. On a single-threaded process
# the cooperative tasks of this thread — the MCP server, the assistant — run
# only between slices, so the slice is the 10 ms cadence the polling loop
# had. With more threads a longer slice only bounds how long a task that
# still lives on this thread waits for its turn.
_get_wait_slice_seconds() = Threads.nthreads() == 1 ? 0.01 : 0.1

# Block until the SDL queue holds an event or `milliseconds` pass, without
# removing anything: the NULL event pointer is SDL's look-only form, so
# everything stays queued for `read!`. Must run on the thread that
# initialized the video subsystem — it pumps events.
_wait_for_queued_event(milliseconds::Integer) =
    (@ccall gc_safe=true _LIBSDL2.SDL_WaitEventTimeout(C_NULL::Ptr{Cvoid},
                                                       Cint(milliseconds)::Cint)::Cint) == 1

"""
    wait_for_input(backend::SdlBackend, devices, timeout_seconds) -> Nothing

Block until the SDL queue holds an event, [`wake_backend!`](@ref) pushes the
wake event, or `timeout_seconds` passes. The queue is only looked at, never
read: everything stays for `read!`. An event this backend already owes
(`pending_input`) ends the wait before it starts, and a held motion sample
caps the timeout at the rest of its rate-limit interval, so the last sample
of a pointer that stopped is delivered on time.

The block runs in GC-safe slices (`_get_wait_slice_seconds`) with a `yield`
between them, so cooperative tasks that live on this thread keep their turn.
"""
function BackendModule.wait_for_input(backend::SdlBackend, devices, timeout_seconds)
    backend.pending_input === nothing || return nothing
    timeout = Float64(timeout_seconds)
    if backend.pending_motion !== nothing
        remaining = _HOVER_MOTION_INTERVAL - (time() - backend.last_hover_motion)
        remaining <= 0 && return nothing
        timeout = min(timeout, remaining)
    end
    deadline = time() + timeout                       # Inf stays Inf
    slice = _get_wait_slice_seconds()
    while true
        this_slice = min(slice, deadline - time())
        this_slice <= 0 && return nothing
        milliseconds = clamp(ceil(Int, this_slice * 1000), 1, 1000)
        _wait_for_queued_event(milliseconds) && return nothing
        yield()                                       # the cooperative tasks' turn
    end
end

"""
    wake_backend!(backend::SdlBackend) -> Nothing

End a [`wait_for_input`](@ref) in progress by pushing this backend's wake
event. Thread-safe: `SDL_PushEvent` is the SDL entry point documented for
cross-thread use. The event carries nothing and `_poll_window_input` skips
it, because the editor's wake-pending flag is the truth and this push is
only the kick that ends the wait. A backend without a registered wake event
declines the kick; the sliced wait notices pending work on its next slice.
"""
function BackendModule.wake_backend!(backend::SdlBackend)
    backend.wake_event_type == UInt32(0) && return nothing
    event = Ref{SDL_Event}()
    ccall(:memset, Ptr{Cvoid}, (Ptr{Cvoid}, Cint, Csize_t), event, 0, sizeof(SDL_Event))
    GC.@preserve event begin
        unsafe_store!(Ptr{UInt32}(Base.unsafe_convert(Ptr{SDL_Event}, event)),
                      backend.wake_event_type)
    end
    SDL_PushEvent(event)
    nothing
end

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
- `SDL_MOUSEMOTION`                    → `WindowInput(<id>, MouseMove)` (coalesced)
- `SDL_MOUSEWHEEL`                     → `WindowInput(<id>, MouseScroll)`

`<id>` is the `WindowDocument.id` of the originating window (looked up
in `backend.window_ids`), or `:none` if the SDL event carries no window
id or refers to a window the backend does not track.

The backend emits only raw events; the `MousePress` click is synthesised from
the `MouseDown`/`MouseUp` pair by the editor's `GestureRecognizer`, not here.

## Pointer motion is coalesced

A pointer reports its position far more often than a frame can act on one, so a
poll finds a run of motion events queued. Only the newest of them says where the
pointer *is*; the older ones say where it was. This call collapses such a run and
answers with the newest sample, rather than answering with the oldest and
leaving the newer ones for a later call to discard — which is what made the
highlight trail the pointer by a frame.

Order is preserved. An event that is not motion ends the run: the held motion is
answered first and the other event is kept in `backend.pending_input` for the
next call, so a click never overtakes the motion that led to it.

Idle motion (no button held) is still rate-limited to one sample per
`_HOVER_MOTION_INTERVAL`. A blocked sample is *held* in
`backend.pending_motion`, not dropped: a pointer that stops sends nothing more,
and dropping its last sample would leave the highlight one step behind for as
long as the pointer rests there. A held sample is answered anyway when another
event waits behind it, because order outranks the rate limit.
"""
function BackendModule.read_from_devices(backend::SdlBackend, devices)
    # What a previous call owes: the event that ended a motion run.
    if backend.pending_input !== nothing
        owed = backend.pending_input
        backend.pending_input = nothing
        return owed
    end
    # The newest motion sample so far — carried over from a call the rate limit
    # blocked, then overwritten by anything newer this poll finds.
    motion = backend.pending_motion
    backend.pending_motion = nothing
    while true
        other, newer = _poll_window_input(backend)
        if newer !== nothing
            motion = newer                # a newer sample replaces the older one
            continue
        end
        other === nothing && break        # queue empty
        # An event that is not motion ends the run. Answer the motion first.
        motion === nothing && return other
        backend.pending_input = other
        return motion
    end
    motion === nothing && return nothing
    # A drag (a button held) is never rate-limited: it must track the pointer.
    if motion.event isa MouseMove && motion.event.buttons == MouseButtons()
        now = time()
        if (now - backend.last_hover_motion) < _HOVER_MOTION_INTERVAL
            backend.pending_motion = motion       # hold it; answer on a later call
            return nothing
        end
        backend.last_hover_motion = now
    end
    motion
end

"""
    _poll_window_input(backend) -> (other, motion)

Pop SDL events until one of them surfaces as a `WindowInput`, and answer a pair
in which exactly one member is non-`nothing`: `motion` for a `MouseMove`,
`other` for every other input. An SDL event the backend does not surface (a
window event it ignores, a text input that maps to no key) is skipped here, so
`(nothing, nothing)` means the queue is empty and nothing else.

`read_from_devices` runs it in a loop and keeps only the newest motion.
"""
function _poll_window_input(backend::SdlBackend)
    # SDL reports device pixels; the events hold logical pixels.
    ratio = get_device_pixel_ratio(backend.display)
    event_ref = Ref{SDL_Event}()
    while Bool(SDL_PollEvent(event_ref))
        evt = event_ref[]
        t = evt.type

        if t == SDL_QUIT
            return (WindowInput(:none, WindowQuit()), nothing)

        elseif t == 0x00000200  # SDL_WINDOWEVENT
            # event byte 1 = SDL_WindowEventID
            sub = evt.window.event
            wid = _lookup_window_id(backend, evt.window.windowID)
            if sub == UInt8(14)  # SDL_WINDOWEVENT_CLOSE
                return (WindowInput(wid, WindowClose()), nothing)
            elseif sub == UInt8(12)  # SDL_WINDOWEVENT_FOCUS_LOST
                return (WindowInput(wid, WindowDefocus()), nothing)
            elseif sub == UInt8(5)  # SDL_WINDOWEVENT_RESIZED (external/user only)
                # SDL reports device pixels; the document works in logical pixels.
                nw = _to_logical(Int(evt.window.data1), ratio)
                nh = _to_logical(Int(evt.window.data2), ratio)
                # Mark the resource as already at this size so the reconciler's
                # _update_window_geometry! doesn't issue a redundant
                # SDL_SetWindowSize back at the OS (which would fight the drag).
                res = get(backend.windows, wid, nothing)
                if res !== nothing
                    res.width = nw
                    res.height = nh
                end
                return (WindowInput(wid, WindowResize(nw, nh)), nothing)
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
            return (WindowInput(wid, sdl_to_keydown(keysym, evt.key.keysym.mod, is_repeat)), nothing)

        elseif t == 0x00000301  # SDL_KEYUP
            wid = _lookup_window_id(backend, evt.key.windowID)
            return (WindowInput(wid, sdl_to_keyup(evt.key.keysym.sym, evt.key.keysym.mod)), nothing)

        elseif t == 0x00000303  # SDL_TEXTINPUT
            kp = sdl_to_keypress(evt)
            kp === nothing && continue
            wid = _lookup_window_id(backend, evt.text.windowID)
            return (WindowInput(wid, kp), nothing)

        elseif t == 0x00000401  # SDL_MOUSEBUTTONDOWN
            button = _sdl_button_sym(evt.button.button)
            mods = _current_modifiers()
            x, y = _to_logical(Int(evt.button.x), ratio), _to_logical(Int(evt.button.y), ratio)
            wid = _lookup_window_id(backend, evt.button.windowID)
            return (WindowInput(wid, MouseDown(button, x, y, mods)), nothing)

        elseif t == 0x00000402  # SDL_MOUSEBUTTONUP
            button = _sdl_button_sym(evt.button.button)
            mods = _current_modifiers()
            x, y = _to_logical(Int(evt.button.x), ratio), _to_logical(Int(evt.button.y), ratio)
            wid = _lookup_window_id(backend, evt.button.windowID)
            return (WindowInput(wid, MouseUp(button, x, y, mods)), nothing)

        elseif t == 0x00000400  # SDL_MOUSEMOTION
            mx_ref, my_ref = Ref{Cint}(0), Ref{Cint}(0)
            bstate = UInt32(SDL_GetMouseState(mx_ref, my_ref))
            buttons = _get_held_mouse_buttons(bstate)
            mods = _current_modifiers()
            wid = _lookup_window_id(backend, evt.motion.windowID)
            # The motion slot of the pair. The caller keeps only the newest of a
            # run of these, and applies the rate limit to what it keeps.
            return (nothing, WindowInput(wid,
                MouseMove(_to_logical(Int(evt.motion.x), ratio),
                          _to_logical(Int(evt.motion.y), ratio), buttons, mods)))

        elseif t == 0x00000403  # SDL_MOUSEWHEEL
            mx_ref, my_ref = Ref{Cint}(0), Ref{Cint}(0)
            SDL_GetMouseState(mx_ref, my_ref)
            mods = _current_modifiers()
            wid = _lookup_window_id(backend, evt.wheel.windowID)
            dx, dy = Int(evt.wheel.x), Int(evt.wheel.y)
            if mods.shift && dx == 0
                dx, dy = dy, 0
            end
            return (WindowInput(wid,
                MouseScroll(dx, dy, _to_logical(Int(mx_ref[]), ratio),
                            _to_logical(Int(my_ref[]), ratio), mods)),
                nothing)
        end
    end
    return (nothing, nothing)
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
    open_native_windows!(backend::SdlBackend, screen::ScreenDocument)

Open a native window for each window `screen` names, then write the size the
window manager granted back into the `WindowDocument`.

A manager is free to grant less than it is asked for. It keeps a window inside
the work area, and a decorated window needs its title bar to fit there too, so a
window asked to be as tall as the whole work area is made shorter by the height
of its own title bar. The editor calls this before the first projection, so the
document is laid out once at the size the window really has. A document laid out
first is laid out at a size the window never has, and the manager's answer then
arrives as a resize that computes the whole document a second time.

This runs before `write_to_devices` ever sees a `ScreenDocument`, and it fills
the same `backend.windows` / `backend.window_ids` tables, so the reconciler
finds the windows already open and updates them instead of opening them.
"""
function BackendModule.open_native_windows!(backend::SdlBackend, screen::ScreenDocument)
    opened = UInt32[]
    for w in screen.windows
        w isa WindowDocument || continue
        haskey(backend.windows, w.id) && continue
        res = _open_native_window!(backend, w)
        backend.windows[w.id] = res
        backend.window_ids[res.sdl_id] = res.id
        push!(opened, res.sdl_id)
    end
    isempty(opened) && return nothing
    _settle_native_windows!(backend, opened)
    for w in screen.windows
        w isa WindowDocument || continue
        res = get(backend.windows, w.id, nothing)
        res === nothing && continue
        res.sdl_id in opened || continue
        w.width  = res.width
        w.height = res.height
    end
    nothing
end

# How long to wait for the window manager to answer, and how long the size must
# hold still before the answer counts as final.
const _WINDOW_SETTLE_TIMEOUT = 0.25
const _WINDOW_SETTLE_QUIET   = 0.02
const _WINDOW_SETTLE_POLL    = 0.005

# Wait for the manager's answer and record it on the resources.
#
# `SDL_CreateWindow` returns before the manager has answered, so the size read
# straight after it is still the size that was asked for. SDL learns the real one
# when it pumps the event queue, which is also where the size change is delivered
# as an event. Both are handled here: the loop pumps until the size holds still,
# and `_take_window_size_events!` keeps the size changes of these windows out of
# the queue, so the editor does not read a resize for a size the document already
# has.
function _settle_native_windows!(backend::SdlBackend, opened::Vector{UInt32})
    resources = [res for res in values(backend.windows) if res.sdl_id in opened]
    deadline = time() + _WINDOW_SETTLE_TIMEOUT
    quiet_since = time()
    last = [_native_window_size(res) for res in resources]
    while time() < deadline
        _take_window_size_events!(opened)
        current = [_native_window_size(res) for res in resources]
        if current == last
            time() - quiet_since >= _WINDOW_SETTLE_QUIET && break
        else
            last = current
            quiet_since = time()
        end
        sleep(_WINDOW_SETTLE_POLL)
    end
    for (res, (w, h)) in zip(resources, last)
        res.width  = w
        res.height = h
    end
    nothing
end

# The window's current size in logical pixels. SDL reports device pixels, which
# is what `WindowDocument` sizes are converted to when the window is created.
function _native_window_size(res::SdlWindowResources)
    w = Ref{Cint}(0); h = Ref{Cint}(0)
    SDL_GetWindowSize(res.win, w, h)
    (_to_logical(Int(w[]), res.ratio), _to_logical(Int(h[]), res.ratio))
end

# Pump the event queue, and drop the size changes belonging to the windows just
# opened. Everything else is put back, so a key pressed while the editor starts
# is still read.
function _take_window_size_events!(opened::Vector{UInt32})
    kept = SDL_Event[]
    event_ref = Ref{SDL_Event}()
    SDL_PumpEvents()
    while Bool(SDL_PollEvent(event_ref))
        evt = event_ref[]
        is_own_resize = evt.type == 0x00000200 &&        # SDL_WINDOWEVENT
                        evt.window.event == UInt8(5) &&  # SDL_WINDOWEVENT_RESIZED
                        UInt32(evt.window.windowID) in opened
        is_own_resize || push!(kept, evt)
    end
    for evt in kept
        ref = Ref(evt)
        SDL_PushEvent(ref)
    end
    nothing
end

"""
    write_to_devices(backend::SdlBackend, devices, screen::ScreenDocument)

Reconcile live native SDL windows against the projection-output
`ScreenDocument`. Windows whose id no longer appears are destroyed;
new ids cause a window to be opened; existing windows have their
geometry / title / style updated as needed, then repainted with the
matching `WindowDocument.content` canvas.

Each window is drawn at the device pixel ratio of the `Display` of `backend`,
which `configure_devices!` sets. The reconciler does not read `devices`.
"""
function BackendModule.write_to_devices(backend::SdlBackend, devices::Vector{Device}, screen::ScreenDocument)
    ratio = get_device_pixel_ratio(backend.display)
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
        canvas = w.content
        canvas isa GraphicsCanvas ||
            error("write_to_devices: WindowDocument(id=:$(w.id)).content is $(typeof(canvas)), expected GraphicsCanvas")
        # The size before the window is made, so the first frame a person sees
        # already fits, and before it is placed, because the place depends on it.
        _fit_window_size!(w, canvas)
        _place_fitted_window!(backend, w)
        res = get(backend.windows, w.id, nothing)
        if res === nothing
            res = _open_native_window!(backend, w; hidden = true)
            backend.windows[w.id] = res
            backend.window_ids[res.sdl_id] = res.id
            _show_painted_window!(backend, res, w)
        else
            _update_window_geometry!(res, w, ratio)
        end
        _render_window!(backend, res, canvas)
    end
end

"""
    _fit_window_size!(w::WindowDocument, canvas::GraphicsCanvas) -> w

Give a window that carries a `maximum_size` the extent of what it printed,
clamped between its `minimum_size` and its `maximum_size`. A window whose
maximum is `(0, 0)` keeps the size it was asked for.

The screen prints such a window at its maximum, so the canvas answers what the
content needed there: a text wraps at the maximum width, and the height follows
the lines it took.
"""
function _fit_window_size!(w::WindowDocument, canvas::GraphicsCanvas)
    maximum_size = w.maximum_size
    (maximum_size[1] <= 0 && maximum_size[2] <= 0) && return w
    minimum_size = w.minimum_size
    width  = _fit_extent(Int(canvas.w[]), minimum_size[1], maximum_size[1])
    height = _fit_extent(Int(canvas.h[]), minimum_size[2], maximum_size[2])
    # Only a size that changed is written: an equal write would invalidate the
    # cell that the mirrored window shares, on every frame.
    (w.width == width && w.height == height) && return w
    w.width = width
    w.height = height
    w
end

"""
    _place_fitted_window!(backend::SdlBackend, w::WindowDocument) -> w

Keep a window that fits its content on the screen. A window that would cross the
right or the bottom edge of the work area is moved inside it, and one that would
then hold the pointer goes to the side of the pointer instead: a window under the
pointer covers the very thing it is about, and the next move of the pointer
closes it.

A window of a fixed size is left alone, and so is one that asks the backend to
place it (`x` or `y` below zero).
"""
function _place_fitted_window!(backend::SdlBackend, w::WindowDocument)
    maximum_size = w.maximum_size
    (maximum_size[1] <= 0 && maximum_size[2] <= 0) && return w
    (w.x < 0 || w.y < 0) && return w
    area = get_display_size(backend)
    (x, y) = compute_window_place(Int(w.x), Int(w.y), Int(w.width), Int(w.height);
                                  area_width = Int(area[1]),
                                  area_height = Int(area[2]),
                                  pointer = get_pointer_position(backend))
    (w.x == x && w.y == y) && return w
    w.x = x
    w.y = y
    w
end

# How far a window that had to move stays from the pointer.
const _POINTER_GAP = 8

# @positional: the window's box, in the order every one writes it.
"""
    compute_window_place(x, y, width, height; area_width, area_height, pointer) -> (x, y)

Where a window of that size goes: inside the work area, and beside `pointer`
rather than under it. `pointer` is the pointer in screen coordinates, or
`nothing` when nobody says where it is.
"""
function compute_window_place(x::Int, y::Int, width::Int, height::Int;
                              area_width::Int, area_height::Int, pointer)
    x + width  > area_width  && (x = area_width  - width)
    y + height > area_height && (y = area_height - height)
    x = max(x, 0)
    y = max(y, 0)
    if pointer !== nothing && x <= pointer[1] < x + width && y <= pointer[2] < y + height
        left = Int(pointer[1]) - width - _POINTER_GAP
        x = left >= 0 ? left : Int(pointer[1]) + _POINTER_GAP
    end
    (x, y)
end

# One extent, clamped. A bound of 0 or less is no bound.
function _fit_extent(extent::Int, minimum::Int, maximum::Int)
    maximum > 0 && (extent = min(extent, maximum))
    minimum > 0 && (extent = max(extent, minimum))
    max(extent, 1)
end

# Whether the native window is on screen. A window is made hidden and shown once
# it holds its first frame, so this tells the two apart.
_is_native_window_shown(res::SdlWindowResources) =
    (SDL_GetWindowFlags(res.win) & UInt32(SDL_WINDOW_SHOWN)) != 0

# Paint a window the reconciler has just opened, and only then show it, so that
# the first pixels a person sees are the window's own. It is opened hidden, and
# a window shown before it is painted holds an undefined back buffer that the
# compositor draws black.
#
# The paint after the show is what the caller does next: a driver is free to
# drop a present made while the window is hidden, so `first_paint` asks for the
# whole window again instead of the rectangles that changed.
function _show_painted_window!(backend::SdlBackend, res::SdlWindowResources,
                               w::WindowDocument)
    canvas = w.content
    canvas isa GraphicsCanvas && _render_window!(backend, res, canvas)
    SDL_ShowWindow(res.win)
    res.first_paint = true
end

# Apply title / size / position / bg changes from a WindowDocument, and a change
# of the device pixel ratio `ratio`, to its native counterpart. Cached fields on
# SdlWindowResources avoid redundant SDL calls when nothing changed.
function _update_window_geometry!(res::SdlWindowResources, w::WindowDocument,
                                  ratio::Float64)
    if w.title != res.title
        SDL_SetWindowTitle(res.win, w.title)
        res.title = String(w.title)
    end
    if w.width != res.width || w.height != res.height || ratio != res.ratio
        SDL_SetWindowSize(res.win, Int32(max(_to_device(w.width, ratio), 1)),
                                   Int32(max(_to_device(w.height, ratio), 1)))
        res.width = Int(w.width)
        res.height = Int(w.height)
        res.ratio = ratio
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
    # A style change mid-life would need flag-bit toggles that SDL only partly
    # supports, so this records the latest value without applying it.
    res.style = w.style
end

# ════════════════════════════════════════════════════════════════════════
# Readability zoom (Ctrl+=/-/0 uniform, Ctrl+Alt+=/-/0 font-only)
# ════════════════════════════════════════════════════════════════════════
#
# The gesture is recognised editor-globally in the kernel's `read!`; here the SDL
# backend supplies the concrete behaviour. `AdjustZoomOperation` steps the `zoom`
# of the backend's `Display`, so the device pixel ratio changes (everything
# magnifies), and reflows the logical viewport — no re-projection.
# `AdjustFontZoomOperation` writes the `_FONT_ZOOM` cell, which
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
# logical `width`/`height` by `old/new` ratio, so the device size stays the same. The
# OS window therefore does not resize, while the content relayouts to the new
# logical viewport — those cells are the exact range that the printer gives the
# content, so the write reflows reactively (no re-projection), exactly like a
# user resize.
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
    editor.backend isa SdlBackend || return nothing
    display = editor.backend.display
    old = get_device_pixel_ratio(display)
    display.zoom = step_zoom(display.zoom, op.delta)
    _reflow_for_scale!(editor, old / get_device_pixel_ratio(display))
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
    decode_sdl_image(filename::AbstractString) -> (data::Vector{UInt8}, width::Int32, height::Int32)

Load an image file (PNG, JPEG, BMP, etc.) via SDL2_image's `IMG_Load`,
convert to RGBA32 row-major pixel format, and return the raw bytes plus
the image dimensions. The returned `data` is suitable for passing to
`GraphicsImage` / `_render_image!`.

Throws on failure (file not found, unsupported format, etc.).
"""
function decode_sdl_image(filename::AbstractString)
    SDL_Init(SDL_INIT_VIDEO)
    surface = IMG_Load(filename)
    surface == C_NULL && error("decode_sdl_image: failed to load '$filename': $(unsafe_string(SDL_GetError()))")

    # Convert to RGBA32 (R=byte0, G=byte1, B=byte2, A=byte3 on little-endian)
    rgba_surface = SDL_ConvertSurfaceFormat(surface, UInt32(SDL_PIXELFORMAT_RGBA32), UInt32(0))
    SDL_FreeSurface(surface)
    rgba_surface == C_NULL && error("decode_sdl_image: format conversion failed: $(unsafe_string(SDL_GetError()))")

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
    result = decode_sdl_image(fn)
    img.raw = result
    img
end

# Image decode via the generic seam.
BackendModule.decode_image(filename::AbstractString) = decode_sdl_image(filename)

# Display size via the generic seam (delegates to the SDL-specific query).
BackendModule.get_display_size(::SdlBackend; display::Integer=0) =
    get_sdl_display_size(; display=display)

# Fill the first `Display` in `devices` with the usable size and the scale of the
# real display, and draw with it from now on: its `zoom` then steps with
# Ctrl+= and Ctrl+-. The scale is the one the probe finds, so the zoom of an
# editor does not reach the `Display` of another. Mouse/Keyboard are left at their
# defaults — SDL2 cannot reliably report button count or keyboard layout.
function BackendModule.configure_devices!(backend::SdlBackend, devices)
    index = findfirst(device -> device isa Display, devices)
    index === nothing && return nothing
    display = devices[index]::Display
    display.width, display.height = get_sdl_display_size()
    display.scale = _PROBED_DISPLAY_SCALE[]
    backend.display = display
    return nothing
end
