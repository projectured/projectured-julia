# Fragment of `SdlModule` — `SdlBackend`: a native window for each window
# document, drawn with the renderer of SDL and SDL_ttf, the keyboard and the
# mouse, and the offscreen renderer that writes images and the frames of a
# video.

# Xlib reads its locale data from the folder that its build named, and that
# folder exists only on the machine that built `Xorg_libX11_jll`. Without the
# data `XSupportsLocale` is false, and SDL then gives a window no title: X11
# shows neither `WM_NAME` nor `_NET_WM_NAME`. The artifact of the JLL holds the
# data, so SDL reads it there. A value that the user set wins. A system with no
# build of the JLL, such as macOS, has no X11, and its JLL assigns no
# `artifact_dir`, so there is nothing to set.
function _set_x11_locale_directory!()
    haskey(ENV, "XLOCALEDIR") && return nothing
    Xorg_libX11_jll.is_available() || return nothing
    directory = joinpath(Xorg_libX11_jll.artifact_dir, "share", "X11", "locale")
    isdir(directory) && (ENV["XLOCALEDIR"] = directory)
    nothing
end

# Each process probes its own machine, and Xlib finds its locale data. The
# methods of AppKit that the backend replaces belong to one process too, so a
# package image keeps none of them.
function __init__()
    _reset_machine_probes!()
    empty!(_REPLACED_KEY_WINDOW_METHODS)
    _set_x11_locale_directory!()
    nothing
end

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

# Start the video subsystem of SDL when it does not run, and answer whether it
# runs. SDL counts the starts of a subsystem in one byte. After 256 starts the
# count is zero again, and the next start quits video first, which destroys
# every window and sends no event. So code that can run more than once in the
# life of a backend starts video here, never with a bare `SDL_Init`.
_start_sdl_video!() = SDL_WasInit(SDL_INIT_VIDEO) != 0 || SDL_Init(SDL_INIT_VIDEO) == 0

"""
    get_sdl_display_size(; display::Integer=0) -> (width, height)

Return the usable size of the given display (default 0) in **logical** pixels —
the coordinate space window sizes are authored in. "Usable" means with
OS-reserved areas like the taskbar / menu bar subtracted; the right thing for
picking a default window size. SDL gives the bounds in window units, which are
divided by the window unit ratio of no window, and `xrandr` gives device pixels,
which are divided by the density that the probe of the display finds. So a window
sized to it fills exactly one monitor once the backend scales it back. Falls back
to `(1280, 720)`
if SDL cannot answer (no display, headless run, etc.). The video subsystem and
the display density are initialized lazily; safe to call before `initialize_backend!`.

On X11 SDL sometimes folds a multi-monitor screen into a single "display"
whose bounds span every monitor (e.g. 7290×4032 across two), which would
size the default window to the whole desktop. When SDL reports one display
but xrandr sees several, the primary monitor's size from xrandr is used
instead so the default fills one monitor, not the span.
"""
function get_sdl_display_size(; display::Integer=0)
    _start_sdl_video!() || return (1280, 720)
    # Ensure the density is known before converting device → logical, since this
    # may run before `initialize_backend!` (early detection is window-free: env
    # + Xft.dpi). The probe latches itself, so repeated calls cost nothing.
    _detect_display_density!()

    # Detect the SDL-collapses-multiple-monitors case and prefer the real
    # primary-monitor size. Only when SDL reports a single display (so we do
    # not override a setup where SDL already enumerates monitors correctly).
    if display == 0 && SDL_GetNumVideoDisplays() <= 1
        mon = _x11_primary_monitor_size(; require_multi=true)
        mon === nothing || return (_to_logical(mon[1], _PROBED_DISPLAY_DENSITY[]),
                                   _to_logical(mon[2], _PROBED_DISPLAY_DENSITY[]))
    end

    rect = Ref(SDL_Rect(Int32(0), Int32(0), Int32(0), Int32(0)))
    rc = SDL_GetDisplayUsableBounds(Int32(display), rect)
    if rc != 0 || rect[].w <= 0 || rect[].h <= 0
        return (1280, 720)
    end
    unit_ratio = _get_window_unit_ratio(_PROBED_DISPLAY_DENSITY[])
    (_to_logical(Int(rect[].w), unit_ratio), _to_logical(Int(rect[].h), unit_ratio))
end

# ════════════════════════════════════════════════════════════════════════
# Backend
# ════════════════════════════════════════════════════════════════════════

# What the dirty walk remembers of each graphic from the frame that painted it,
# keyed by its placement (`_make_placement_key`): the place of every graphic (the
# absolute content origin of a canvas, the origin of the container of any other),
# the box, the content and the transform of a viewport, the keys of the elements
# that a canvas drew, and the signature of each leaf (`_compute_leaf_signature`).
# The walk compares this frame with it by value. `baseline` is the count of
# records after the last full paint; it bounds how many records of graphics that
# are gone can collect.
#
# `guards` holds the guard cell of each painted canvas (`_read_guard!`), and
# `guard_places` the content origin and the clip edges of the canvas, the place
# that its guard reads for; the key of a placement names the canvas itself. `visits` is the count of the elements whose cells the last
# walk tested (`_collect_dirty_elem!`), which a test and a measurement read.
mutable struct _PaintedGeometry
    origins::Dict{UInt,NTuple{2,Int}}
    viewports::Dict{UInt,Tuple{NTuple{4,Int},UInt,AffineTransform}}
    members::Dict{UInt,Vector{UInt}}
    signatures::Dict{UInt,UInt}
    baseline::Int
    guards::Dict{UInt,Any}
    guard_places::Dict{UInt,Any}
    visits::Int        # the elements that the last walk tested
    recordings::Int    # the graphics that the last walk recorded from their cells
    new_guards::Int    # the guards that the last walk made
end
_PaintedGeometry() = _PaintedGeometry(Dict{UInt,NTuple{2,Int}}(),
                                      Dict{UInt,Tuple{NTuple{4,Int},UInt,AffineTransform}}(),
                                      Dict{UInt,Vector{UInt}}(), Dict{UInt,UInt}(), 0,
                                      Dict{UInt,Any}(), Dict{UInt,Any}(), 0, 0, 0)

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
    width::Int           # last applied size, in logical pixels
    height::Int
    x::Int               # last applied position, in logical pixels (-1 = not yet positioned)
    y::Int
    style::Symbol        # last applied style
    bg::NTuple{4,UInt8}  # last applied background
    ss::Int              # supersample factor for anti-aliasing (1 = off)
    ratio::Float64       # last applied device pixel ratio of the backend's Display
    pixels_per_window_unit::Float64  # device pixels in one SDL window unit: 1 on X11
                                     # and Windows, 2 on a Retina screen of macOS
    target::Ptr{SDL_Texture}  # offscreen SSAA render target (C_NULL until created)
    target_w::Int        # current target texture size (device px)
    target_h::Int
    # Dirty-rectangle partial repaint state.
    first_paint::Bool    # force a full repaint on the first frame / after target (re)creation
    dirty_bounds::Dict{UInt,NTuple{4,Int}}  # last-rendered absolute logical bounds, keyed by
                                            # the placement of each graphic (for old∪new)
    painted::_PaintedGeometry  # the place and the geometry each graphic was painted with
    # Recent frames' logical dirty rects (x0,y0,x1,y1), one set for each frame,
    # most-recent first. The target→window copy each frame refreshes the rects of
    # the last `buffer age` frames: the back-buffer we draw into was last presented `age` frames ago
    # (queried via EGL/GLX buffer age), so everything that changed since then
    # must be re-copied or the older edits ghost on the alternate buffer(s).
    damage_history::Vector{Vector{NTuple{4,Int}}}
    # A target texture that a move copies the pixels of a box through, because SDL
    # can not copy a texture into itself (C_NULL until a move needs it).
    scratch::Ptr{SDL_Texture}
end

"""
    SdlBackend()

SDL2 + SDL_ttf backend. Loaded TTF fonts are cached in the module-level
[`_font_cache`](@ref), shared across windows, measurement, and offscreen
image rendering.

The backend emits only raw input events; recognising composite gestures
(e.g. synthesising a `MouseClick` click from a `MouseDown`/`MouseUp` pair) is
the job of the gesture tracking projection, not the backend's.

`windows` is the live registry of native SDL windows, keyed by the
`WindowDocument.id` they mirror. `window_ids` is the reverse map from
SDL `windowID` to `WindowDocument.id`, used when translating raw SDL
events into `WindowInput`s. Both are reconciled by
`write_to_devices!(::SdlBackend, devices, ::ScreenDocument)`.

`pending_inputs` and `pending_motion` are the buffers `take_from_devices!` needs
to collapse a run of pointer motion into its newest sample and to answer the
`KeyPress` of Return and Tab after their `KeyDown`, and `last_hover_motion` is the
time of the rate limit of idle motion.
They live on the backend rather than at module level, so two backends in one
process never hand each other an event or a delay. `partial_render`,
`debug_dirty`, `debug_dirty_hold` and `supersample` are read for each window of
this backend alone; the `RenderSettings` of an editor reach them through
`apply_settings!`.

`modifiers` holds the modifier keys of the last key event that the poll read. A
mouse event and a text event take their modifiers from it, so they hold the
modifiers at their place in the queue, not at the time of the poll.
`initialize_backend!` seeds it from `SDL_GetModState`.

`display_updates` holds a `DisplayUpdate` for each window that showed a frame
which differs from the one before, until `take_from_devices!` answers it. A window
that shows two changed frames before a read has one update, with the later time.

`display` is the `Display` that the backend draws on. Its device pixel ratio
sizes the windows, rasterizes the text and converts the input coordinates. A new
backend has a `Display()` of its own, and `initialize_backend!` gives it the
density that the probe finds. `configure_devices!` replaces it with the `Display`
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
    #   debug_dirty_hold — the seconds that an outline stays on the frames after it
    #   supersample    — the supersample factor of each window (1 = off)
    partial_render::Bool
    debug_dirty::Bool
    debug_dirty_hold::Float64
    supersample::Int
    # The repaints of the last `debug_dirty_hold` seconds, with the time of each,
    # by the id of the window: the outline of a frame is the union of them.
    recent_repaints::Dict{Symbol, Vector{Tuple{Float64,Vector{NTuple{4,Int}}}}}
    # Input coalescing state (see `take_from_devices!`):
    #   pending_inputs — the events owed to the next calls, in order: the event that
    #                    arrived behind a held motion, and the `KeyPress` of a
    #                    Return or a Tab after its `KeyDown`
    #   pending_motion — the newest motion sample not yet delivered
    #   last_hover_motion — when the last idle motion was delivered (`time()`),
    #                       for the rate limit of idle motion
    pending_inputs::Vector{WindowInput}
    pending_motion::Union{WindowInput, Nothing}
    last_hover_motion::Float64
    # The modifier keys of the last key event in the order of the queue.
    modifiers::ModifierKeys
    # The SDL user-event type `wake_backend!` pushes to end a wait in
    # progress. Zero until `initialize_backend!` registers one; a wake on an
    # uninitialized backend is a no-op.
    wake_event_type::UInt32
    # The display the windows are drawn on (see the docstring).
    display::Display
    # The usable area of each display, `(x, y, width, height)` in logical pixels at
    # the zoom 1, the main display first, read with the work area of `display`;
    # empty with one display, where that work area serves.
    display_areas::Vector{NTuple{4,Int}}
    # The `DisplayUpdate` of each window that showed a changed frame since the
    # last read, at most one for each window (see the docstring).
    display_updates::Vector{WindowInput}
    # The zoom of the display at the last drawn frame, 0 before the first one. A
    # frame at another zoom keeps the device size of each window.
    drawn_zoom::Float64
    # The canvas that each window drew last, by the id of the window, where the
    # backend finds the shape of the pointer (see `find_pointer_shape`).
    drawn_canvases::Dict{Symbol, GraphicsCanvas}
    # The shape of the pointer that the backend set last, `:default` before the
    # first one, and the cursor that it made for each shape, once.
    pointer_shape::Symbol
    cursors::Dict{Symbol, Ptr{SDL_Cursor}}
    # The colour settings of the system that the backend found last, the change of
    # them that waits for `take_from_devices!`, the task of a query in progress, and
    # whether a focus asked for one more query while it ran (see
    # `find_system_colors`).
    system_colors::Union{Nothing, SystemColors}
    system_colors_change::Union{Nothing, WindowInput}
    system_colors_task::Union{Nothing, Task}
    is_system_colors_query_pending::Bool
end

# The keywords are the defaults of the `RenderSettings` of an editor. An editor
# with the `settings` wrapper applies its settings to the backend when it starts,
# and the environment variables reach the backend through those settings.
SdlBackend(; partial_render::Bool = true, debug_dirty::Bool = false,
             debug_dirty_hold::Real = 0.0, supersample::Integer = 2) =
    SdlBackend(Dict{Symbol, SdlWindowResources}(),
               Dict{UInt32, Symbol}(),
               partial_render, debug_dirty, Float64(debug_dirty_hold), Int(supersample),
               Dict{Symbol, Vector{Tuple{Float64,Vector{NTuple{4,Int}}}}}(),
               WindowInput[], nothing, 0.0, ModifierKeys(), UInt32(0), Display(), NTuple{4,Int}[],
               WindowInput[], 0.0,
               Dict{Symbol, GraphicsCanvas}(), :default, Dict{Symbol, Ptr{SDL_Cursor}}(),
               nothing, nothing, nothing, false)

# SDL draws a screen of windows, and `--backend=sdl` names it.
get_backend_name(::Type{SdlBackend}) = :sdl
get_backend_output(::Type{SdlBackend}) = :windows

# Module-level TTF font cache, keyed by (filename, scaled_size).
# Shared by window rendering, offscreen image rendering, and text measurement.
# Populated lazily by `_get_font`; freed by `quit_backend!`.
const _font_cache = Dict{Tuple{String,Int}, Ptr{TTF_Font}}()

# Module-level text-texture cache. Rendering a `GraphicsText` rasterizes each
# glyph of the string, composes the glyphs into one surface, uploads it as a GPU
# texture and draws it. When scrolling a static document the spans never change,
# so the rasterize/upload churn is the dominant render cost. We cache the
# uploaded texture (plus its device size, so `SDL_QueryTexture` is skipped too)
# keyed by renderer + text + font + colour and reuse it across frames. The font
# is in the key at its logical size, where the layout places the glyphs, and at
# its device size, where SDL rasterizes them. Textures are renderer-specific, so
# entries are evicted when their renderer is destroyed (`_close_native_window!`,
# `close_offscreen_renderer`) and all are freed by `quit_backend!`.
struct _TextTextureKey
    renderer::Ptr{SDL_Renderer}
    text::String
    filename::String
    logical_size::Int
    size::Int
    color::NTuple{4,UInt8}
end

struct _TextTexture
    texture::Ptr{SDL_Texture}
    dw::Int          # device px width  (the logical size follows at each draw, from the ratio)
    dh::Int          # device px height
    left::Int        # device px from the left of the texture to the pen origin of the text
    ascent::Int      # device px from the top of the texture down to its baseline
    box_ascent::Int  # logical px from the `y` of the text down to its baseline (`compute_text_extent`)
end

const _text_texture_cache = Dict{_TextTextureKey, _TextTexture}()

# Soft cap: a single document's distinct spans are bounded, but rendering many
# different documents over a session would grow this without limit. When the cap
# is hit, drop everything and start over — far simpler than an LRU and rare.
const _TEXT_TEXTURE_CACHE_CAP = 16384

# ── Dirty-rectangle partial repaint controls ─────────────────────────────
#
# Nothing needs to be repainted that has not been *invalidated* in the reactive
# graph, so we walk the canvas tree, find the smallest rectangle covering every
# invalidated graphic, clip to it and repaint only that region into a retained
# target.
#
# `partial_render` of the backend is the master switch, on by default (false
# forces the full-frame repaint). `debug_dirty` of the backend, when on, outlines the
# repainted region in red so it is visible which part of the screen was painted.
# `_render_window!` reads both from the backend of the window, and the
# `RenderSettings` of an editor set them through `apply_settings!`.

# How many recent frames' damage rects to retain for the partial target→window
# copy. The copy refreshes the rects of the last `buffer age` of them; deeper
# swap chains than this fall back to a full copy. 8 is far beyond any real swap
# chain (double/triple buffering ⇒ age 2/3).
const _DAMAGE_HISTORY_CAP = 8

# The render settings of an editor reach its backend here. A change of the mode
# or of the outline repaints each window in full at the next frame, so no
# outline of a frame before stays on the back buffer. A new supersample factor
# reaches each open window, and `_ensure_ss_target!` makes its target again.
function apply_settings!(backend::SdlBackend, settings::RenderSettings)
    changed = backend.partial_render != settings.partial_render ||
              backend.debug_dirty != settings.debug_dirty
    backend.partial_render = settings.partial_render
    backend.debug_dirty = settings.debug_dirty
    backend.debug_dirty_hold = settings.debug_dirty_hold
    backend.supersample = settings.supersample
    for resources in values(backend.windows)
        changed && (resources.first_paint = true)
        resources.ss = settings.supersample
    end
    nothing
end

function read_settings!(settings::RenderSettings, backend::SdlBackend)
    settings.partial_render = backend.partial_render
    settings.debug_dirty = backend.debug_dirty
    settings.debug_dirty_hold = backend.debug_dirty_hold
    settings.supersample = backend.supersample
    nothing
end

# The rects to outline in a frame of `res`: those of the frame, and with a hold,
# those of each repaint of the window in the last `debug_dirty_hold` seconds.
function _get_held_outline!(backend::SdlBackend, res::SdlWindowResources, rects)
    backend.debug_dirty_hold > 0 || return rects
    now = time()
    recent = get!(() -> Tuple{Float64,Vector{NTuple{4,Int}}}[], backend.recent_repaints,
                  res.id)
    push!(recent, (now, collect(rects)))
    filter!(entry -> now - entry[1] <= backend.debug_dirty_hold, recent)
    unique!(reduce(vcat, (entry[2] for entry in recent); init = NTuple{4,Int}[]))
end

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
    ModifierKeys(; ctrl, shift, alt, meta)
end

# Convenience overload: extract modifiers from the current SDL state.
_current_modifiers() = sdl_modifiers(UInt16(SDL_GetModState() & 0xFFFF))

# The system opens an address in its program for it, such as the browser.
open_url!(::SdlBackend, address::AbstractString) = SDL_OpenURL(address) == 0

# ════════════════════════════════════════════════════════════════════════
# Keyboard
# ════════════════════════════════════════════════════════════════════════

"""
    sdl_keysym_to_symbol(keysym::Int32) -> Symbol

Map an SDL keysym integer to the backend-agnostic key symbol vocabulary.
Each letter key has the name of its lower-case letter, `:a` to `:z`.
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
    keysym == Int32(1073741912) && return :return   # keypad Enter
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
    keysym == Int32(44)         && return :comma    # ',' — the icon scale, Ctrl+Alt+,
    keysym == Int32(91)         && return :left_bracket   # '[' — the spacing scale, Ctrl+Alt+[
    keysym == Int32(93)         && return :right_bracket  # ']' — the spacing scale, Ctrl+Alt+]
    # Letters: the keysym of a letter key is the code of its lower-case letter.
    Int32(97) <= keysym <= Int32(122) && return Symbol(Char(keysym))
    # Punctuation chords: the punctuation keys that a binding names need distinct
    # symbols rather than the `:char` fallback so `@gesture_case` can tell them
    # apart under Ctrl.
    keysym == Int32(92)         && return :backslash # Ctrl+\\ — split a pane group
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
    sdl_to_keydown(keysym, mod, is_repeat; time) -> KeyDown

Build a `KeyDown` from SDL key-down event fields, at the time `time`.
"""
function sdl_to_keydown(keysym::Int32, mod::UInt16, is_repeat::Bool; time::Real)::KeyDown
    KeyDown(sdl_keysym_to_symbol(keysym), sdl_modifiers(mod); repeat = is_repeat, time)
end

"""
    sdl_to_keyup(keysym, mod; time) -> KeyUp

Build a `KeyUp` from SDL key-up event fields, at the time `time`.
"""
function sdl_to_keyup(keysym::Int32, mod::UInt16; time::Real)::KeyUp
    KeyUp(sdl_keysym_to_symbol(keysym), sdl_modifiers(mod); time)
end

"""
    sdl_to_keypress(evt; modifiers, time) -> Union{KeyPress, Nothing}

Build a `KeyPress` with `modifiers` at the time `time` from an `SDL_TEXTINPUT`
event. Returns `nothing` if the event carries no printable text (e.g. empty or
invalid UTF-8).
`SDL_TEXTINPUT` provides a null-terminated UTF-8 string in `evt.text.text`
(a `NTuple{32,UInt8}`).
"""
function sdl_to_keypress(evt; modifiers::ModifierKeys,
                         time::Real)::Union{KeyPress,Nothing}
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
    KeyPress(ch, text, modifiers; time)
end

# The time of an SDL event on the clock of `time()`. SDL stamps each event with
# the milliseconds since `SDL_Init`, so the ticks now minus the stamp is the age
# of the event. The subtraction wraps as the ticks do.
function _get_sdl_event_time(timestamp::UInt32)
    age = SDL_GetTicks() - timestamp
    time() - Int(age) / 1000
end

# ════════════════════════════════════════════════════════════════════════
# Mouse helpers
# ════════════════════════════════════════════════════════════════════════

# The name of an SDL button: 1 is the left, 2 the middle and 3 the right button,
# and 4 and 5 (`X1` and `X2`) the side buttons, back and forward. Another number
# has no name in the event layer, and the answer is `nothing`.
_sdl_button_sym(b::UInt8) =
    b == 0x01 ? :left : b == 0x02 ? :middle : b == 0x03 ? :right :
    b == 0x04 ? :back : b == 0x05 ? :forward : nothing

# The buttons that an SDL button mask holds: the `state` of a motion event.
_get_held_mouse_buttons(bstate::UInt32) =
    MouseButtons(left = (bstate & UInt32(0x01)) != UInt32(0),
                 middle = (bstate & UInt32(0x02)) != UInt32(0),
                 right = (bstate & UInt32(0x04)) != UInt32(0),
                 back = (bstate & UInt32(0x08)) != UInt32(0),
                 forward = (bstate & UInt32(0x10)) != UInt32(0))

# ════════════════════════════════════════════════════════════════════════
# Native window lifecycle (internal helpers; driven by the reconciler in
# `write_to_devices!(::SdlBackend, devices, ::ScreenDocument)`).
# ════════════════════════════════════════════════════════════════════════

# The flags a window of each style is created with. **Named, not numbered.** The
# tooltip and the floating style both carried `0x00000400` under a comment that
# called it `SDL_WINDOW_ALWAYS_ON_TOP`. It is `SDL_WINDOW_MOUSE_FOCUS`, which SDL
# REPORTS about a window and never accepts when one is made, so neither style was
# ever on top and neither flag set said what its comment said.
const _WINDOW_FLAGS_DEFAULT  = SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI
# A tooltip belongs to the window under it: it stays above, it is not a task of
# its own, and `SDL_WINDOW_TOOLTIP` is what tells the window manager of X11 to
# treat it as one and leave the keyboard where it is. SDL on Cocoa reads none of
# these flags, and `_refuse_key_focus!` keeps the keyboard there.
const _WINDOW_FLAGS_TOOLTIP  = SDL_WINDOW_SHOWN | SDL_WINDOW_BORDERLESS |
                               SDL_WINDOW_ALWAYS_ON_TOP | SDL_WINDOW_SKIP_TASKBAR |
                               SDL_WINDOW_TOOLTIP | SDL_WINDOW_ALLOW_HIGHDPI
const _WINDOW_FLAGS_FLOATING = SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE |
                               SDL_WINDOW_ALWAYS_ON_TOP | SDL_WINDOW_ALLOW_HIGHDPI
# A popup, a menu or a dropdown list, never takes the focus. With
# `SDL_WINDOW_POPUP_MENU` the window manager of X11 does not manage the window,
# so it can not give the window the focus and take it back, as it does with a
# managed window the moment it opens. SDL on Cocoa reads no such flag, and
# `_refuse_key_focus!` keeps the focus in the window under the popup.
const _WINDOW_FLAGS_POPUP    = SDL_WINDOW_SHOWN | SDL_WINDOW_BORDERLESS |
                               SDL_WINDOW_ALWAYS_ON_TOP | SDL_WINDOW_SKIP_TASKBAR |
                               SDL_WINDOW_POPUP_MENU | SDL_WINDOW_ALLOW_HIGHDPI

function _window_flags(style::Symbol)
    style === :tooltip  && return _WINDOW_FLAGS_TOOLTIP
    style === :popup    && return _WINDOW_FLAGS_POPUP
    style === :floating && return _WINDOW_FLAGS_FLOATING
    return _WINDOW_FLAGS_DEFAULT
end

# The place that SDL gets for `w`, in window units at `unit_ratio`. SDL centers a
# window whose place the backend chooses; every other place, negative too, is a
# place on the screen.
function _get_native_window_place(w::WindowDocument, unit_ratio::Float64)
    is_automatic_window_place(w) && return (SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED)
    (Int32(_to_device(w.x, unit_ratio)), Int32(_to_device(w.y, unit_ratio)))
end

# Whether a window of `style` can take the key focus. A tooltip and a popup take
# their keys through the window under them: F2 of a tooltip, and the arrows, Return
# and Escape of a menu or a dropdown. A popup still takes the press that chooses.
_can_take_key_focus(style::Symbol) = style !== :tooltip && style !== :popup

# The same flags, with the window held back until it holds a frame. A window
# that is shown before it is painted holds an undefined back buffer, and the
# compositor draws that black, so a tooltip flashes black and fills in after.
_hidden_window_flags(style::Symbol) =
    (UInt32(_window_flags(style)) & ~UInt32(SDL_WINDOW_SHOWN)) | UInt32(SDL_WINDOW_HIDDEN)

# Open one native SDL window for a WindowDocument and return the resource record.
# The window is drawn at the device pixel ratio of the `Display` of `backend`.
function _open_native_window!(backend::SdlBackend, w::WindowDocument; hidden::Bool = false)
    ratio = get_device_pixel_ratio(backend.display)
    # WindowDocument places and sizes are logical; SDL takes window units. The
    # window does not exist yet, so the ratio is that of the last window.
    unit_ratio = _get_window_unit_ratio(ratio)
    work_area_unit_ratio = _get_window_unit_ratio(_PROBED_DISPLAY_DENSITY[])
    px, py = _get_native_window_place(w, unit_ratio)
    flags = hidden ? _hidden_window_flags(w.style) : UInt32(_window_flags(w.style))
    win = SDL_CreateWindow(w.title, px, py,
        Int32(max(_to_device(w.width, unit_ratio), 1)),
        Int32(max(_to_device(w.height, unit_ratio), 1)), flags)
    @assert win != C_NULL "SDL window creation failed: $(unsafe_string(SDL_GetError()))"
    _can_take_key_focus(w.style) || _refuse_key_focus!(win)

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

    if _update_display_density!(win, renderer)
        backend.display.density = _PROBED_DISPLAY_DENSITY[]
        ratio = get_device_pixel_ratio(backend.display)
    end
    # The window now knows its own units. It was made in the units of the last
    # window, so a window with other units takes its size and place again in its
    # own: a window on a screen with another number of pixels per point, or a
    # window made after the density was known.
    pixels_per_window_unit = _measure_pixels_per_window_unit(win, renderer)
    _LAST_PIXELS_PER_WINDOW_UNIT[] = pixels_per_window_unit
    own_unit_ratio = ratio / pixels_per_window_unit
    if own_unit_ratio != unit_ratio
        SDL_SetWindowSize(win, Int32(max(_to_device(w.width, own_unit_ratio), 1)),
                               Int32(max(_to_device(w.height, own_unit_ratio), 1)))
        SDL_SetWindowPosition(win, _get_native_window_place(w, own_unit_ratio)...)
    end
    # The work area of the display is in logical pixels through the window unit
    # ratio of no window, which this window can change.
    if _get_window_unit_ratio(_PROBED_DISPLAY_DENSITY[]) != work_area_unit_ratio
        _read_work_areas!(backend)
    end

    sdl_id = UInt32(SDL_GetWindowID(win))
    SdlWindowResources(win, renderer, w.id, sdl_id, w.title,
                       Int(w.width), Int(w.height), Int(w.x), Int(w.y),
                       w.style, w.bg, backend.supersample, ratio, pixels_per_window_unit,
                       C_NULL, 0, 0, true, Dict{UInt,NTuple{4,Int}}(), _PaintedGeometry(),
                       Vector{NTuple{4,Int}}[], C_NULL)
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

# ── Logical ↔ device pixel conversion ──────────────────────────────────
#
# Layout, documents and events are all in *logical* pixels; the window's
# backbuffer is in *device* pixels. `ratio` is the number of device pixels in one
# logical pixel. `_to_device` and `_to_logical` convert with `ratio` for the SSAA
# targets, and with the window unit ratio for the native windows and their input.
#
# SDL counts the size and the place of a window, a resize, the mouse and the
# bounds of a display in *window units*. On X11 and Windows a window unit is a
# device pixel. On macOS, and with the Wayland driver, it is a point, and a Retina
# screen has two device pixels in each point. So a window value converts with the
# window unit ratio, `ratio` over the pixels per window unit, which
# `_get_window_unit_ratio` gives: on a Retina screen at zoom 1 that is 2 / 2 = 1.
_to_device(px, ratio::Float64) = round(Int, px * ratio)
_to_logical(px, ratio::Float64) = round(Int, px / ratio)

# The pixels per window unit of the last window that opened, and 1 before any
# window opened. A conversion with no window uses it: the bounds of a display,
# the global pointer, the size of a new window and the size of a cursor. On macOS
# the density is not known before the first window either, so the ratio there is
# 1 / 1 until a window opens.
const _LAST_PIXELS_PER_WINDOW_UNIT = Ref(1.0)

# The device pixels in one window unit of `win`: the width of the output of its
# renderer over the width of the window, and 1 when SDL gives no width.
function _measure_pixels_per_window_unit(win::Ptr{SDL_Window}, renderer::Ptr{SDL_Renderer})
    output_width, output_height = Ref{Cint}(0), Ref{Cint}(0)
    window_width, window_height = Ref{Cint}(0), Ref{Cint}(0)
    SDL_GetRendererOutputSize(renderer, output_width, output_height)
    SDL_GetWindowSize(win, window_width, window_height)
    (output_width[] > 0 && window_width[] > 0) || return 1.0
    Float64(output_width[]) / Float64(window_width[])
end

# The number of SDL window units in one logical pixel: of the window `res`, of the
# window of `id` in `backend`, or of no window, at the device pixel ratio `ratio`.
# An id that names no window of the backend gets the probed value.
_get_window_unit_ratio(res::SdlWindowResources, ratio::Float64) = ratio / res.pixels_per_window_unit
_get_window_unit_ratio(ratio::Float64) = ratio / _LAST_PIXELS_PER_WINDOW_UNIT[]
function _get_window_unit_ratio(backend::SdlBackend, id::Symbol)
    ratio = get_device_pixel_ratio(backend.display)
    res = get(backend.windows, id, nothing)
    res === nothing ? _get_window_unit_ratio(ratio) : _get_window_unit_ratio(res, ratio)
end

# Idle (no-button) mouse motion is forwarded for hover features (e.g. the
# reference inspector) but rate-limited so a probe does not run on every pixel.
# Button-held motion (drag) is never throttled. Each backend keeps the time of
# its last idle motion in `last_hover_motion`.
const _HOVER_MOTION_INTERVAL = 0.03   # seconds (~33 Hz)

"""
    get_pointer_position(::SdlBackend) -> (x, y)

Current global mouse position in the logical pixels of the screen, the space of
the `x` and the `y` of a `WindowDocument`, so the result can place a window
directly.
"""
function BackendModule.get_pointer_position(backend::SdlBackend)
    x_ref, y_ref = Ref{Cint}(0), Ref{Cint}(0)
    SDL_GetGlobalMouseState(x_ref, y_ref)
    unit_ratio = _get_window_unit_ratio(get_device_pixel_ratio(backend.display))
    (_to_logical(Int(x_ref[]), unit_ratio), _to_logical(Int(y_ref[]), unit_ratio))
end

# Find the density of the display: the number of device pixels in one logical
# pixel of the hardware. The density is a fact of the machine, not of an editor,
# so the probe runs once in a process and keeps its result in
# `_PROBED_DISPLAY_DENSITY`. `configure_devices!` copies it into the `Display` of
# each editor.
#
# Two-phase detection:
#
#   _detect_display_density!() — called from initialize_backend! and from
#   get_sdl_display_size, before any window exists:
#     1. PROJECTURED_DISPLAY_DENSITY env var — explicit override, always respected.
#     2. Xft.dpi from X resources — reliable on X11/XWayland (GNOME writes
#        Xft.dpi = 96 × density, e.g. 192 for 200%).
#
#   _update_display_density!(win, renderer) — called when a window opens, only if
#   the window-free phase found nothing:
#     3. SDL renderer-output / window-size ratio — macOS Retina, native Wayland.
#     4. SDL_GetDisplayDPI / 96 — Windows fallback.
#
# Falls back to 1.0 (no scaling) if nothing fires.
#
# Both phases are latched, because the density value alone cannot say whether a
# probe already ran: a 1× display detects as exactly 1.0, which is also the
# default. Without the latches every caller re-runs `xrdb`, and phase 4
# overwrites a correct 1.0 with SDL's slightly-off DPI ratio (e.g. 96.04 / 96).
#
#   _DISPLAY_DENSITY_PROBED   — the window-free probe ran; do not spawn xrdb again.
#   _DISPLAY_DENSITY_DETECTED — a real density was found; no later phase may change it.
const _DISPLAY_DENSITY_PROBED   = Ref(false)
const _DISPLAY_DENSITY_DETECTED = Ref(false)
const _PROBED_DISPLAY_DENSITY   = Ref(1.0)

# Forget what the probes of the machine found: the density of the display, the
# pixels per window unit, and whether EGL and GLX answer. A precompile workload
# runs the probes on the machine that builds the package image, and the image
# keeps the values. So `__init__` calls this, and each process probes its own
# machine and reads its own `PROJECTURED_DISPLAY_DENSITY`.
function _reset_machine_probes!()
    _DISPLAY_DENSITY_PROBED[] = false
    _DISPLAY_DENSITY_DETECTED[] = false
    _PROBED_DISPLAY_DENSITY[] = 1.0
    _LAST_PIXELS_PER_WINDOW_UNIT[] = 1.0
    _EGL_AVAILABLE[] = nothing
    _GLX_AVAILABLE[] = nothing
    nothing
end

function _detect_display_density!()
    _DISPLAY_DENSITY_PROBED[] && return _DISPLAY_DENSITY_DETECTED[]
    _DISPLAY_DENSITY_PROBED[] = true

    # 1. Explicit override.
    env_val = get(ENV, "PROJECTURED_DISPLAY_DENSITY", "")
    if !isempty(env_val)
        density = tryparse(Float64, env_val)
        if density !== nothing && density > 0
            _PROBED_DISPLAY_DENSITY[] = density
            _DISPLAY_DENSITY_DETECTED[] = true
            @debug "Display density: $(_PROBED_DISPLAY_DENSITY[]) (PROJECTURED_DISPLAY_DENSITY)"
            return true
        end
    end

    # 2. Xft.dpi from X resources — GNOME sets this to 96 × density on X11 and
    #    XWayland.  Run xrdb only when a DISPLAY is available and xrdb exists.
    if haskey(ENV, "DISPLAY")
        try
            out = readchomp(pipeline(`xrdb -query`, stderr=devnull))
            m = match(r"(?:^|\n)Xft\.dpi:\s*(\d+(?:\.\d+)?)"i, out)
            if m !== nothing
                xft_dpi = parse(Float64, m.captures[1])
                if xft_dpi > 0
                    _PROBED_DISPLAY_DENSITY[] = xft_dpi / 96.0
                    _DISPLAY_DENSITY_DETECTED[] = true
                    @debug "Display density: $(_PROBED_DISPLAY_DENSITY[]) (Xft.dpi = $xft_dpi)"
                    return true
                end
            end
        catch
            # xrdb not installed or failed — fall through.
        end
    end

    return false
end

# Answers `true` when this call found the density.
function _update_display_density!(win::Ptr{SDL_Window}, renderer::Ptr{SDL_Renderer})
    # Skip if a window-free phase already found the density.
    _DISPLAY_DENSITY_DETECTED[] && return false

    # A window whose units are points has more than one pixel in each unit.
    pixels_per_window_unit = _measure_pixels_per_window_unit(win, renderer)
    if pixels_per_window_unit > 1
        _PROBED_DISPLAY_DENSITY[] = pixels_per_window_unit
        _DISPLAY_DENSITY_DETECTED[] = true
        @debug "Display density: $(_PROBED_DISPLAY_DENSITY[]) (SDL renderer ratio)"
        return true
    end

    # SDL DPI fallback (Windows / some X11 setups).
    display_index = SDL_GetWindowDisplayIndex(win)
    display_index < 0 && return false
    ddpi = Ref{Cfloat}(0)
    hdpi = Ref{Cfloat}(0)
    vdpi = Ref{Cfloat}(0)
    if SDL_GetDisplayDPI(display_index, ddpi, hdpi, vdpi) == 0 && ddpi[] > 0
        _PROBED_DISPLAY_DENSITY[] = Float64(ddpi[]) / 96.0
        _DISPLAY_DENSITY_DETECTED[] = true
        @debug "Display density: $(_PROBED_DISPLAY_DENSITY[]) (SDL DPI = $(ddpi[]))"
        return true
    end
    false
end

# Destroy one native SDL window. Loaded fonts persist in the
# module-level cache until `quit_backend!`.
function _close_native_window!(res::SdlWindowResources)
    res.target != C_NULL && SDL_DestroyTexture(res.target)
    res.scratch != C_NULL && SDL_DestroyTexture(res.scratch)
    _evict_renderer_textures!(res.renderer)
    SDL_DestroyRenderer(res.renderer)
    SDL_DestroyWindow(res.win)
end

# ── Font resolution ────────────────────────────────────────────────────

# The handle of `font` at the device size for `ratio`.
function _get_font(font::StyleFont, ratio::Float64)
    size = font_device_size(font, ratio)
    key = (compute_font_path(font), size)
    get!(_font_cache, key) do
        # `font_file` and not the path that `compute_font_path` gives: that path
        # is where the font was when the style package was compiled, and a bundle
        # copied to another machine has it somewhere else. The metrics reader
        # resolves the same way, so SDL and it always open one file.
        path = font_file(first(key))
        f = TTF_OpenFont(path, size)
        @assert f != C_NULL "Font load failed: $path@$(size)"
        _set_layout_rendering!(f)
    end
end

# SDL_ttf's `TTF_HINTING_LIGHT_SUBPIXEL`, which the generated binding lacks.
const _TTF_HINTING_LIGHT_SUBPIXEL = Cint(4)

# A font draws as the layout measures it (`FontFileMeasure`). Light hinting fits
# a glyph to the pixel rows only, so its ink keeps the width of the advance that
# the layout gives it. Answers the handle.
function _set_layout_rendering!(f::Ptr{TTF_Font})
    TTF_SetFontHinting(f, _TTF_HINTING_LIGHT_SUBPIXEL)
    f
end

# ── Fallback fonts ─────────────────────────────────────────────────────
#
# SDL2_ttf draws a character only in the font it is given, and a font it lacks
# draws as a `.notdef` box. So `find_glyph_font_file` says which font draws each
# character, and `compute_placed_glyphs` asks it for each glyph of a drawn text.
# The fallback fonts are monochrome, so every glyph draws through the same
# blended path.

# Open (and cache) the font file at `path` at `size` device px. C_NULL when the
# file is absent or fails to load, so a caller draws in the primary font.
function _get_fallback_font(path::String, size::Int)
    key = (path, size)
    get!(_font_cache, key) do
        file = font_file(path)
        f = isfile(file) ? TTF_OpenFont(file, size) : Ptr{TTF_Font}(C_NULL)
        f == C_NULL ? f : _set_layout_rendering!(f)
    end
end

# SDL_ttf, for the functions of it that the generated binding lacks. Each call
# names `LibSDL2.libsdl2_ttf`, which the JLL sets when it loads, so the library is
# found at run time. A constant keeps the path of the build machine, and a bundle
# then opens a second SDL_ttf that has none of the fonts of the first.

# Where SDL_ttf puts the glyph of `character` in the font `handle`, in device
# pixels: the column of its pen origin and the row of its baseline in the surface
# of the glyph, and a width and a height that the surface never exceeds. SDL_ttf
# lays a glyph out as a string of one character: the pen starts at column 0, or
# right of the ink of a negative left bearing, and the baseline is
# `TTF_FontAscent` rows down, or lower when the ink rises above the ascent.
# `nothing` when the font has no metrics for the glyph.
function _get_glyph_geometry(handle::Ptr{TTF_Font}, character::Char)
    left, right, bottom, top, advance = (Ref{Cint}(0) for _ in 1:5)
    status = ccall((:TTF_GlyphMetrics32, LibSDL2.libsdl2_ttf), Cint,
                   (Ptr{TTF_Font}, UInt32, Ref{Cint}, Ref{Cint}, Ref{Cint}, Ref{Cint}, Ref{Cint}),
                   handle, UInt32(character), left, right, bottom, top, advance)
    status == 0 || return nothing
    ascent = Int(TTF_FontAscent(handle))
    origin = max(0, -Int(left[]))
    baseline = max(ascent, Int(top[]))
    width = origin + max(Int(right[]), Int(advance[]))
    height = baseline + max(Int(TTF_FontHeight(handle)) - ascent, -Int(bottom[]))
    (origin, baseline, width, height)
end

# The glyph of `character` in the font `handle`, rasterized in `color`: the
# surface, the column of its pen origin and the row of its baseline, or
# `nothing` when the glyph has no pixel.
function _render_glyph(handle::Ptr{TTF_Font}, character::Char, color::SDL_Color)
    geometry = _get_glyph_geometry(handle, character)
    geometry === nothing && return nothing
    surface = ccall((:TTF_RenderGlyph32_Blended, LibSDL2.libsdl2_ttf), Ptr{SDL_Surface},
                    (Ptr{TTF_Font}, UInt32, SDL_Color), handle, UInt32(character), color)
    surface == C_NULL && return nothing
    origin, baseline, _, _ = geometry
    (surface, origin, baseline)
end

# The font handle that draws `placed` in a text set in `font`, at the device size
# `size`: the font itself, or the fallback font of the glyph when it opens.
function _get_placed_font(placed::PlacedGlyph, font::StyleFont, primary::Ptr{TTF_Font}, size::Int)
    placed.file == compute_font_path(font) && return primary
    handle = _get_fallback_font(placed.file, size)
    handle == C_NULL ? primary : handle
end

# The surface of `text` in `font` at `ratio`, in `color`: each glyph in the font
# file and at the pen position where the layout measures it
# (`compute_placed_glyphs`), its pen origin on the device pixel nearest to that
# position, so that no advance of SDL_ttf moves a glyph. Answers the surface, the
# column of the pen origin of the text and the row of its baseline, or `nothing`
# when no glyph has a pixel.
function _render_text_surface(text::AbstractString, font::StyleFont, ratio::Float64,
                              color::NTuple{4,UInt8})
    primary = _get_font(font, ratio)
    size = font_device_size(font, ratio)
    sdl_color = SDL_Color(color...)
    glyphs = Tuple{Ptr{SDL_Surface},Int,Int}[]   # (surface, column of its left edge from the pen origin, baseline row)
    for placed in compute_placed_glyphs(text, font)
        handle = _get_placed_font(placed, font, primary, size)
        rendered = _render_glyph(handle, placed.character, sdl_color)
        rendered === nothing && continue
        surface, origin, baseline = rendered
        push!(glyphs, (surface, round(Int, placed.x * ratio) - origin, baseline))
    end
    isempty(glyphs) && return nothing
    left = max(0, -minimum(x for (_, x, _) in glyphs))
    ascent = maximum(baseline for (_, _, baseline) in glyphs)
    width = 0
    height = 0
    for (surface, x, baseline) in glyphs
        info = unsafe_load(surface)
        width = max(width, left + x + Int(info.w))
        height = max(height, ascent - baseline + Int(info.h))
    end
    combined = SDL_CreateRGBSurfaceWithFormat(UInt32(0), Cint(width), Cint(height),
                                              Cint(32), UInt32(SDL_PIXELFORMAT_ARGB8888))
    if combined == C_NULL
        foreach(glyph -> SDL_FreeSurface(glyph[1]), glyphs)
        return nothing
    end
    # Every glyph has the colour of the text, so a surface of that colour with no
    # alpha keeps the colour exact where two glyphs blend over each other.
    red, green, blue, _ = color
    SDL_FillRect(combined, C_NULL,
                 SDL_MapRGBA(unsafe_load(combined).format, red, green, blue, UInt8(0)))
    for (surface, x, baseline) in glyphs
        info = unsafe_load(surface)
        SDL_SetSurfaceBlendMode(surface, SDL_BLENDMODE_BLEND)
        destination = Ref(SDL_Rect(Cint(left + x), Cint(ascent - baseline), info.w, info.h))
        SDL_BlitSurface(surface, C_NULL, combined, destination)
        SDL_FreeSurface(surface)
    end
    (combined, left, ascent)
end

# The rectangle that the texture of `text` in `font` covers when SDL draws it at
# `ratio`, in logical pixels from the `x` and the `y` of the text, found from the
# geometry of each glyph without a render: `(x0, y0, x1, y1)`, or `nothing` when
# no glyph has metrics. The texture can reach past the box of the text: left of
# `x` by a negative left bearing, and above its top by a glyph that rises above
# the ascent of its font.
function _compute_text_texture_box(text::AbstractString, font::StyleFont, ratio::Float64)
    primary = _get_font(font, ratio)
    size = font_device_size(font, ratio)
    x0 = y0 = typemax(Int)
    x1 = y1 = typemin(Int)
    for placed in compute_placed_glyphs(text, font)
        geometry = _get_glyph_geometry(_get_placed_font(placed, font, primary, size), placed.character)
        geometry === nothing && continue
        origin, baseline, width, height = geometry
        left = round(Int, placed.x * ratio) - origin
        x0 = min(x0, left); x1 = max(x1, left + width)
        y0 = min(y0, -baseline); y1 = max(y1, height - baseline)
    end
    x0 == typemax(Int) && return nothing
    _, ascent, _ = compute_text_extent(text, font)
    (floor(Int, x0 / ratio), ascent + floor(Int, y0 / ratio),
     ceil(Int, x1 / ratio), ascent + ceil(Int, y1 / ratio))
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
    key = _TextTextureKey(renderer, String(text), compute_font_path(font_style),
                          font_logical_size(font_style), font_device_size(font_style, ratio),
                          color)

    # Reuse the uploaded texture for an unchanged (text, font, colour) span;
    # rasterize + upload only on a cache miss. The texture is rasterized at
    # device size and freed when its renderer is torn down.
    entry = get(_text_texture_cache, key, nothing)
    if entry === nothing
        rendered = _render_text_surface(text, font_style, ratio, color)
        rendered === nothing && return
        surface, left, ascent = rendered
        texture = SDL_CreateTextureFromSurface(renderer, surface)
        # The software renderer draws a scaled texture that a clip cuts from the
        # cut part of its source, so a linear sample at the edge of the clip takes
        # other texels than an uncut draw: a rectangle of a partial paint that cuts
        # a text would draw other pixels than a full paint. A nearest sample of a
        # text that the supersample scales by a whole number is the same under any
        # clip.
        _is_software_renderer(renderer) &&
            SDL_SetTextureScaleMode(texture, SDL_ScaleModeNearest)
        w_ref, h_ref = Ref{Cint}(0), Ref{Cint}(0)
        SDL_QueryTexture(texture, C_NULL, C_NULL, w_ref, h_ref)
        SDL_FreeSurface(surface)
        length(_text_texture_cache) >= _TEXT_TEXTURE_CACHE_CAP && _clear_text_texture_cache!()
        _, box_ascent, _ = compute_text_extent(text, font_style)
        entry = _TextTexture(texture, Int(w_ref[]), Int(h_ref[]), left, ascent, box_ascent)
        _text_texture_cache[key] = entry
    end

    # The pen origin of the text is its `x`, and its baseline is where the layout
    # put it: the ascent of its box (`compute_text_extent`) below its `y`. The
    # pen origin of the texture is `entry.left` device pixels right of its left
    # edge, and its baseline `entry.ascent` device pixels below its top. The rect
    # is in logical pixels as real numbers, and the renderer scale maps it to
    # whole device pixels, so the texture lands 1:1 and stays crisp at any ratio.
    baseline = Float64(elem.y + oy + entry.box_ascent)
    dest = Ref(SDL_FRect(Cfloat(elem.x + ox - entry.left / ratio),
                         Cfloat(baseline - entry.ascent / ratio),
                         Cfloat(entry.dw / ratio), Cfloat(entry.dh / ratio)))
    SDL_RenderCopyF(renderer, entry.texture, C_NULL, dest)
end

# True when `renderer` is the software renderer of SDL: the renderer of each
# offscreen render, and of a window on a machine with no accelerated driver.
function _is_software_renderer(renderer::Ptr{SDL_Renderer})
    info = Ref{SDL_RendererInfo}()
    SDL_GetRendererInfo(renderer, info) == 0 &&
        (info[].flags & SDL_RENDERER_SOFTWARE) != 0
end

# ── Render a GraphicsViewport element ────────────────────────────────

# The edges of the clip in force, in absolute logical pixels. A laid-out canvas
# walks its elements between them, so an element outside is neither drawn nor
# read.
struct _ClipEdges
    left::Int
    top::Int
    right::Int
    bottom::Int
end

# A paint of one rectangle of the dirty walk at a time: the records of the walk,
# the rectangle in paint, and the count of the leaves that the paint drew. The
# render reads it to skip a graphic that can draw no pixel in the rectangle.
mutable struct _PartialPaint
    records::Dict{UInt,NTuple{4,Int}}
    rect::NTuple{4,Int}
    drawn::Int
end

# True when the graphic placed at `key` draws no pixel in the rectangle of
# `paint`: its record, widened by the pad of a dirty rectangle, does not meet the
# rectangle. The record of a canvas covers what it holds, and the record of a
# viewport is its box. A graphic with no record is drawn.
function _is_outside_partial_paint(paint::_PartialPaint, key::UInt)
    bounds = get(paint.records, key, nothing)
    bounds === nothing && return false
    (x0, y0, x1, y1) = paint.rect
    pad = _DIRTY_RECT_PAD
    bounds[3] + pad <= x0 || bounds[1] - pad >= x1 || bounds[4] + pad <= y0 || bounds[2] - pad >= y1
end

# The placement key of `elem` in the container placed at `key`, made as the dirty
# walk makes it; 0 in a full paint, which reads no record.
_make_render_key(paint::Union{Nothing,_PartialPaint}, elem, key::UInt) =
    paint === nothing ? UInt(0) : _make_placement_key(elem, key)

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

# The scale in force of `renderer`: the display density times the supersample
# factor of a window or of an offscreen renderer, times the scale of each
# viewport that the render is in.
function _get_render_scale(renderer::Ptr{SDL_Renderer})
    fx = Ref{Cfloat}(0); fy = Ref{Cfloat}(0)
    SDL_RenderGetScale(renderer, fx, fy)
    (fx[] > 0 ? Float64(fx[]) : 1.0, fy[] > 0 ? Float64(fy[]) : 1.0)
end

# The device pixels that the logical box from `(x0, y0)` to `(x1, y1)` touches at
# the scale `(scale_x, scale_y)`, as a rectangle to set at the scale 1: the corner
# rounds down and the far edge rounds up.
function _make_device_rect(x0::Int, y0::Int, x1::Int, y1::Int, scale_x::Float64, scale_y::Float64)
    left = floor(Int32, x0 * scale_x)
    top = floor(Int32, y0 * scale_y)
    SDL_Rect(left, top, ceil(Int32, x1 * scale_x) - left, ceil(Int32, y1 * scale_y) - top)
end

# Viewports nest, and SDL's clip rectangle does not. `SDL_RenderSetClipRect`
# REPLACES what is in force, and clearing it with `C_NULL` removes clipping
# altogether rather than putting the enclosing one back. Left to SDL, a viewport
# inside a viewport would widen the clip to its own box on the way in and remove
# it entirely on the way out: everything drawn after an inner viewport, still
# inside the outer one, would be unclipped, and a tab page holding a scroll pane
# would draw its later content over the tab strip and outside the page.
#
# So a viewport intersects with the clip in force, and restores it afterwards.
#
# SDL keeps a clip in device pixels: it scales a clip by the scale in force when
# the clip is set, and it answers the clip in force in the units of the scale in
# force, cut to whole units. Under the scale of a content, a whole unit is more
# than one pixel. So a viewport reads and sets each clip at the scale 1, in
# device pixels, and it sets the scale of its content after the clip: no scale
# rounds a clip.
#
# In a partial paint, `key` is the placement key of the viewport. Its content
# skips what misses the rectangle in paint, except under a scale: the records
# there are in the units of the content.
function _render_viewport!(renderer::Ptr{SDL_Renderer}, vp::GraphicsViewport, ox::Int, oy::Int,
                          ratio::Float64; paint::Union{Nothing,_PartialPaint} = nothing,
                          key::UInt = UInt(0))
    vx = Int(vp.x) + ox
    vy = Int(vp.y) + oy
    vw = Int(vp.w)
    vh = Int(vp.h)
    canvas = vp.content::GraphicsCanvas
    cx, cy = Int(canvas.x), Int(canvas.y)
    M = vp.transform::AffineTransform
    org_x, org_y, edges = _compute_viewport_content_place(vx, vy, vw, vh, cx, cy, M)
    # Only the scale (a, d) and the translation (e, f) of a transform count; a
    # rotation or a shear is dropped.
    plain = _is_plain_viewport_transform(M)
    sx = plain || M.a == 0.0 ? 1.0 : M.a
    sy = plain || M.d == 0.0 ? 1.0 : M.d
    base_x, base_y = _get_render_scale(renderer)
    SDL_RenderSetScale(renderer, 1.0f0, 1.0f0)
    prev = _clip_current(renderer)
    box = _make_device_rect(vx, vy, vx + vw, vy + vh, base_x, base_y)
    SDL_RenderSetClipRect(renderer, Ref(prev === nothing ? box : _clip_intersect(box, prev)))
    SDL_RenderSetScale(renderer, Cfloat(base_x * sx), Cfloat(base_y * sy))
    if plain
        _render_canvas!(renderer, canvas, org_x, org_y, edges, ratio;
                        paint, key = _make_render_key(paint, canvas, key))
    else
        _render_canvas!(renderer, canvas, org_x, org_y, edges, ratio)
    end
    SDL_RenderSetScale(renderer, 1.0f0, 1.0f0)
    _clip_restore!(renderer, prev)
    SDL_RenderSetScale(renderer, Cfloat(base_x), Cfloat(base_y))
end

# True when a viewport draws its content unscaled and unmoved, so a plain clip to
# its box is the whole of the transform.
_is_plain_viewport_transform(M::AffineTransform) =
    M === affine_identity ||
    (M.a == 1.0 && M.d == 1.0 && M.e == 0.0 && M.f == 0.0 && is_affine_axis_aligned(M))

# Where a viewport with the absolute box `(vx, vy, vw, vh)` draws its content at the
# content offset `(cx, cy)`: the content origin and the edges of the clip that
# `_render_canvas!` gets, in the units the content is drawn in. The render and the
# dirty walk both read it, so the walk visits what the render draws.
#
# Under a scale, a content-local element coord `l` must land at viewport-space
# `t + s*(c+l)`; under the scaled renderer the passed origin is therefore
# `(v+t)/s + c`. Rotation/shear (off-diagonal) is dropped: only the scale (a, d)
# and translation (e, f) are honoured.
function _compute_viewport_content_place(vx::Int, vy::Int, vw::Int, vh::Int, cx::Int, cy::Int,
                                     M::AffineTransform)
    _is_plain_viewport_transform(M) &&
        return (vx + cx, vy + cy, _ClipEdges(vx, vy, vx + vw, vy + vh))
    sx = M.a == 0.0 ? 1.0 : M.a
    sy = M.d == 0.0 ? 1.0 : M.d
    (round(Int, (vx + M.e) / sx) + cx, round(Int, (vy + M.f) / sy) + cy,
     _ClipEdges(round(Int, vx / sx), round(Int, vy / sy),
                round(Int, (vx + vw) / sx), round(Int, (vy + vh) / sy)))
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

# ── Render a GraphicsArc element ─────────────────────────────────────

# Fill the band between the radii `rad` and `rad - bw` from `start` through
# `sweep` degrees (0 at the top, clockwise on the screen) as one strip of
# triangles with float vertices. A segment is about two device pixels of the
# outer edge long, so the supersample downsample smooths the curve as it smooths
# the rows of `_stroke_ring!`.
function _fill_arc_band!(renderer::Ptr{SDL_Renderer}, cx::Int, cy::Int, rad::Int, bw::Int,
                         start::Float64, sweep::Float64,
                         r::UInt8, g::UInt8, b::UInt8, a::UInt8)
    fx = Ref{Cfloat}(0); fy = Ref{Cfloat}(0)
    SDL_RenderGetScale(renderer, fx, fy)
    f = Float64(fx[]); f <= 0 && (f = 1.0)
    rin = rad - bw
    n = max(2, ceil(Int, deg2rad(sweep) * rad * f / 2))
    col = SDL_Color(r, g, b, a)
    z = SDL_FPoint(0.0f0, 0.0f0)
    verts = Vector{SDL_Vertex}(undef, 2 * (n + 1))
    for k in 0:n
        s, c = sincosd(start + sweep * k / n)
        verts[2k + 1] = SDL_Vertex(SDL_FPoint(Cfloat(cx + rad * s), Cfloat(cy - rad * c)), col, z)
        verts[2k + 2] = SDL_Vertex(SDL_FPoint(Cfloat(cx + rin * s), Cfloat(cy - rin * c)), col, z)
    end
    idx = Vector{Cint}(undef, 6n)
    for k in 0:(n - 1)
        o = Cint(2k)
        idx[6k + 1:6k + 6] .= (o, o + Cint(1), o + Cint(2), o + Cint(1), o + Cint(3), o + Cint(2))
    end
    GC.@preserve verts idx begin
        SDL_RenderGeometry(renderer, Ptr{SDL_Texture}(C_NULL),
                           pointer(verts), Cint(length(verts)),
                           pointer(idx), Cint(length(idx)))
    end
end

function _render_arc!(renderer::Ptr{SDL_Renderer}, arc::GraphicsArc, ox::Int, oy::Int)
    arc.color.alpha == 0 && return
    sweep = Float64(arc.sweep_angle)
    sweep > 0 || return
    rad = Int(arc.radius)
    rad > 0 || return
    bw = clamp(Int(arc.width), 1, rad)
    cx, cy = Int(arc.cx) + ox, Int(arc.cy) + oy
    if sweep >= 360
        # The whole ring is the ring of a circle, drawn the same way.
        SDL_SetRenderDrawColor(renderer, _rgba8(arc.color)...)
        _stroke_ring!(renderer, cx, cy, rad, bw)
    else
        _fill_arc_band!(renderer, cx, cy, rad, bw, Float64(arc.start_angle), sweep, _rgba8(arc.color)...)
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
#
# In a partial paint, `paint` holds the rectangle in paint and `key` is the
# placement key of `canvas`. The render then skips each element whose record
# misses the rectangle, with all that it holds. A full paint passes `nothing`.
function _render_canvas!(renderer::Ptr{SDL_Renderer}, canvas::GraphicsCanvas, ox::Int, oy::Int,
                         edges::_ClipEdges, ratio::Float64;
                         paint::Union{Nothing,_PartialPaint} = nothing, key::UInt = UInt(0))
    layout = canvas.layout
    elements = canvas.elements
    early_stop = !canvas.overlapping_elements && layout != layout_none
    if elements isa ListNode
        # A list can be endless, so only a layout with no overlap may hold one.
        check_list_canvas(elements, layout, canvas.overlapping_elements)
        # Traverse prev links to render content before the head (e.g. negative y offsets)
        prev_node = elements.prev
        while prev_node !== nothing
            elem = prev_node.value
            if !(elem isa GraphicsFence)
                _render_element_guarded!(renderer, elem, ox, oy, edges, ratio; paint,
                                         key = _make_render_key(paint, elem, _make_render_key(paint, prev_node, key)))
                if early_stop
                    if layout == layout_vertical
                        ey = _find_render_coordinate(_render_elem_y, elem)
                        ey !== nothing && (ey + oy) < edges.top && break
                    elseif layout == layout_horizontal
                        ex = _find_render_coordinate(_render_elem_x, elem)
                        ex !== nothing && (ex + ox) < edges.left && break
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
                        ey = _find_render_coordinate(_render_elem_y, elem)
                        ey !== nothing && (ey + oy) > edges.bottom && break
                    elseif layout == layout_horizontal
                        ex = _find_render_coordinate(_render_elem_x, elem)
                        ex !== nothing && (ex + ox) > edges.right && break
                    end
                end
                _render_element_guarded!(renderer, elem, ox, oy, edges, ratio; paint,
                                         key = _make_render_key(paint, elem, _make_render_key(paint, node, key)))
            end
            node = node.next
        end
    else
        # A laid-out canvas starts at the first element that reaches into the
        # clip. The elements before it end before the near edge, so their
        # content is not read.
        for i in _compute_first_drawn_index(canvas, ox, oy, edges):length(elements)
            elem = elements[i]
            elem isa GraphicsFence && continue
            if early_stop
                if layout == layout_vertical
                    ey = _find_render_coordinate(_render_elem_y, elem)
                    ey !== nothing && (ey + oy) > edges.bottom && break
                elseif layout == layout_horizontal
                    ex = _find_render_coordinate(_render_elem_x, elem)
                    ex !== nothing && (ex + ox) > edges.right && break
                end
            end
            _render_element_guarded!(renderer, elem, ox, oy, edges, ratio; paint,
                                     key = _make_render_key(paint, elem, key))
        end
    end
end

# The index of the first element of `canvas` that the render and the walks visit:
# the near edge of the clip on the layout axis, moved into the canvas coordinates.
_compute_first_drawn_index(canvas::GraphicsCanvas, ox::Int, oy::Int, edges::_ClipEdges) =
    compute_first_visible_index(canvas,
        canvas.layout == layout_horizontal ? edges.left - ox : edges.top - oy)

function _dispatch_render_elem!(renderer::Ptr{SDL_Renderer}, elem, ox::Int, oy::Int,
                                edges::_ClipEdges, ratio::Float64;
                                paint::Union{Nothing,_PartialPaint} = nothing, key::UInt = UInt(0))
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
    elseif elem isa GraphicsArc
        _render_arc!(renderer, elem, ox, oy)
    elseif elem isa GraphicsViewport
        _render_viewport!(renderer, elem, ox, oy, ratio; paint, key)
    elseif elem isa GraphicsImage
        _render_image!(renderer, elem, ox, oy)
    elseif elem isa GraphicsCanvas
        # Nested canvas: offset its origin by its position. `edges` are the
        # absolute clip edges, used only by the early stop, so they pass
        # through unchanged: a child's local offset moves `oy`, and with it the
        # absolute y of each element, not the clip.
        cx, cy = Int(elem.x), Int(elem.y)
        _render_canvas!(renderer, elem, ox + cx, oy + cy, edges, ratio; paint, key)
    end
    # GraphicsFence and unknown types are silently skipped
end

_render_elem_x(elem) = hasfield(typeof(elem), :x) ? Int(elem.x) : nothing
_render_elem_y(elem) = hasfield(typeof(elem), :y) ? Int(elem.y) : nothing

# One element drawn, or skipped when reading it throws while an editor paints
# with its barriers on: the editor records the fault, the rest of the canvas
# draws, and a fault that a barrier took draws as its mark on the next frame.
# Outside such a paint the exception goes on, so a test sees it.
#
# In a partial paint, an element placed at `key` whose record misses the
# rectangle in paint is not drawn, nor is a graphic that draws no pixel, and each
# leaf that is drawn counts.
function _render_element_guarded!(renderer::Ptr{SDL_Renderer}, elem, ox::Int, oy::Int,
                                  edges::_ClipEdges, ratio::Float64;
                                  paint::Union{Nothing,_PartialPaint} = nothing, key::UInt = UInt(0))
    paint === nothing || !_is_outside_partial_paint(paint, key) || return nothing
    try
        if paint !== nothing
            # A graphic that draws no pixel has no record, and it would draw in
            # every rectangle.
            _is_invisible_graphic(elem) && return nothing
            _is_leaf_graphic(elem) && (paint.drawn += 1)
        end
        _dispatch_render_elem!(renderer, elem, ox, oy, edges, ratio; paint, key)
    catch exception
        record_paint_fault!(exception; origin = typeof(elem)) || rethrow()
    end
    nothing
end

# The place of an element on the axis of the early stop, or `nothing` when it has
# none, or when reading it throws and the editor that paints records the fault.
function _find_render_coordinate(read, elem)
    try
        read(elem)
    catch exception
        record_paint_fault!(exception; origin = typeof(elem)) || rethrow()
        nothing
    end
end

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
        _forget_painted_geometry!(res)
    end
    true
end

# ── Dirty-rectangle analysis ─────────────────────────────────────────────
#
# Walk the canvas tree (mirroring `_render_canvas!`'s offset accumulation and
# extents) and return the set of absolute logical rectangles that covers every
# graphic that changed, empty if nothing changed (`_DirtyRegion`). A graphic changes in one
# of three ways, and the walk finds each in its own way.
#
# Its content changed. Detection keys on the reactive `valid` flag of the
# relevant cells, tested via `is_cell_valid` *before* the value is read
# (reading computes, or checks). Because writing a primitive cell marks it valid (only its
# dependents go stale), the detectable dirty units are the *computed* container
# cells the projection pipeline invalidates — a canvas whose `CellVector`-backed
# `elements` cell or one slot of it is stale, or a `ListNode` whose spine / value
# cells are stale — plus any leaf whose own field cell is stale (in-place
# mutation).
#
# It moved, or it was resized. The geometry of a container is compared BY VALUE
# with the geometry it was painted with (`res.painted`). The origin of a
# paragraph below an edit is not valid when the walk tests it, whether or not a
# height changed, because it waits for a computation or a check. A container
# painted at the same place is not a unit; one that moved is.
#
# It came into view, or it left it. A graphic the walk has no record of is new
# to the screen and is painted. A graphic that was painted and now lies past the
# layout early-stop is not drawn, and its old place is cleared. A graphic that
# was painted and that its canvas no longer holds is cleared too. The walk finds
# it by the keys of what the canvas draws, compared with the keys it painted, and
# not by a stale cell: the size of a canvas reads its elements, so a layout that
# reads the size before the walk computes a new element list, and the walk finds
# the list valid.
#
# For each dirty unit the region gets its *new* bounds and its *previous*
# rendered bounds (cached in `res.dirty_bounds`) so content that moved, shrank or
# was removed still clears its vacated pixels. A unit is painted whole, so the walk
# also records the bounds and the place of everything inside it that the render
# reaches (`_record_painted_element!`): the first change inside it then knows
# what it covered and where it was.
#
# A record is keyed by the PLACEMENT of a graphic, not by the graphic alone: the
# `objectid` of the graphic mixed with the key of the container that holds it
# (`_make_placement_key`). One graphic can be drawn at more than one place — the
# regions of a table share its rules and bands — and each place has its own
# geometry.

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
_acc_tuple_or_nothing(a::_DirtyAcc) = _acc_empty(a) ? nothing : _acc_tuple(a)

# True when a box covers no pixel: a hidden viewport of zero size paints nothing,
# and its corner must not stretch a rectangle.
_is_empty_box(b::NTuple{4,Int}) = !(b[3] > b[1] && b[4] > b[2])

# The dirty region of a frame: a set of rectangles, each painted on its own. A
# rectangle that another one covers completely is dropped; rectangles that only
# overlap are both kept, so two small changes far apart repaint two small boxes
# and not the box that spans both.
struct _DirtyRegion
    rects::Vector{NTuple{4,Int}}
end
_DirtyRegion() = _DirtyRegion(NTuple{4,Int}[])

_is_rect_covered(inner::NTuple{4,Int}, outer::NTuple{4,Int}) =
    outer[1] <= inner[1] && outer[2] <= inner[2] && outer[3] >= inner[3] && outer[4] >= inner[4]

function _add_dirty_rect!(region::_DirtyRegion, r::NTuple{4,Int})
    _is_empty_box(r) && return nothing
    any(q -> _is_rect_covered(r, q), region.rects) && return nothing
    filter!(q -> !_is_rect_covered(q, r), region.rects)
    push!(region.rects, r)
    nothing
end

# True when the rectangles `a` and `b` share a pixel.
_has_overlap(a::NTuple{4,Int}, b::NTuple{4,Int}) =
    a[1] < b[3] && b[1] < a[3] && a[2] < b[4] && b[2] < a[4]

# A box of a viewport with a scale that a rectangle of `region` cuts is painted
# after the rectangles, whole, cut only to the window. The software renderer draws
# a scaled texture that a clip cuts off its grid of pixels with another sampling,
# so content cut that way would differ from a full paint, and a later paint of the
# whole box draws over the cut. A box that a box painted so cuts is painted too.
# The smaller boxes go first, so a box inside another one is painted again by it,
# under the clips of a full paint. A rectangle that such a box covers is dropped.
# The records keep the box of a viewport inside scaled content in the units of
# that content: a rectangle that meets such a box only repaints more than it must.
function _extend_over_scaled_viewports!(region::_DirtyRegion, res::SdlWindowResources)
    isempty(region.rects) && return nothing
    boxes = NTuple{4,Int}[]
    for (box, _, transform) in values(res.painted.viewports)
        _is_plain_viewport_transform(transform) && continue
        window_box = (clamp(box[1], 0, res.width), clamp(box[2], 0, res.height),
                      clamp(box[3], 0, res.width), clamp(box[4], 0, res.height))
        _is_empty_box(window_box) || push!(boxes, window_box)
    end
    cuts(r, box) = _has_overlap(r, box) && !_is_rect_covered(box, r)
    painted = NTuple{4,Int}[]
    grown = true
    while grown
        grown = false
        for box in boxes
            box in painted && continue
            (any(r -> cuts(r, box), region.rects) || any(b -> cuts(b, box), painted)) || continue
            push!(painted, box)
            grown = true
        end
    end
    sort!(painted; by = b -> (b[3] - b[1]) * (b[4] - b[2]))
    for box in painted
        filter!(r -> !_is_rect_covered(r, box), region.rects)
        push!(region.rects, box)
    end
    nothing
end

# True if any of `elem`'s own visual field cells is stale. A view state field is
# the reader's (not rendered) and `:prev`/`:next` are the list spine (handled
# separately), so they never force a repaint on their own.
function _node_dirty(elem)::Bool
    for f in fieldnames(typeof(elem))
        (is_view_state_field(f) || f === :prev || f === :next) && continue
        c = getfield(elem, f)
        c isa Cell || continue
        is_cell_valid(c) || return true
    end
    false
end

# Bounds of a single element / a whole canvas, returned as an absolute logical
# `(x0,y0,x1,y1)` tuple or `nothing` if empty. A text covers its box and the
# texture that SDL draws for it at `ratio`, the ratio it is drawn at, so its
# bounds cover every pixel that the render gives it. Every other element takes
# the bounds of `extend_element_bounds!` (and so recomputes the cells it reads —
# exactly what we want, since the unit is about to be repainted).
function _bounds_of_elem(elem, ox::Int, oy::Int, ratio::Float64)
    _is_invisible_graphic(elem) && return nothing
    get_content_box(_extend_drawn_bounds!(ContentBounds(), elem, (ox, oy), ratio))
end

function _bounds_of_canvas(canvas::GraphicsCanvas, ox::Int, oy::Int, ratio::Float64)
    has_declared_extent(canvas) && return (ox, oy, ox + Int(canvas.w), oy + Int(canvas.h))
    bounds = ContentBounds()
    for elem in canvas.elements
        _extend_drawn_bounds!(bounds, elem, (ox, oy), ratio)
    end
    get_content_box(bounds)
end

# True for a graphic that SDL draws no pixel of, so it has no bounds to paint: a
# rectangle with a transparent fill and no visible border, such as the hit target
# of a widget, and a pointer shape, which only says how the pointer looks over its
# box, such as the arrow over the whole gutter of a text.
_is_invisible_graphic(elem) =
    elem isa GraphicsPointerShape ||
    (elem isa GraphicsRect && elem.color.alpha == 0 &&
     (Int(elem.border_width) == 0 || elem.border_color.alpha == 0))

# Extend the bounds by what SDL draws for `elem` at the content origin.
function _extend_drawn_bounds!(bounds::ContentBounds, elem, origin::NTuple{2,Int},
                               ratio::Float64)
    (ox, oy) = origin
    if elem isa GraphicsText
        extend_element_bounds!(bounds, elem, origin)
        texture = _compute_text_texture_box(elem.text, elem.font, ratio)
        texture === nothing && return bounds
        x, y = ox + Int(elem.x), oy + Int(elem.y)
        extend_content_bounds!(bounds, (x + texture[1], y + texture[2], x + texture[3], y + texture[4]))
    elseif elem isa GraphicsCanvas
        x, y = ox + Int(elem.x), oy + Int(elem.y)
        has_declared_extent(elem) &&
            return extend_content_bounds!(bounds, (x, y, x + Int(elem.w), y + Int(elem.h)))
        for child in elem.elements
            _extend_drawn_bounds!(bounds, child, (x, y), ratio)
        end
    else
        extend_element_bounds!(bounds, elem, origin)
    end
    bounds
end

# ── The layout early-stop ──
#
# A vertical or horizontal canvas whose elements do not overlap stops drawing at
# the first element past the far edge of the viewport, and a list stops at the
# first element before the near edge when it walks back. `edges` are the
# absolute edges of the clip; the render passes them to a nested canvas
# unchanged. A laid-out `CellVector` starts at `_compute_first_drawn_index`.

function _is_past_early_stop(elem, ox::Int, oy::Int, edges::_ClipEdges,
                             layout::LayoutDirection, early::Bool)::Bool
    early || return false
    if layout == layout_vertical
        ey = _render_elem_y(elem)
        return ey !== nothing && (ey + oy) > edges.bottom
    elseif layout == layout_horizontal
        ex = _render_elem_x(elem)
        return ex !== nothing && (ex + ox) > edges.right
    end
    false
end

function _is_before_early_start(elem, ox::Int, oy::Int, edges::_ClipEdges,
                                layout::LayoutDirection, early::Bool)::Bool
    early || return false
    if layout == layout_vertical
        ey = _render_elem_y(elem)
        return ey !== nothing && (ey + oy) < edges.top
    elseif layout == layout_horizontal
        ex = _render_elem_x(elem)
        return ex !== nothing && (ex + ox) < edges.left
    end
    false
end

_is_early_stop_layout(canvas::GraphicsCanvas) =
    !canvas.overlapping_elements && canvas.layout != layout_none

# ── What a paint records ──
#
# The bounds `elem` is drawn with at the content origin `(ox, oy)`, as an
# absolute `(x0,y0,x1,y1)` or `nothing`. It records what the next frame compares
# against, for `elem` and for everything inside it that the render reaches: the
# place of each graphic in `res.painted.origins` (the content origin a canvas
# draws its elements at, and the origin of the container of any other graphic),
# its bounds in `res.dirty_bounds`, and the geometry of each viewport. The
# records stop at the layout early-stop, as the render does: what lies past it is
# not drawn, and a graphic that later comes into view has no record and is
# painted then.

# The key of `elem` placed in the container whose key is `parent`. The canvas of
# the window is placed in 0.
_make_placement_key(elem, parent::UInt) = hash(objectid(elem), parent)

function _record_painted_element!(res::SdlWindowResources, elem, key::UInt, ox::Int, oy::Int,
                                  edges::_ClipEdges)
    elem isa GraphicsFence && return nothing
    res.painted.recordings += 1
    elem isa GraphicsCanvas &&
        return _record_painted_canvas!(res, elem, key, ox + Int(elem.x), oy + Int(elem.y), edges)
    elem isa GraphicsViewport && return _record_painted_viewport!(res, elem, key, ox, oy)
    res.painted.origins[key] = (ox, oy)
    signature = _compute_leaf_signature(elem)
    signature === nothing ? delete!(res.painted.signatures, key) :
                            (res.painted.signatures[key] = signature)
    _record_bounds!(res, key, _bounds_of_elem(elem, ox, oy, res.ratio))
end

# What a leaf draws, as one number: the hash of the values of its cells, or
# `nothing` when a value can change in place and keep its hash. The engine
# computes a cell again when a cell it read was written, also when the new value
# is the same, so the walk compares this and the bounds before it paints a leaf
# whose cells were stale. A leaf with no signature is painted whenever it is stale.
function _compute_leaf_signature(elem)::Union{UInt,Nothing}
    signature = hash(typeof(elem))
    for f in fieldnames(typeof(elem))
        (is_view_state_field(f) || f === :prev || f === :next) && continue
        c = getfield(elem, f)
        value = c isa AbstractCell ? c[] : c
        _is_hashed_faithfully(value) || return nothing
        signature = hash(value, signature)
    end
    signature
end

# True for a value whose hash changes whenever what it holds changes: a plain
# value, a small array of plain values, or a document whose fields are immutable
# cells, such as a color or a font, which hashes by identity and can not change in
# place. A pointer, a large array, of which `hash` reads a sample, and any other
# mutable object can change in place and keep their hash.
function _is_hashed_faithfully(value)::Bool
    value isa Ptr && return false
    value isa AbstractString && return true
    value isa Tuple && return all(_is_hashed_faithfully, value)
    value isa AbstractArray && return length(value) < 32768 && isbitstype(eltype(value))
    ismutable(value) || return true
    T = typeof(value)
    fieldcount(T) > 0 && all(i -> fieldtype(T, i) <: ImmutableCell, 1:fieldcount(T))
end

# A canvas whose content origin is `(ox, oy)`.
function _record_painted_canvas!(res::SdlWindowResources, canvas::GraphicsCanvas, key::UInt,
                                 ox::Int, oy::Int, edges::_ClipEdges)
    res.painted.origins[key] = (ox, oy)
    elements = canvas.elements
    layout = canvas.layout
    early = _is_early_stop_layout(canvas)
    acc = _DirtyAcc()
    if elements isa ListNode
        # An endless list in a canvas that can not stop its walk records nothing,
        # as the walk leaves it (`_collect_canvas_dirty!`).
        early || return _record_bounds!(res, key, nothing)
        for node in _collect_drawn_nodes(elements, ox, oy, edges, layout, early)
            b = _record_painted_node!(res, node, node.value, key, ox, oy, edges)
            b === nothing || _acc_extend!(acc, b)
        end
    else
        members = UInt[]
        for i in _compute_first_drawn_index(canvas, ox, oy, edges):length(elements)
            elem = elements[i]
            elem isa GraphicsFence && continue
            _is_past_early_stop(elem, ox, oy, edges, layout, early) && break
            elem_key = _make_placement_key(elem, key)
            push!(members, elem_key)
            b = _record_painted_element!(res, elem, elem_key, ox, oy, edges)
            b === nothing || _acc_extend!(acc, b)
        end
        res.painted.members[key] = members
    end
    _record_bounds!(res, key, _acc_tuple_or_nothing(acc))
end

# A node of a list whose key is `list`: its place, and the bounds of its value.
function _record_painted_node!(res::SdlWindowResources, node::ListNode, value, list::UInt,
                               ox::Int, oy::Int, edges::_ClipEdges)
    key = _make_placement_key(node, list)
    res.painted.origins[key] = (ox, oy)
    _record_bounds!(res, key, _record_painted_element!(res, value, _make_placement_key(value, key),
                                                       ox, oy, edges))
end

# A viewport at the content origin `(ox, oy)`. Its bounds are its box, because it
# clips its content; its content is recorded at the place and to the extent the
# render draws it with.
function _record_painted_viewport!(res::SdlWindowResources, vp::GraphicsViewport, key::UInt,
                                   ox::Int, oy::Int)
    box, content, transform = _get_viewport_geometry(vp, ox, oy)
    res.painted.origins[key] = (ox, oy)
    res.painted.viewports[key] = (box, objectid(content), transform)
    cox, coy, cedges = _compute_viewport_content_place(box, content, transform)
    _record_painted_canvas!(res, content, _make_placement_key(content, key), cox, coy, cedges)
    _record_bounds!(res, key, _is_empty_box(box) ? nothing : box)
end

# The absolute box of `vp` at the content origin `(ox, oy)`, the canvas it shows,
# and its transform: the geometry the walk compares by value.
function _get_viewport_geometry(vp::GraphicsViewport, ox::Int, oy::Int)
    vx, vy = ox + Int(vp.x), oy + Int(vp.y)
    ((vx, vy, vx + Int(vp.w), vy + Int(vp.h)), vp.content::GraphicsCanvas,
     vp.transform::AffineTransform)
end

_compute_viewport_content_place(box::NTuple{4,Int}, content::GraphicsCanvas, M::AffineTransform) =
    _compute_viewport_content_place(box[1], box[2], box[3] - box[1], box[4] - box[2],
                                Int(content.x), Int(content.y), M)

function _record_bounds!(res::SdlWindowResources, key::UInt, b::Union{Nothing,NTuple{4,Int}})
    b === nothing ? delete!(res.dirty_bounds, key) : (res.dirty_bounds[key] = b)
    b
end

_is_painted(res::SdlWindowResources, key::UInt) = haskey(res.painted.origins, key)

# The content of a viewport that only moved since the last paint. `box` is the box
# of the viewport, cut by the boxes of the viewports around it as the walk leaves
# them, and `clip` is the box of the viewport, which clips its content. `offset`
# is how far the content moved, `key` places the viewport, `guard` is the guard of
# the content that the last paint read, and `rects` are the bounds of the
# graphics of the content that the copy does not give.
mutable struct _ContentMove
    box::NTuple{4,Int}
    clip::NTuple{4,Int}
    offset::NTuple{2,Int}
    key::UInt
    guard::Any
    rects::Vector{NTuple{4,Int}}
end

# What one walk collects: the dirty region, and the recordings it defers.
#
# A recording reads the new values of what it records, and a read computes a
# stale cell again. A recording that ran during the walk could compute cells the
# walk had still to test — the box of a composite reads the size of the children
# after it, and the size of a child reads every graphic in it — and hide their
# change. So the walk first finds every change and adds the rectangles it already
# knows: the old bounds of a unit, the old and new box of a viewport, the place a
# graphic left. It runs the recordings after, in the order it met them, so a unit
# is recorded before the container that holds it records its bounds again.
#
# A canvas whose element list is new is read in a second phase, in `lists`, after
# the walk has tested every cell of the frame, because its list can read the size
# of other graphics and compute their cells. Under that canvas the walk compares
# by value (`by_value`): a read of the list can have computed the cells below it,
# so a stale cell there says nothing. A container records its bounds from the
# records of what it draws, so the first phase queues that in `lists` too, after
# the lists below it, and it runs after their recordings. The clip of a viewport,
# in the `clips` of the walk that holds it, runs after every recording, because a
# recording adds the rectangles it clips; a viewport keeps the clips of the
# viewports inside it and runs them first.
#
# The content of a viewport that only moved is a move, in `moves`: the walk tests
# nothing in it and records it at its new place, and the clip of each viewport
# around it cuts its box. After the recordings, `_settle_content_moves!` gives
# each move the rectangles that a copy of its box cannot give, or its whole box.
struct _DirtyWalk
    region::_DirtyRegion
    deferred::Vector{Function}
    lists::Vector{Function}
    clips::Vector{Function}
    moves::Vector{_ContentMove}
    by_value::Bool
    visits::Base.RefValue{Int}   # the elements tested, shared by every walk of one frame
end
_DirtyWalk() = _DirtyWalk(_DirtyRegion(), Function[], Function[], Function[], _ContentMove[], false, Ref(0))

# The walk of the second phase under a canvas of `walk` whose list is new.
_make_by_value_walk(walk::_DirtyWalk) =
    _DirtyWalk(walk.region, walk.deferred, walk.lists, walk.clips, walk.moves, true, walk.visits)

# The walk of the content of a viewport: a region, clips and moves of its own.
_make_viewport_walk(walk::_DirtyWalk) =
    _DirtyWalk(_DirtyRegion(), walk.deferred, walk.lists, Function[], _ContentMove[], walk.by_value,
               walk.visits)

# Run `f` after the walk. True, so a caller can answer that something changed.
_defer!(walk::_DirtyWalk, f::Function) = (push!(walk.deferred, f); true)

# Run `f`, which records the bounds of a container from the records of what it
# draws, after the recordings of everything inside the container. In the first
# phase a list below it can wait for the second phase, so `f` waits too.
_defer_refresh!(walk::_DirtyWalk, f::Function) =
    walk.by_value ? _defer!(walk, f) : (push!(walk.lists, () -> _defer!(walk, f)); true)

# Clear the place of a graphic that was painted and that the render no longer
# reaches, and forget it. False when it was not painted: the render did not reach
# it before either, so what follows it was not painted.
function _clear_left_view!(res::SdlWindowResources, walk::_DirtyWalk, key::UInt)::Bool
    _is_painted(res, key) || return false
    old = get(res.dirty_bounds, key, nothing)
    old === nothing || _add_dirty_rect!(walk.region, old)
    _forget_painted!(res, key)
    true
end

# Forget the records of the graphic placed at `key`.
function _forget_painted!(res::SdlWindowResources, key::UInt)
    delete!(res.dirty_bounds, key)
    delete!(res.painted.origins, key)
    delete!(res.painted.viewports, key)
    delete!(res.painted.members, key)
    delete!(res.painted.signatures, key)
    delete!(res.painted.guards, key)
    delete!(res.painted.guard_places, key)
    nothing
end

# A dirty unit: after the walk, its previous (cached) bounds and its new bounds go
# into the region. `record` computes the new bounds and records them, with
# everything inside the unit, as next frame's "previous"; the old bounds are read
# before it runs. The new bounds are `nothing` when the unit now renders nothing
# (content removed) — its cached old extent is still cleared.
function _union_unit!(res::SdlWindowResources, walk::_DirtyWalk, key::UInt, record::Function)::Bool
    _defer!(walk, () -> begin
        old = get(res.dirty_bounds, key, nothing)
        new = record()
        old === nothing || _add_dirty_rect!(walk.region, old)
        new === nothing || _add_dirty_rect!(walk.region, new)
    end)
end

# Forget what the paints recorded, as a fresh render target does: the next walk
# finds every container unknown and paints it whole.
function _forget_painted_geometry!(res::SdlWindowResources)
    empty!(res.dirty_bounds)
    empty!(res.painted.origins)
    empty!(res.painted.viewports)
    empty!(res.painted.members)
    empty!(res.painted.signatures)
    empty!(res.painted.guards)
    empty!(res.painted.guard_places)
    res.painted.baseline = 0
    nothing
end

# The records of graphics that are gone stay until a full paint, so the count
# may grow to twice what a full paint records, plus this much, before one.
const _PAINTED_RECORD_SLACK = 10_000

_count_painted_records(res::SdlWindowResources) =
    length(res.dirty_bounds) + length(res.painted.origins) + length(res.painted.viewports) +
    length(res.painted.members) + length(res.painted.signatures) + length(res.painted.guards)

_is_painted_geometry_full(res::SdlWindowResources) =
    _count_painted_records(res) > 2 * res.painted.baseline + _PAINTED_RECORD_SLACK

# ── The walk ──
#
# Each walk function answers whether something changed in what it walked: a
# unit, or a graphic that left the view. A container whose content changed so
# records its bounds again after the walk, from the records of the graphics it
# draws (`_refresh_canvas_bounds!`), so that its record covers what is on the
# screen when it moves or leaves the view later.

# True for a graphic that holds no other: its own cells are its whole content.
_is_leaf_graphic(elem) = !(elem isa GraphicsCanvas || elem isa GraphicsViewport)

# Recurse into a canvas at content origin `(ox, oy)`, placed under `key`. `edges`
# are the edges of the clip, threaded exactly as in `_render_canvas!` so the
# dirty walk reads precisely the cells the renderer reads — in particular it
# honours the same layout early-stop, so off-screen `ListNode` tail cells (which
# the renderer leaves lazily invalid) are not misread as "dirty" every frame.
function _collect_canvas_dirty!(res::SdlWindowResources, canvas::GraphicsCanvas, key::UInt,
                                ox::Int, oy::Int, edges::_ClipEdges, walk::_DirtyWalk)::Bool
    elements_cell = getfield(canvas, :elements)
    # A canvas's painted content depends only on its elements and on the place it
    # is painted at — not on w/h/layout (those are metadata for parents/scroll that
    # the renderer never reads, so their cells may stay perpetually invalid and
    # must not be mistaken for "dirty"). `(ox, oy)` already holds this canvas's own
    # offset, which the caller read, so the place is compared by value.
    moved = get(res.painted.origins, key, nothing) != (ox, oy)
    # A valid guard at the same place: nothing that the canvas draws changed since
    # its guard read it, so the walk tests none of its elements.
    moved || _is_guard_valid(res, key, ox, oy, edges) && return false
    list_changed = walk.by_value || !is_cell_valid(elements_cell)
    ev = elements_cell[]                 # read after capturing validity above
    if !list_changed && ev isa CellVector && !is_cell_valid(getfield(ev, :elements))
        list_changed = true              # the regenerated element vector changed
    end
    layout = canvas.layout
    early = _is_early_stop_layout(canvas)
    if ev isa ListNode
        # A list can be endless. In a canvas with no layout, or with overlap,
        # nothing stops its walk, so the walk leaves it, and the render refuses
        # it (`check_list_canvas`).
        _is_early_stop_layout(canvas) || return false
        # A list has no bounds of its own to repaint: a list that moved, or that
        # was never painted, reflows as a changed spine does.
        res.painted.origins[key] = (ox, oy)
        return _collect_listnode_dirty!(res, ev, key, ox, oy, edges, layout, early, walk;
                                        reflow = moved || list_changed)
    end
    if !moved && list_changed && haskey(res.painted.members, key)
        # A new element list, read in the second phase and walked by value.
        walk.by_value && return _collect_new_elements_dirty!(res, canvas, key, ox, oy, edges, walk)
        push!(walk.lists, () -> _collect_new_elements_dirty!(res, canvas, key, ox, oy, edges,
                                                             _make_by_value_walk(walk)))
        return true
    end
    if !moved && !list_changed
        # The walk starts where the render starts. A search that would read a
        # stale slot answers nothing, and the canvas is painted whole.
        start = _find_first_walked_index(canvas, ev, ox, oy, edges)
        if start !== nothing
            first, dirty_leaves = start
            stale_slot, changed = _collect_elements_dirty!(res, canvas, ev, key, first, dirty_leaves,
                                                           ox, oy, edges, walk)
            if !stale_slot
                return changed &&
                       _defer_refresh!(walk, () -> _refresh_canvas_bounds!(res, ev, key, first, ox, oy,
                                                                           edges, layout, early))
            end
        end
    end
    _union_unit!(res, walk, key, () -> _record_painted_canvas!(res, canvas, key, ox, oy, edges))
end

# The index of the first element that the render draws, found by the same search
# as `_compute_first_drawn_index`, and the indices of the leaves that the search
# read while their cells were not valid; or `nothing` when a slot that the
# search reads is not valid. The search reads the place of a few elements,
# and that read computes a stale leaf again, so the walk takes the test of the
# leaf from before the read.
function _find_first_walked_index(canvas::GraphicsCanvas, ev, ox::Int, oy::Int, edges::_ClipEdges)
    (_is_early_stop_layout(canvas) && ev isa CellVector) || return (1, Int[])
    slots = getfield(ev, :elements)[]
    horizontal = canvas.layout == layout_horizontal
    stale_slot = false
    dirty_leaves = Int[]
    first = compute_first_visible_index(length(slots), horizontal ? edges.left - ox : edges.top - oy) do i
        elem = slots[i]
        if elem isa AbstractCell
            is_cell_valid(elem) || (stale_slot = true; return nothing)
            elem = elem[]
        end
        _is_leaf_graphic(elem) && _node_dirty(elem) && push!(dirty_leaves, i)
        horizontal ? _render_elem_x(elem) : _render_elem_y(elem)
    end
    stale_slot ? nothing : (first, dirty_leaves)
end

# The elements of a canvas that is not itself a unit, in the order the renderer
# draws them. Answers whether a slot is stale, and whether something changed in
# an element. A stale slot holds another graphic, so the canvas is painted whole.
# A slot is tested before it is read, as the element list is, and only where the
# walk reaches it, because a slot past the early-stop may stay stale for as long
# as it is off-screen. A leaf is tested before the early-stop reads its place, as
# a canvas is before its origin is read. Past the early-stop, each graphic that
# was painted has left the view and its place is cleared; the first that was not
# painted ends the list. The keys of the elements drawn are compared, in order,
# with the keys that were painted: a list that a reader before the walk computed
# can hold other elements while no cell of it is stale, and what it no longer
# draws is cleared.
function _collect_elements_dirty!(res::SdlWindowResources, canvas::GraphicsCanvas, ev, key::UInt,
                                  first::Int, dirty_leaves::Vector{Int}, ox::Int, oy::Int,
                                  edges::_ClipEdges, walk::_DirtyWalk)
    slots = ev isa CellVector ? getfield(ev, :elements)[] : ev
    layout = canvas.layout
    early = _is_early_stop_layout(canvas)
    painted = get(res.painted.members, key, nothing)
    drawn = 0          # how many elements the render draws
    other = nothing    # the keys of the drawn elements, from the first one that differs from `painted`
    past = false
    changed = false
    for i in first:length(slots)
        slot = slots[i]
        if slot isa AbstractCell
            is_cell_valid(slot) || return (true, changed)
            elem = slot[]
        else
            elem = slot
        end
        elem isa GraphicsFence && continue
        elem_key = _make_placement_key(elem, key)
        leaf_dirty = _is_leaf_graphic(elem) && (i in dirty_leaves || _node_dirty(elem))
        past = past || _is_past_early_stop(elem, ox, oy, edges, layout, early)
        if past
            _clear_left_view!(res, walk, elem_key) || break
            changed = true
        else
            drawn += 1
            if other === nothing && painted !== nothing &&
               (drawn > length(painted) || painted[drawn] != elem_key)
                other = painted[1:drawn - 1]
            end
            other === nothing || push!(other, elem_key)
            changed |= _collect_dirty_elem!(res, elem, elem_key, ox, oy, edges, walk, leaf_dirty)
        end
    end
    if painted !== nothing && (other !== nothing || drawn < length(painted))
        _clear_members_not_drawn!(res, walk, canvas.overlapping_elements, painted,
                                  other === nothing ? painted[1:drawn] : other)
        changed = true
    end
    (false, changed)
end

# Clear what a canvas drew before, the keys `painted`, and does not draw now, the
# keys `drawn`: an element that left the list, or the view. Where elements can
# overlap, the order draws too: a kept element that has another place in the
# order is painted again.
function _clear_members_not_drawn!(res::SdlWindowResources, walk::_DirtyWalk, overlapping::Bool,
                                   painted::Vector{UInt}, drawn::Vector{UInt})
    drawn_set = Set(drawn)
    for old in painted
        old in drawn_set || _clear_left_view!(res, walk, old)
    end
    overlapping || return nothing
    painted_set = Set(painted)
    kept_now = [k for k in drawn if k in painted_set]
    kept_before = [k for k in painted if k in drawn_set]
    for (now, before) in zip(kept_now, kept_before)
        now == before && continue
        bounds = get(res.dirty_bounds, now, nothing)
        bounds === nothing || _add_dirty_rect!(walk.region, bounds)
    end
    nothing
end

# The elements of a canvas whose element list is new and that did not move, in a
# walk by value. Each element is taken by its placement key, as in a list that did
# not change: a new one is painted, a moved one at its old and new place, a kept
# one only when it draws something else. What the canvas drew before and does not
# draw now is cleared (`_clear_members_not_drawn!`).
function _collect_new_elements_dirty!(res::SdlWindowResources, canvas::GraphicsCanvas, key::UInt,
                                      ox::Int, oy::Int, edges::_ClipEdges, walk::_DirtyWalk)
    ev = canvas.elements
    layout = canvas.layout
    early = _is_early_stop_layout(canvas)
    first = _compute_first_drawn_index(canvas, ox, oy, edges)
    drawn = UInt[]
    for i in first:length(ev)
        elem = ev[i]
        elem isa GraphicsFence && continue
        _is_past_early_stop(elem, ox, oy, edges, layout, early) && break
        elem_key = _make_placement_key(elem, key)
        push!(drawn, elem_key)
        _collect_dirty_elem!(res, elem, elem_key, ox, oy, edges, walk, false)
    end
    _clear_members_not_drawn!(res, walk, canvas.overlapping_elements, res.painted.members[key], drawn)
    _defer_refresh!(walk, () -> _refresh_canvas_bounds!(res, ev, key, first, ox, oy, edges, layout, early))
end

# Record the bounds of a canvas again, from the records of the elements it draws,
# and the keys of those elements.
function _refresh_canvas_bounds!(res::SdlWindowResources, ev, key::UInt, first::Int,
                                 ox::Int, oy::Int, edges::_ClipEdges, layout::LayoutDirection,
                                 early::Bool)
    drawn = _DirtyAcc()
    members = UInt[]
    for i in first:length(ev)
        elem = ev[i]
        elem isa GraphicsFence && continue
        _is_past_early_stop(elem, ox, oy, edges, layout, early) && break
        elem_key = _make_placement_key(elem, key)
        push!(members, elem_key)
        b = get(res.dirty_bounds, elem_key, nothing)
        b === nothing || _acc_extend!(drawn, b)
    end
    res.painted.members[key] = members
    _record_bounds!(res, key, _acc_tuple_or_nothing(drawn))
end

# One element at the content origin `(ox, oy)`. `leaf_dirty` is whether a leaf's
# own cells were stale, tested by the caller before any read of its place.
function _collect_dirty_elem!(res::SdlWindowResources, elem, key::UInt, ox::Int, oy::Int,
                              edges::_ClipEdges, walk::_DirtyWalk, leaf_dirty::Bool)::Bool
    elem isa GraphicsFence && return false
    walk.visits[] += 1
    elem isa GraphicsCanvas &&
        return _collect_canvas_dirty!(res, elem, key, ox + Int(elem.x), oy + Int(elem.y), edges, walk)
    elem isa GraphicsViewport && return _collect_viewport_dirty!(res, elem, key, ox, oy, walk)
    # A leaf new to the screen, or one with an in-place-mutated (stale) field cell.
    record = () -> _record_painted_element!(res, elem, key, ox, oy, edges)
    _is_painted(res, key) || return _union_unit!(res, walk, key, record)
    (leaf_dirty || walk.by_value) || return false
    # A leaf that draws what it drew, where it drew it, is not painted.
    _defer!(walk, () -> begin
        old = get(res.dirty_bounds, key, nothing)
        old_signature = get(res.painted.signatures, key, nothing)
        new = record()
        new == old && old_signature !== nothing &&
            old_signature == get(res.painted.signatures, key, nothing) && return
        old === nothing || _add_dirty_rect!(walk.region, old)
        new === nothing || _add_dirty_rect!(walk.region, new)
    end)
end

# A viewport clips its content, so its dirty contribution is clamped to its own
# box. If the viewport moved, was resized, shows another canvas or has another
# transform, its old and its new box are dirty. Its bounds are its box, so only
# such a change changes them. The content collects into a region of its own,
# which is clipped to the box after the walk, when the recordings inside the
# content have added their rectangles.
function _collect_viewport_dirty!(res::SdlWindowResources, vp::GraphicsViewport, key::UInt,
                                  ox::Int, oy::Int, walk::_DirtyWalk)::Bool
    box, content, transform = _get_viewport_geometry(vp, ox, oy)
    painted = get(res.painted.viewports, key, nothing)
    if painted != (box, objectid(content), transform)
        painted === nothing || _add_dirty_rect!(walk.region, painted[1])
        _add_dirty_rect!(walk.region, box)
        return _defer!(walk, () -> _record_painted_viewport!(res, vp, key, ox, oy))
    end
    cox, coy, cedges = _compute_viewport_content_place(box, content, transform)
    content_key = _make_placement_key(content, key)
    # A content that only moved is a move: the walk tests nothing in it, and it
    # records the content at its new place. The second phase compares by value,
    # where a guard says nothing, so it takes no move.
    move = walk.by_value ? nothing :
           _find_content_move(res, key, content_key, box, transform, cox, coy, cedges)
    if move !== nothing
        push!(walk.moves, move)
        old_edges = _move_clip_edges(cedges, move.offset)
        _defer!(walk, () -> _record_moved_canvas!(res, content, content_key, cox, coy, cedges, old_edges,
                                                  move.offset, move.rects))
        return false
    end
    # The content can answer that nothing changed in its bounds while a viewport
    # inside it has rectangles to give, so the clip always runs, after the
    # recordings; an empty region costs nothing there. The clips of the viewports
    # inside the content, also those that the second phase finds, run first, so
    # they add their rectangles before this one clips them.
    inner = _make_viewport_walk(walk)
    _collect_canvas_dirty!(res, content, content_key, cox, coy, cedges, inner)
    push!(walk.clips, () -> begin
        foreach(clip -> clip(), inner.clips)
        _clip_inner_moves!(walk, inner, box, transform)
        isempty(inner.region.rects) && return
        # Under a scale the content's dirty region is in scaled content units;
        # rather than map every sub-rect through the transform, treat any dirty
        # content as dirtying the whole (clipped) viewport box. Correct, and
        # zoom/pan repaints the whole pane anyway.
        if !_is_plain_viewport_transform(transform)
            _add_dirty_rect!(walk.region, box)
            return
        end
        # Intersect each rectangle of the content's dirty region with the box.
        vx, vy, vx1, vy1 = box
        for r in inner.region.rects
            _add_dirty_rect!(walk.region, (max(r[1], vx), max(r[2], vy), min(r[3], vx1), min(r[4], vy1)))
        end
    end)
    false
end

# The move of the content of the viewport placed at `key`, or `nothing`. The
# caller found the box, the content and the transform as the last paint drew
# them. The content moved when its origin `(cox, coy)` is not the origin that the
# last paint recorded. Nothing in it changed when the guard that the last paint
# read for it, at that origin and between the same edges, is still valid: a
# guard reads every cell that the render reads for the elements between its
# edges, and not the origin of its own canvas.
function _find_content_move(res::SdlWindowResources, key::UInt, content_key::UInt, box::NTuple{4,Int},
                            transform::AffineTransform, cox::Int, coy::Int, cedges::_ClipEdges)
    _is_plain_viewport_transform(transform) || return nothing
    origin = get(res.painted.origins, content_key, nothing)
    (origin === nothing || origin == (cox, coy)) && return nothing
    guard = get(res.painted.guards, content_key, nothing)
    guard === nothing && return nothing
    get(res.painted.guard_places, content_key, nothing) == (origin[1], origin[2], cedges) || return nothing
    is_cell_valid(guard) || return nothing
    _ContentMove(box, box, (cox - origin[1], coy - origin[2]), key, guard, NTuple{4,Int}[])
end

_move_clip_edges(edges::_ClipEdges, offset::NTuple{2,Int}) =
    _ClipEdges(edges.left + offset[1], edges.top + offset[2], edges.right + offset[1], edges.bottom + offset[2])

_move_box(box::NTuple{4,Int}, offset::NTuple{2,Int}) =
    (box[1] + offset[1], box[2] + offset[2], box[3] + offset[1], box[4] + offset[2])

_intersect_boxes(a::NTuple{4,Int}, b::NTuple{4,Int}) =
    (max(a[1], b[1]), max(a[2], b[2]), min(a[3], b[3]), min(a[4], b[4]))

# Give the moves found in the content of a viewport with the box `box` to the walk
# around it, with their boxes cut to that box. Under a scale the records of the
# content are in its own units, so a move there paints its box instead, and the
# clip of the viewport grows that to the box of the viewport.
function _clip_inner_moves!(walk::_DirtyWalk, inner::_DirtyWalk, box::NTuple{4,Int},
                            transform::AffineTransform)
    plain = _is_plain_viewport_transform(transform)
    for move in inner.moves
        if plain
            move.box = _intersect_boxes(move.box, box)
            push!(walk.moves, move)
        else
            _add_dirty_rect!(inner.region, move.box)
        end
    end
    empty!(inner.moves)
    nothing
end

# Record a canvas of the content of a move at its new content origin `(ox, oy)`,
# and answer the bounds of what it draws and whether a guard below it must be made
# again. `edges` are the box of the viewport, and the content moved by `offset`.
# The content did not change, so the last paint drew the elements between
# `old_edges`: the edges moved by the offset, or the same edges inside a viewport
# that moved with the content. An element between both edges keeps its records,
# moved by the offset, and reads no cell for them. One between `edges` only came
# into view and is recorded; one between `old_edges` only left it and is
# forgotten; each adds its bounds to `rects`.
#
# An element between both edges that is not a canvas also adds its bounds when
# they cross an edge of the box at its new place or at its old one. The software
# renderer of SDL samples a scaled texture that a clip cuts on another grid, so
# a text that the edge cuts by another amount draws other pixels.
#
# A guard reads the elements between its edges. A canvas that draws other elements
# than the last paint drew has its guard made again at the end of the walk, and so
# has each canvas around it, whose guard reads that one. Any other guard keeps its
# cell, at the new place: a line of a text shows the same tokens when its view
# moves up, and only the list of the lines shows other lines.
function _record_moved_canvas!(res::SdlWindowResources, canvas::GraphicsCanvas, key::UInt,
                               ox::Int, oy::Int, edges::_ClipEdges, old_edges::_ClipEdges,
                               offset::NTuple{2,Int}, rects::Vector{NTuple{4,Int}})
    res.painted.origins[key] = (ox, oy)
    elements = canvas.elements
    layout = canvas.layout
    early = _is_early_stop_layout(canvas)
    remade = false
    acc = _DirtyAcc()
    if elements isa ListNode
        early || return (_record_bounds!(res, key, nothing), false)
        drawn = _collect_drawn_nodes(elements, ox, oy, edges, layout, early)
        drawn_before = _collect_drawn_nodes(elements, ox, oy, old_edges, layout, early)
        kept = Base.IdSet{ListNode}(drawn_before)
        for node in drawn
            node_key = _make_placement_key(node, key)
            if node in kept
                _move_records!(res, node_key, offset)
                value = node.value
                b, below = _record_moved_element!(res, value, _make_placement_key(value, node_key),
                                                  ox, oy, edges, old_edges, offset, rects)
                remade |= below
                value isa GraphicsCanvas || _add_crossing_bounds!(rects, b, edges, old_edges)
            else
                b = _record_painted_node!(res, node, node.value, key, ox, oy, edges)
                b === nothing || push!(rects, b)
            end
            b === nothing || _acc_extend!(acc, b)
        end
        remade |= length(drawn) != length(drawn_before) || any(a !== b for (a, b) in zip(drawn, drawn_before))
        shown = Base.IdSet{ListNode}(drawn)
        for node in drawn_before
            node in shown && continue
            node_key = _make_placement_key(node, key)
            value = node.value
            _clear_moved_left_view!(res, rects, node_key, offset) do
                _forget_painted!(res, node_key)
                _forget_recorded_element!(res, value, _make_placement_key(value, node_key), ox, oy, old_edges)
            end
        end
        return (_record_moved_canvas_bounds!(res, key, ox, oy, edges, acc, remade), remade)
    end
    first_now = _compute_first_drawn_index(canvas, ox, oy, edges)
    first_before = _compute_first_drawn_index(canvas, ox, oy, old_edges)
    members = UInt[]
    members_before = UInt[]
    past_now = past_before = false
    for i in min(first_now, first_before):length(elements)
        elem = elements[i]
        elem isa GraphicsFence && continue
        past_now = past_now || _is_past_early_stop(elem, ox, oy, edges, layout, early)
        past_before = past_before || _is_past_early_stop(elem, ox, oy, old_edges, layout, early)
        past_now && past_before && break
        now = i >= first_now && !past_now
        before = i >= first_before && !past_before
        elem_key = _make_placement_key(elem, key)
        before && push!(members_before, elem_key)
        if now
            push!(members, elem_key)
            if before
                b, below = _record_moved_element!(res, elem, elem_key, ox, oy, edges, old_edges, offset, rects)
                remade |= below
                elem isa GraphicsCanvas || _add_crossing_bounds!(rects, b, edges, old_edges)
            else
                b = _record_painted_element!(res, elem, elem_key, ox, oy, edges)
                b === nothing || push!(rects, b)
            end
            b === nothing || _acc_extend!(acc, b)
        elseif before
            _clear_moved_left_view!(res, rects, elem_key, offset) do
                _forget_recorded_element!(res, elem, elem_key, ox, oy, old_edges)
            end
        end
    end
    res.painted.members[key] = members
    remade |= members != members_before
    (_record_moved_canvas_bounds!(res, key, ox, oy, edges, acc, remade), remade)
end

# Record the bounds of a canvas of a moved content, from what it draws, and its
# guard: forgotten when it is `remade`, so the walk makes it again at its end, and
# else kept at the new place `(ox, oy, edges)`.
function _record_moved_canvas_bounds!(res::SdlWindowResources, key::UInt, ox::Int, oy::Int,
                                      edges::_ClipEdges, acc::_DirtyAcc, remade::Bool)
    if remade
        delete!(res.painted.guards, key)
        delete!(res.painted.guard_places, key)
    elseif haskey(res.painted.guards, key)
        res.painted.guard_places[key] = (ox, oy, edges)
    end
    _record_bounds!(res, key, _acc_tuple_or_nothing(acc))
end

# Move the records of the graphic placed at `key` by `offset`: its place, the box
# of a viewport and its bounds. Answer its bounds at the new place.
function _move_records!(res::SdlWindowResources, key::UInt, offset::NTuple{2,Int})
    origin = get(res.painted.origins, key, nothing)
    origin === nothing || (res.painted.origins[key] = (origin[1] + offset[1], origin[2] + offset[2]))
    geometry = get(res.painted.viewports, key, nothing)
    geometry === nothing ||
        (res.painted.viewports[key] = (_move_box(geometry[1], offset), geometry[2], geometry[3]))
    bounds = get(res.dirty_bounds, key, nothing)
    bounds === nothing && return nothing
    res.dirty_bounds[key] = _move_box(bounds, offset)
end

_get_edges_box(edges::_ClipEdges) = (edges.left, edges.top, edges.right, edges.bottom)

# True when `bounds` meet `box` and reach past it.
_is_crossing_box(bounds::NTuple{4,Int}, box::NTuple{4,Int}) =
    _has_overlap(bounds, box) && !_is_rect_covered(bounds, box)

# Add `bounds` to `rects` when they cross the box of `edges` or of `old_edges`. A
# box that did not move against the content cuts each graphic by the same amount
# in both frames, so then nothing is added.
function _add_crossing_bounds!(rects::Vector{NTuple{4,Int}}, bounds, edges::_ClipEdges,
                               old_edges::_ClipEdges)
    (bounds === nothing || edges == old_edges) && return nothing
    (_is_crossing_box(bounds, _get_edges_box(edges)) || _is_crossing_box(bounds, _get_edges_box(old_edges))) &&
        push!(rects, bounds)
    nothing
end

# An element of the content of a move that the render draws in both frames, and
# whether a guard below it must be made again: a canvas can show other elements
# between the new edges, so it is recorded as a moved canvas, and a viewport as a
# moved viewport; anything else draws the same, and its records move.
function _record_moved_element!(res::SdlWindowResources, elem, key::UInt, ox::Int, oy::Int,
                                edges::_ClipEdges, old_edges::_ClipEdges, offset::NTuple{2,Int},
                                rects::Vector{NTuple{4,Int}})
    elem isa GraphicsCanvas &&
        return _record_moved_canvas!(res, elem, key, ox + Int(elem.x), oy + Int(elem.y), edges, old_edges,
                                     offset, rects)
    elem isa GraphicsViewport &&
        return _record_moved_viewport!(res, elem, key, ox, oy, edges, old_edges, offset, rects)
    (_move_records!(res, key, offset), false)
end

# A viewport in the content of a move that the render draws in both frames. Its
# box moved with the content, so its content shows the same elements, between its
# own box in both frames. A viewport with a scale puts its content on the grid of
# its own units, which a move does not keep, and the edge of the box that cuts a
# viewport cuts it by another amount: each of them adds its box to `rects`.
function _record_moved_viewport!(res::SdlWindowResources, vp::GraphicsViewport, key::UInt, ox::Int, oy::Int,
                                 edges::_ClipEdges, old_edges::_ClipEdges, offset::NTuple{2,Int},
                                 rects::Vector{NTuple{4,Int}})
    box, content, transform = _get_viewport_geometry(vp, ox, oy)
    if !_is_plain_viewport_transform(transform) ||
       (edges != old_edges && (_is_crossing_box(box, _get_edges_box(edges)) ||
                               _is_crossing_box(box, _get_edges_box(old_edges))))
        # Recorded again at its new place, so the guards of its content are made
        # again too.
        b = _record_painted_viewport!(res, vp, key, ox, oy)
        b === nothing || push!(rects, b)
        return (b, true)
    end
    _move_records!(res, key, offset)
    cox, coy, cedges = _compute_viewport_content_place(box, content, transform)
    _, below = _record_moved_canvas!(res, content, _make_placement_key(content, key), cox, coy, cedges, cedges,
                                     offset, rects)
    (_is_empty_box(box) ? nothing : box, below)
end

# An element of the content of a move, placed at `key`, that the last paint drew
# and that the render no longer reaches. After the copy its old pixels lie where
# its record moves by `offset`, so that place goes into `rects`. Then `forget`
# forgets its records.
function _clear_moved_left_view!(forget::Function, res::SdlWindowResources, rects::Vector{NTuple{4,Int}},
                                 key::UInt, offset::NTuple{2,Int})
    old = get(res.dirty_bounds, key, nothing)
    old === nothing || push!(rects, _move_box(old, offset))
    forget()
    nothing
end

# Forget the records that a recording of `elem` placed at `key`, at the content
# origin `(ox, oy)` and between `edges`, writes: its own, and those of all that it
# draws there.
function _forget_recorded_element!(res::SdlWindowResources, elem, key::UInt, ox::Int, oy::Int,
                                   edges::_ClipEdges)
    _forget_painted!(res, key)
    if elem isa GraphicsCanvas
        _forget_recorded_canvas!(res, elem, key, ox + Int(elem.x), oy + Int(elem.y), edges)
    elseif elem isa GraphicsViewport
        box, content, transform = _get_viewport_geometry(elem, ox, oy)
        cox, coy, cedges = _compute_viewport_content_place(box, content, transform)
        content_key = _make_placement_key(content, key)
        _forget_painted!(res, content_key)
        _forget_recorded_canvas!(res, content, content_key, cox, coy, cedges)
    end
    nothing
end

function _forget_recorded_canvas!(res::SdlWindowResources, canvas::GraphicsCanvas, key::UInt,
                                  ox::Int, oy::Int, edges::_ClipEdges)
    elements = canvas.elements
    layout = canvas.layout
    early = _is_early_stop_layout(canvas)
    if elements isa ListNode
        early || return nothing
        for node in _collect_drawn_nodes(elements, ox, oy, edges, layout, early)
            node_key = _make_placement_key(node, key)
            _forget_painted!(res, node_key)
            value = node.value
            _forget_recorded_element!(res, value, _make_placement_key(value, node_key), ox, oy, edges)
        end
        return nothing
    end
    for i in _compute_first_drawn_index(canvas, ox, oy, edges):length(elements)
        elem = elements[i]
        elem isa GraphicsFence && continue
        _is_past_early_stop(elem, ox, oy, edges, layout, early) && break
        _forget_recorded_element!(res, elem, _make_placement_key(elem, key), ox, oy, edges)
    end
    nothing
end

# The nodes of a list that the render draws, in its order: back along the prev
# links from the head, up to and with the first node before the near edge, then
# forward along the next links from the head, up to the first node past the far
# edge.
function _collect_drawn_nodes(head::ListNode, ox::Int, oy::Int, edges::_ClipEdges,
                              layout::LayoutDirection, early::Bool)
    nodes = ListNode[]
    node = head.prev
    while node !== nothing
        value = node.value
        if !(value isa GraphicsFence)
            push!(nodes, node)
            _is_before_early_start(value, ox, oy, edges, layout, early) && break
        end
        node = node.prev
    end
    node = head
    while node !== nothing
        value = node.value
        if !(value isa GraphicsFence)
            _is_past_early_stop(value, ox, oy, edges, layout, early) && break
            push!(nodes, node)
        end
        node = node.next
    end
    nodes
end

# Clear each node from `node` on, along the `link` field, that was painted and
# that the render no longer reaches. A fence was never painted and is passed. A
# link that is not valid was not read by the render, so nothing past it was
# drawn. True when a node was cleared.
function _clear_left_view_nodes!(res::SdlWindowResources, walk::_DirtyWalk, node, list::UInt,
                                 link::Symbol)::Bool
    cleared = false
    while node !== nothing
        if _clear_left_view!(res, walk, _make_placement_key(node, list))
            cleared = true
        elseif !(getfield(node, :value)[] isa GraphicsFence)
            break
        end
        next = getfield(node, link)
        is_cell_valid(next) || break
        node = next[]
    end
    cleared
end

# Walk a `ListNode`-backed element list the same way `_render_canvas!` does
# (prev links, then next links, with the layout early-stop), visiting only the
# nodes the renderer would draw. A change confined to one node's value is a
# per-node dirty unit (one edited line stays tight, with old∪new bounds so a
# shrinking line clears its tail), and so is a node new to the screen. A spine
# change (line inserted/removed), or a `reflow` the caller asks for, reflows
# everything below it, so the dirty region is extended down to the viewport
# bottom — which also clears a removed last line's vacated pixels. The nodes that
# were painted and that the render no longer reaches have their places cleared.
function _collect_listnode_dirty!(res::SdlWindowResources, head::ListNode, key::UInt,
                                  ox::Int, oy::Int, edges::_ClipEdges,
                                  layout::LayoutDirection, early::Bool, walk::_DirtyWalk;
                                  reflow::Bool = false)::Bool
    # (node, its key, its value, whether the value or a leaf value's cells are stale)
    visited = Tuple{ListNode,UInt,Any,Bool}[]
    spine_dirty = reflow
    visit!(node, elem, vstale) = push!(visited, (node, _make_placement_key(node, key), elem,
                                                 vstale || (_is_leaf_graphic(elem) && _node_dirty(elem))))

    # Prev links (negative offsets): process, then early-stop (as in render).
    pcell = getfield(head, :prev)
    is_cell_valid(pcell) || (spine_dirty = true)
    node = pcell[]
    above = nothing                        # the first node the render does not reach back
    while node !== nothing
        vcell = getfield(node, :value)
        vstale = !is_cell_valid(vcell)
        elem = vcell[]
        pc = getfield(node, :prev)
        if !(elem isa GraphicsFence)
            visit!(node, elem, vstale)
            if _is_before_early_start(elem, ox, oy, edges, layout, early)
                above = is_cell_valid(pc) ? pc[] : nothing
                break
            end
        end
        is_cell_valid(pc) || (spine_dirty = true)
        node = pc[]
    end

    # Next links from head: early-stop, then process (as in render). A leaf value
    # is tested before the early-stop reads its place.
    node = head
    below = nothing                        # the first node the render does not reach forward
    while node !== nothing
        vcell = getfield(node, :value)
        vstale = !is_cell_valid(vcell)
        elem = vcell[]
        if !(elem isa GraphicsFence)
            leaf_dirty = _is_leaf_graphic(elem) && _node_dirty(elem)
            if _is_past_early_stop(elem, ox, oy, edges, layout, early)
                below = node
                break
            end
            push!(visited, (node, _make_placement_key(node, key), elem, vstale || leaf_dirty))
        end
        nc = getfield(node, :next)
        is_cell_valid(nc) || (spine_dirty = true)
        node = nc[]
    end

    changed = _clear_left_view_nodes!(res, walk, above, key, :prev)
    changed |= _clear_left_view_nodes!(res, walk, below, key, :next)

    if spine_dirty
        changed = _defer!(walk, () -> begin
            wb = _DirtyAcc()
            for (n, nkey, val, _) in visited
                old = get(res.dirty_bounds, nkey, nothing)
                old === nothing || _acc_extend!(wb, old)
                b = _record_painted_node!(res, n, val, key, ox, oy, edges)
                b === nothing || _acc_extend!(wb, b)
            end
            _acc_empty(wb) && return
            # Reflow runs to the viewport bottom (vertical) / right (horizontal).
            bottom = layout == layout_horizontal ? wb.maxy : max(wb.maxy, edges.bottom)
            right  = layout == layout_horizontal ? max(wb.maxx, edges.right) : wb.maxx
            _add_dirty_rect!(walk.region, (wb.minx, wb.miny, right, bottom))
        end)
    else
        for (n, nkey, val, stale) in visited
            if stale || !_is_painted(res, nkey)
                changed = _union_unit!(res, walk, nkey,
                                       () -> _record_painted_node!(res, n, val, key, ox, oy, edges))
            else
                value_key = _make_placement_key(val, nkey)
                # Something changed inside the value: the node's record follows it.
                _collect_dirty_elem!(res, val, value_key, ox, oy, edges, walk, false) &&
                    (changed = _defer_refresh!(walk, () ->
                        _record_bounds!(res, nkey, get(res.dirty_bounds, value_key, nothing))))
            end
        end
    end
    changed || return false
    # The bounds of the list are those of the nodes it draws, so a list that
    # moves or leaves the view clears them.
    _defer_refresh!(walk, () -> begin
        drawn = _DirtyAcc()
        for (_, nkey, _, _) in visited
            b = get(res.dirty_bounds, nkey, nothing)
            b === nothing || _acc_extend!(drawn, b)
        end
        _record_bounds!(res, key, _acc_tuple_or_nothing(drawn))
    end)
end

# ── The guards ──
#
# A guard is a computed cell for one painted canvas that reads what the walk
# tests for the elements that the render draws there: the element list, the slot
# of each element, every field cell of a leaf (as `_node_dirty` tests them), the
# place of a nested canvas, the geometry of a viewport, and the guard of each
# canvas inside. A write of any of them makes the guard not valid, and so the
# guard of each canvas around it. While a guard is valid and its canvas keeps its
# place, nothing that the canvas draws changed, and the walk skips the canvas. A
# guard reads only the elements between the edges, so it reads no more of a list
# than the render draws.
#
# A canvas drawn at another place, or between other edges, draws other elements,
# so it gets a new guard; the old one has no reader left, and a cell keeps its
# readers only by weak references.

# Whether the guard of the canvas at `key` is valid for the place `(ox, oy, edges)`.
function _is_guard_valid(res::SdlWindowResources, key::UInt, ox::Int, oy::Int, edges::_ClipEdges)
    guard = get(res.painted.guards, key, nothing)
    guard === nothing && return false
    get(res.painted.guard_places, key, nothing) == (ox, oy, edges) || return false
    is_cell_valid(guard)
end

# Read the guard of `canvas` at `key` for the place `(ox, oy, edges)`, and make it
# first when the canvas has none for that place. A guard reads its place when it
# computes, so a move keeps the cell of a guard whose reads stay the same and
# moves its place (`_record_moved_canvas_bounds!`).
function _read_guard!(res::SdlWindowResources, canvas::GraphicsCanvas, key::UInt, ox::Int, oy::Int,
                      edges::_ClipEdges)
    place = (ox, oy, edges)
    guard = get(res.painted.guards, key, nothing)
    if guard === nothing || get(res.painted.guard_places, key, nothing) != place
        res.painted.guard_places[key] = place
        guard = Cell(Computation(function ()
            (x, y, at) = get(res.painted.guard_places, key, place)
            _read_guarded_cells(res, canvas, key, x, y, at)
        end))
        res.painted.guards[key] = guard
        res.painted.new_guards += 1
    end
    guard[]
    nothing
end

# The reads of the guard of `canvas` at `key`: the elements between the edges, as
# the render takes them.
function _read_guarded_cells(res::SdlWindowResources, canvas::GraphicsCanvas, key::UInt, ox::Int, oy::Int,
                             edges::_ClipEdges)
    elements = canvas.elements
    layout = canvas.layout
    early = _is_early_stop_layout(canvas)
    if elements isa ListNode
        early || return nothing
        for node in _collect_drawn_nodes(elements, ox, oy, edges, layout, early)
            node_key = _make_placement_key(node, key)
            value = node.value
            _read_guarded_element(res, value, _make_placement_key(value, node_key), ox, oy, edges)
        end
        return nothing
    end
    slots = elements isa CellVector ? getfield(elements, :elements)[] : elements
    for i in _compute_first_drawn_index(canvas, ox, oy, edges):length(slots)
        slot = slots[i]
        elem = slot isa AbstractCell ? slot[] : slot
        elem isa GraphicsFence && continue
        _is_past_early_stop(elem, ox, oy, edges, layout, early) && break
        _read_guarded_element(res, elem, _make_placement_key(elem, key), ox, oy, edges)
    end
    nothing
end

# The reads of one element at the content origin `(ox, oy)`, as the walk tests it.
function _read_guarded_element(res::SdlWindowResources, elem, key::UInt, ox::Int, oy::Int,
                               edges::_ClipEdges)
    if elem isa GraphicsCanvas
        _read_guard!(res, elem, key, ox + Int(elem.x), oy + Int(elem.y), edges)
    elseif elem isa GraphicsViewport
        box, content, transform = _get_viewport_geometry(elem, ox, oy)
        cox, coy, cedges = _compute_viewport_content_place(box, content, transform)
        _read_guard!(res, content, _make_placement_key(content, key), cox, coy, cedges)
    elseif !(elem isa GraphicsFence)
        for name in fieldnames(typeof(elem))
            (is_view_state_field(name) || name === :prev || name === :next) && continue
            field = getfield(elem, name)
            field isa Cell && field[]
        end
    end
    nothing
end

# The parts of `box` that a copy of its pixels by `offset` gives no pixels for: the
# band at each edge that the content moved away from.
function _compute_move_strips(box::NTuple{4,Int}, offset::NTuple{2,Int})
    (x0, y0, x1, y1) = box
    (dx, dy) = offset
    strips = NTuple{4,Int}[]
    dy > 0 && push!(strips, (x0, y0, x1, y0 + dy))
    dy < 0 && push!(strips, (x0, y1 + dy, x1, y1))
    dx > 0 && push!(strips, (x0, y0, x0 + dx, y1))
    dx < 0 && push!(strips, (x1 + dx, y0, x1, y1))
    strips
end

# True when the box of `move` can be copied in the window of `res`: it covers a
# pixel, no outer viewport and no edge of the window cut it, so its edges are the
# edges that the recording tested, the offset is less than its size, and the
# guard of the content is still valid after the recordings, which read the
# graphics that came into view. The device pixel ratio must be a whole number. A
# text rasterizes at that ratio and is scaled by the supersample, and at another
# ratio the edge of a rectangle can cut it off the grid of its texels, which the
# software renderer of SDL then samples on another grid.
function _is_copyable_move(move::_ContentMove, res::SdlWindowResources)
    (x0, y0, x1, y1) = move.box
    (dx, dy) = move.offset
    isinteger(res.ratio) && !_is_empty_box(move.box) && move.box == move.clip &&
        abs(dx) < x1 - x0 && abs(dy) < y1 - y0 && is_cell_valid(move.guard)
end

# The moves in groups whose boxes overlap, each move in one group.
function _group_overlapping_moves(moves::Vector{_ContentMove})
    groups = Vector{_ContentMove}[]
    for move in moves
        joined = [group for group in groups if any(m -> _has_overlap(m.box, move.box), group)]
        filter!(group -> !any(j -> j === group, joined), groups)
        push!(groups, vcat(joined..., [move]))
    end
    groups
end

# Settle the moves of `walk` after its recordings, and answer the boxes to copy,
# each with its offset. Each box is cut to the window. A move that cannot be
# copied paints its box. The moves whose boxes overlap form a group, which is
# copied as the box of its largest move when that box holds the others and all of
# them have one offset; any other group paints its boxes. A box that is painted is
# a change like any other, so it joins the region before a copied group takes the
# rectangles from outside the contents.
#
# A copied group gives the region what the copy cannot give: the strips of each
# box; for each move inside the largest one, the band that its box covers after
# the copy and did not cover before; the bounds of the graphics that came into
# view or left it, cut to their box; and, cut to the box and moved by the offset,
# each rectangle of the region from outside the contents, where a graphic changed
# that the copy moves. `_collect_cover_rects!` adds the graphics outside the
# contents that the copy moves.
function _settle_content_moves!(res::SdlWindowResources, canvas::GraphicsCanvas, walk::_DirtyWalk)
    window = (0, 0, res.width, res.height)
    moves = _ContentMove[]
    for move in walk.moves
        move.box = _intersect_boxes(move.box, window)
        _is_copyable_move(move, res) ? push!(moves, move) : _add_dirty_rect!(walk.region, move.box)
    end
    groups = Tuple{_ContentMove,Vector{_ContentMove}}[]
    for group in _group_overlapping_moves(moves)
        top = group[argmax([(m.box[3] - m.box[1]) * (m.box[4] - m.box[2]) for m in group])]
        if all(m -> m.offset == top.offset && _is_rect_covered(m.box, top.box), group)
            push!(groups, (top, group))
        else
            foreach(m -> _add_dirty_rect!(walk.region, m.box), group)
        end
    end
    outside = copy(walk.region.rects)
    copies = Tuple{NTuple{4,Int},NTuple{2,Int}}[]
    for (top, group) in groups
        rects = _compute_move_strips(top.box, top.offset)
        nested = Dict{UInt,_ContentMove}(m.key => m for m in group if m !== top)
        for move in values(nested)
            append!(rects, _compute_move_strips(move.box, move.offset))
            band = _compute_move_strips(_move_box(move.box, move.offset), (-move.offset[1], -move.offset[2]))
            append!(rects, (_intersect_boxes(b, top.box) for b in band))
        end
        for move in group, r in move.rects
            push!(rects, _intersect_boxes(r, move.box))
        end
        for r in outside
            _has_overlap(r, top.box) &&
                push!(rects, _intersect_boxes(_move_box(_intersect_boxes(r, top.box), top.offset), top.box))
        end
        _collect_cover_rects!(rects, res, canvas, top, nested)
        foreach(r -> _add_dirty_rect!(walk.region, r), _merge_edge_rects(rects, top.box, top.offset))
        push!(copies, (top.box, top.offset))
    end
    copies
end

# The rectangles of a copied box `box`, merged into one band for each edge line
# that they cross: the edges of the box across the move, and the same edges moved
# by `offset`. Each token of a row that an edge cuts gives a rectangle, and a band
# paints the row once, where the rectangles would paint it once for each one that
# meets it. A band is kept only where it is at most a quarter of the box thick along
# the move, so a tall line across an edge does not stretch it over the box.
function _merge_edge_rects(rects::Vector{NTuple{4,Int}}, box::NTuple{4,Int}, offset::NTuple{2,Int})
    (dx, dy) = offset
    lines = Tuple{Int,Int}[]   # (axis, place): 2 for a row, 1 for a column
    dy == 0 || append!(lines, ((2, box[2]), (2, box[4]), (2, box[2] + dy), (2, box[4] + dy)))
    dx == 0 || append!(lines, ((1, box[1]), (1, box[3]), (1, box[1] + dx), (1, box[3] + dx)))
    groups = [NTuple{4,Int}[] for _ in lines]
    merged = NTuple{4,Int}[]
    for r in rects
        _is_empty_box(r) && continue
        line = findfirst(((axis, place),) -> r[axis] <= place <= r[axis + 2], lines)
        line === nothing ? push!(merged, r) : push!(groups[line], r)
    end
    for (group, (axis, _)) in zip(groups, lines)
        isempty(group) && continue
        band = (minimum(r[1] for r in group), minimum(r[2] for r in group),
                maximum(r[3] for r in group), maximum(r[4] for r in group))
        thin = 4 * (band[axis + 2] - band[axis]) <= box[axis + 2] - box[axis]
        thin ? push!(merged, band) : append!(merged, group)
    end
    merged
end

# Add to `rects` what a copy of the box of `move` makes wrong in the graphics that
# are not in its content. The copy moves their pixels too, so each one whose
# record, widened by the pad, meets the box gives that place and the place that
# the copy moved it to, cut to the box. The walk goes down from the window by the
# records, as a partial paint does. A rectangle gives only its border and the edges
# of its fill (`_add_rect_cover_rects!`), and a viewport in `nested`, whose content
# moved by the same offset, gives its own strips in `_settle_content_moves!`.
function _collect_cover_rects!(rects::Vector{NTuple{4,Int}}, res::SdlWindowResources,
                               canvas::GraphicsCanvas, move::_ContentMove, nested::Dict{UInt,_ContentMove})
    _collect_cover_canvas!(rects, res, canvas, _make_placement_key(canvas, UInt(0)), 0, 0,
                           _ClipEdges(0, 0, res.width, res.height), move, nested)
end

function _collect_cover_canvas!(rects::Vector{NTuple{4,Int}}, res::SdlWindowResources,
                                canvas::GraphicsCanvas, key::UInt, ox::Int, oy::Int, edges::_ClipEdges,
                                move::_ContentMove, nested::Dict{UInt,_ContentMove})
    elements = canvas.elements
    layout = canvas.layout
    early = _is_early_stop_layout(canvas)
    if elements isa ListNode
        early || return nothing
        for node in _collect_drawn_nodes(elements, ox, oy, edges, layout, early)
            value = node.value
            _collect_cover_element!(rects, res, value, _make_placement_key(value, _make_placement_key(node, key)),
                                    ox, oy, edges, move, nested)
        end
        return nothing
    end
    for i in _compute_first_drawn_index(canvas, ox, oy, edges):length(elements)
        elem = elements[i]
        elem isa GraphicsFence && continue
        _is_past_early_stop(elem, ox, oy, edges, layout, early) && break
        _collect_cover_element!(rects, res, elem, _make_placement_key(elem, key), ox, oy, edges, move, nested)
    end
    nothing
end

function _collect_cover_element!(rects::Vector{NTuple{4,Int}}, res::SdlWindowResources, elem, key::UInt,
                                 ox::Int, oy::Int, edges::_ClipEdges, move::_ContentMove,
                                 nested::Dict{UInt,_ContentMove})
    (key == move.key || haskey(nested, key)) && return nothing
    record = get(res.dirty_bounds, key, nothing)
    record === nothing && return nothing
    pad = _DIRTY_RECT_PAD
    padded = (record[1] - pad, record[2] - pad, record[3] + pad, record[4] + pad)
    _has_overlap(padded, move.box) || return nothing
    if elem isa GraphicsCanvas
        return _collect_cover_canvas!(rects, res, elem, key, ox + Int(elem.x), oy + Int(elem.y), edges,
                                      move, nested)
    elseif elem isa GraphicsViewport
        box, content, transform = _get_viewport_geometry(elem, ox, oy)
        if _is_plain_viewport_transform(transform)
            cox, coy, cedges = _compute_viewport_content_place(box, content, transform)
            return _collect_cover_canvas!(rects, res, content, _make_placement_key(content, key), cox, coy,
                                          cedges, move, nested)
        end
    elseif elem isa GraphicsRect
        return _add_rect_cover_rects!(rects, elem, ox, oy, record, move)
    end
    cut = _intersect_boxes(padded, move.box)
    push!(rects, cut, _intersect_boxes(_move_box(cut, move.offset), move.box))
    nothing
end

# A rectangle outside the content of a move, with the record `record`; it draws
# nothing outside its box. Where a part of it has one colour along the move, the
# copy keeps that part and only its ends change, the part minus the part moved by
# the offset and back (`_add_move_ends!`): the fill, inside the border and the
# corners, and, for a move up or down, the left and the right band of the border.
# Any other band, which holds a corner, gives its place and the place that the copy
# moved it to (`_add_moved_place!`). Each is cut to the box. A focus ring, with no
# fill, so gives its top and bottom band and the ends of its sides.
function _add_rect_cover_rects!(rects::Vector{NTuple{4,Int}}, elem::GraphicsRect, ox::Int, oy::Int,
                                record::NTuple{4,Int}, move::_ContentMove)
    x, y = ox + Int(elem.x), oy + Int(elem.y)
    border = elem.border_color.alpha == 0 ? 0 : Int(elem.border_width)
    inset = border + max(Int(elem.radius_tl), Int(elem.radius_tr), Int(elem.radius_br), Int(elem.radius_bl))
    inner = (x + inset, y + inset, x + Int(elem.w) - inset, y + Int(elem.h) - inset)
    _is_empty_box(inner) && return _add_moved_place!(rects, record, move)
    _add_moved_place!(rects, (record[1], record[2], record[3], inner[2]), move)
    _add_moved_place!(rects, (record[1], inner[4], record[3], record[4]), move)
    for side in ((record[1], inner[2], inner[1], inner[4]), (inner[3], inner[2], record[3], inner[4]))
        move.offset[1] == 0 ? _add_move_ends!(rects, side, move) : _add_moved_place!(rects, side, move)
    end
    elem.color.alpha == 0 || _add_move_ends!(rects, inner, move)
    nothing
end

# Add the place of `part`, a part of a graphic outside the content of `move`, and
# the place that the copy moved it to, each cut to the box of the move.
function _add_moved_place!(rects::Vector{NTuple{4,Int}}, part::NTuple{4,Int}, move::_ContentMove)
    cut = _intersect_boxes(part, move.box)
    _is_empty_box(cut) && return nothing
    push!(rects, cut, _intersect_boxes(_move_box(cut, move.offset), move.box))
    nothing
end

# Add the ends of `part`, a part with one colour along the move of `move`: the part
# minus the part moved by the offset, and the part moved by the offset minus the
# part, each cut to the box of the move. Every other pixel of the box has the
# colour of the part, or not, on both sides of the move.
function _add_move_ends!(rects::Vector{NTuple{4,Int}}, part::NTuple{4,Int}, move::_ContentMove)
    _is_empty_box(part) && return nothing
    back = (-move.offset[1], -move.offset[2])
    for strip in vcat(_compute_move_strips(part, move.offset), _compute_move_strips(_move_box(part, move.offset), back))
        push!(rects, _intersect_boxes(strip, move.box))
    end
    nothing
end

# Compute what changed in `canvas` (the whole window content): the walk, the new
# element lists it queued, the recordings it deferred, the clips of the viewports
# (see `_DirtyWalk`) and the moves. Answer the dirty region, and the boxes whose
# pixels a paint copies first, each with the offset of its content. Each
# rectangle is clamped to the window and padded a couple of logical pixels so
# anti-aliased glyph edges straddling the clip boundary are not clipped. The
# region is empty when nothing changed. Recording what was painted is a side
# effect, so this is also called (its answer ignored) on the first full paint to
# seed each unit's previous bounds and each graphic's place.
function _compute_dirty_change(res::SdlWindowResources, canvas::GraphicsCanvas)
    res.painted.recordings = 0
    res.painted.new_guards = 0
    walk = _DirtyWalk()
    root = _make_placement_key(canvas, UInt(0))
    edges = _ClipEdges(0, 0, res.width, res.height)
    _collect_canvas_dirty!(res, canvas, root, 0, 0, edges, walk)
    i = 0
    while i < length(walk.lists)
        i += 1
        walk.lists[i]()
    end
    foreach(record -> record(), walk.deferred)
    foreach(clip -> clip(), walk.clips)
    res.painted.visits = walk.visits[]
    moves = _settle_content_moves!(res, canvas, walk)
    # The guards read after every recording, as a recording does, so no read
    # computes a cell that the walk had still to test. A guard that throws stays
    # not valid, and the walk enters its canvas; the paint meets the same fault.
    try
        _read_guard!(res, canvas, root, 0, 0, edges)
    catch exception
        is_fault_exception(exception) || rethrow()
    end
    pad = _DIRTY_RECT_PAD
    padded = _DirtyRegion()
    for r in walk.region.rects
        _add_dirty_rect!(padded, (clamp(r[1] - pad, 0, res.width), clamp(r[2] - pad, 0, res.height),
                                  clamp(r[3] + pad, 0, res.width), clamp(r[4] + pad, 0, res.height)))
    end
    _extend_over_scaled_viewports!(padded, res)
    (padded.rects, moves)
end

# The dirty region of `canvas`, as `_compute_dirty_change` finds it.
_compute_dirty_region(res::SdlWindowResources, canvas::GraphicsCanvas) =
    first(_compute_dirty_change(res, canvas))

# The smallest rectangle that covers the dirty region, or `nothing` when nothing
# changed: the size of a frame's repaint in one number, for a log or a test.
function _compute_dirty_rect(res::SdlWindowResources, canvas::GraphicsCanvas)
    rects = _compute_dirty_region(res, canvas)
    isempty(rects) && return nothing
    (minimum(r[1] for r in rects), minimum(r[2] for r in rects),
     maximum(r[3] for r in rects), maximum(r[4] for r in rects))
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

# ── Painting a dirty region ──────────────────────────────────────────────

# Each rectangle of a region is painted with its own clip. Its paint looks up the
# record of each graphic that it meets on its way down from the window, and it
# draws only the graphics whose records meet the rectangle. Past this many, the
# region is painted as the one rectangle that covers it. A paragraph that grows
# by a line gives two rectangles for itself and two for each paragraph below it
# that moves.
const _DIRTY_RECT_LIMIT = 32

# The walk widens each rectangle of a region by this many pixels on each side, so
# the anti-aliased edge of a glyph at the border of a rectangle is not cut. A
# partial paint widens a record by the same pad before it skips a graphic, so a
# graphic that draws up to the pad past its record still draws.
const _DIRTY_RECT_PAD = 2

function _limit_dirty_rects(rects::Vector{NTuple{4,Int}})
    length(rects) <= _DIRTY_RECT_LIMIT && return rects
    [(minimum(r[1] for r in rects), minimum(r[2] for r in rects),
      maximum(r[3] for r in rects), maximum(r[4] for r in rects))]
end

_to_sdl_rect(r::NTuple{4,Int}) = SDL_Rect(Int32(r[1]), Int32(r[2]), Int32(r[3] - r[1]), Int32(r[4] - r[2]))

# Repaint the `rects` of `canvas` into the current target of `renderer`, each
# under its own clip. Not SDL_RenderClear: it ignores the clip rect and would
# wipe the retained pixels outside the dirty region, so the background of each
# rect is filled by hand.
#
# With the `records` of the dirty walk, the paint of each rect skips the graphics
# whose records miss it, and the answer is the `_PartialPaint`, whose `drawn`
# counts the leaves drawn. With none, each rect draws the whole canvas, as a full
# paint must not depend on the walk, and the answer is `nothing`.
function _paint_dirty_rects!(renderer::Ptr{SDL_Renderer}, canvas::GraphicsCanvas,
                             rects::Vector{NTuple{4,Int}}, bg::NTuple{4,UInt8},
                             width::Int, height::Int, ratio::Float64;
                             records::Union{Nothing,Dict{UInt,NTuple{4,Int}}} = nothing)
    paint = records === nothing ? nothing : _PartialPaint(records, (0, 0, 0, 0), 0)
    key = _make_render_key(paint, canvas, UInt(0))
    # The clip and the background of a rect cover the same device pixels, as a
    # viewport reads them (`_render_viewport!`).
    scale_x, scale_y = _get_render_scale(renderer)
    for r in rects
        clip = Ref(_make_device_rect(r[1], r[2], r[3], r[4], scale_x, scale_y))
        SDL_RenderSetScale(renderer, 1.0f0, 1.0f0)
        SDL_RenderSetClipRect(renderer, clip)
        SDL_SetRenderDrawColor(renderer, bg[1], bg[2], bg[3], bg[4])
        SDL_RenderFillRect(renderer, clip)
        SDL_RenderSetScale(renderer, Cfloat(scale_x), Cfloat(scale_y))
        paint === nothing || (paint.rect = r)
        _render_canvas!(renderer, canvas, 0, 0, _ClipEdges(0, 0, width, height), ratio; paint, key)
    end
    SDL_RenderSetClipRect(renderer, C_NULL)
    paint
end

# ── The copy of a box whose content moved ──
#
# A move is the box of a viewport whose content only moved since the last paint.
# The pixels of the content that stay in the box are in the kept pixels already,
# `offset` logical pixels from where they belong, so the paint copies them there
# before it paints the rectangles.

# The part of `box` whose pixels stay in the box after a move by `offset`, where
# they are before the copy.
_get_kept_box(box::NTuple{4,Int}, offset::NTuple{2,Int}) =
    (max(box[1], box[1] - offset[1]), max(box[2], box[2] - offset[2]),
     min(box[3], box[3] - offset[1]), min(box[4], box[4] - offset[2]))

# The scratch texture of the window of `res`, at least `width` × `height` device
# pixels, made again when it is smaller. False when SDL can not make one.
function _ensure_scratch_texture!(res::SdlWindowResources, width::Int, height::Int)::Bool
    if res.scratch != C_NULL
        held_width, held_height = Ref{Cint}(0), Ref{Cint}(0)
        SDL_QueryTexture(res.scratch, C_NULL, C_NULL, held_width, held_height)
        held_width[] >= width && held_height[] >= height && return true
        width, height = max(width, Int(held_width[])), max(height, Int(held_height[]))
        SDL_DestroyTexture(res.scratch)
    end
    res.scratch = SDL_CreateTexture(res.renderer, UInt32(SDL_PIXELFORMAT_RGBA8888),
                                    Int32(SDL_TEXTUREACCESS_TARGET), Int32(width), Int32(height))
    res.scratch != C_NULL
end

# Copy the pixels that stay in `box` by `offset` logical pixels, in the kept target
# of the window of `res`, through its scratch texture. The copy runs in device
# pixels, at the scale 1, with no clip, and it blends nothing. The window is left
# with its kept target as the target of its renderer. False when there is no
# scratch texture, and then nothing is copied.
function _copy_target_box!(res::SdlWindowResources, box::NTuple{4,Int}, offset::NTuple{2,Int})::Bool
    kept = _get_kept_box(box, offset)
    _is_empty_box(kept) && return true
    factor = res.ratio * res.ss
    source = _make_device_rect(kept..., factor, factor)
    _ensure_scratch_texture!(res, Int(source.w), Int(source.h)) || return false
    whole = SDL_Rect(0, 0, source.w, source.h)
    moved = SDL_Rect(source.x + round(Int32, offset[1] * factor), source.y + round(Int32, offset[2] * factor),
                     source.w, source.h)
    renderer = res.renderer
    blend = Ref{SDL_BlendMode}(SDL_BLENDMODE_NONE)
    SDL_GetTextureBlendMode(res.target, blend)
    SDL_SetTextureBlendMode(res.target, SDL_BLENDMODE_NONE)
    SDL_SetTextureBlendMode(res.scratch, SDL_BLENDMODE_NONE)
    SDL_SetRenderTarget(renderer, res.scratch)
    SDL_RenderSetScale(renderer, 1.0f0, 1.0f0)
    SDL_RenderSetClipRect(renderer, C_NULL)
    SDL_RenderCopy(renderer, res.target, Ref(source), Ref(whole))
    SDL_SetRenderTarget(renderer, res.target)
    SDL_RenderSetScale(renderer, 1.0f0, 1.0f0)
    SDL_RenderSetClipRect(renderer, C_NULL)
    SDL_RenderCopy(renderer, res.scratch, Ref(whole), Ref(moved))
    SDL_SetTextureBlendMode(res.target, blend[])
    true
end

# Copy the pixels that stay in `box` by `offset` logical pixels, in the surface of
# the offscreen renderer `off`, whose paint state is `res`. The renderer draws what
# it holds back first, and then each row moves in place. False when the copy
# would reach past the surface, and then nothing is copied.
function _copy_surface_box!(off, res::SdlWindowResources, box::NTuple{4,Int}, offset::NTuple{2,Int})::Bool
    kept = _get_kept_box(box, offset)
    _is_empty_box(kept) && return true
    factor = res.ratio * res.ss
    source = _make_device_rect(kept..., factor, factor)
    dx, dy = round(Int, offset[1] * factor), round(Int, offset[2] * factor)
    surface = unsafe_load(off.surface)
    x, y, w, h = Int(source.x), Int(source.y), Int(source.w), Int(source.h)
    (min(x, x + dx) >= 0 && min(y, y + dy) >= 0 &&
     max(x, x + dx) + w <= surface.w && max(y, y + dy) + h <= surface.h) || return false
    SDL_RenderFlush(off.renderer)
    pitch = Int(surface.pitch)
    pixels = Ptr{UInt8}(surface.pixels)
    for row in (dy > 0 ? (h - 1:-1:0) : (0:h - 1))
        from = pixels + (y + row) * pitch + x * 4
        unsafe_copyto!(from + dy * pitch + dx * 4, from, w * 4)
    end
    true
end

# Copy each box of `moves` that no rectangle of `rects` covers, with
# `copy(box, offset)`, and answer the boxes that it copied. A box that `copy`
# cannot copy goes into `rects`, so the paint draws it.
function _copy_moved_boxes!(copy::Function, rects::Vector{NTuple{4,Int}}, moves)
    copied = NTuple{4,Int}[]
    for (box, offset) in moves
        any(r -> _is_rect_covered(box, r), rects) && continue
        copy(box, offset) ? push!(copied, box) : push!(rects, box)
    end
    copied
end

# Outline the union of `rects` in red, `thickness` logical pixels wide, inside
# it: rects that overlap or touch are outlined as one shape, with no line inside.
function _outline_dirty_rects!(renderer::Ptr{SDL_Renderer}, rects, thickness::Int)
    SDL_SetRenderDrawColor(renderer, 0xff, 0x00, 0x00, 0xff)
    for bar in _compute_union_outline(rects, thickness)
        SDL_RenderFillRect(renderer, Ref(_to_sdl_rect(bar)))
    end
    nothing
end

# The outline of the union of `rects` (each `(x0, y0, x1, y1)`, covering the
# pixels x0 ≤ x < x1 and y0 ≤ y < y1), as bars `thickness` pixels wide on the
# inside of its boundary. An edge of a rect is kept only where the pixels just
# beyond it are outside every rect: the top edge where the row above is not
# covered, the right edge where the column after it is not covered, and so on.
function _compute_union_outline(rects, thickness::Int)
    bars = NTuple{4,Int}[]
    t = max(1, thickness)
    for (x0, y0, x1, y1) in rects
        (x1 > x0 && y1 > y0) || continue
        # The spans of the rects that cover the row or the column just beyond an edge.
        across_row(y) = [(q[1], q[3]) for q in rects if q[2] <= y < q[4]]
        across_column(x) = [(q[2], q[4]) for q in rects if q[1] <= x < q[3]]
        for (a, b) in _subtract_spans(x0, x1, across_row(y0 - 1))
            push!(bars, (a, y0, b, min(y1, y0 + t)))
        end
        for (a, b) in _subtract_spans(x0, x1, across_row(y1))
            push!(bars, (a, max(y0, y1 - t), b, y1))
        end
        for (a, b) in _subtract_spans(y0, y1, across_column(x0 - 1))
            push!(bars, (x0, a, min(x1, x0 + t), b))
        end
        for (a, b) in _subtract_spans(y0, y1, across_column(x1))
            push!(bars, (max(x0, x1 - t), a, x1, b))
        end
    end
    bars
end

# The parts of the span `lo ≤ v < hi` that none of `cuts` (each `(a, b)`, a ≤ v < b)
# covers.
function _subtract_spans(lo::Int, hi::Int, cuts)
    parts = Tuple{Int,Int}[]
    start = lo
    for (a, b) in sort(cuts)
        b <= start && continue
        a >= hi && break
        a > start && push!(parts, (start, a))
        start = max(start, b)
        start >= hi && break
    end
    start < hi && push!(parts, (start, hi))
    parts
end

# ── Per-window paint ──────────────────────────────────────────────────────

# Walk `canvas` for what changed since the frame before, and answer the region
# that covers it, empty when nothing changed. The walk seeds `res.dirty_bounds`
# with each unit's current extent, so the *next* edit can clear vacated pixels
# (old∪new). The records of graphics that are gone collect until they are
# forgotten, and a full paint records again what is there.
function _walk_window_change!(res::SdlWindowResources, canvas::GraphicsCanvas)
    if _is_painted_geometry_full(res)
        _forget_painted_geometry!(res)
        res.first_paint = true
    end
    change = _compute_dirty_change(res, canvas)
    # A walk with no records paints the whole window as one unit, so it
    # records everything that is there: the count to measure growth against.
    res.painted.baseline == 0 && (res.painted.baseline = _count_painted_records(res))
    change
end

# Repaint `canvas` into the window, restricting the work to the invalidated
# region when partial rendering is enabled, and answer whether the frame differs
# from the one before, which the backend reports as a `DisplayUpdate`.
# Everything is rendered into the retained `res.target` texture (which keeps its
# pixels across frames); only the dirty rects of that texture are re-rendered,
# then the damaged rects (this frame's and those of the last `buffer age` frames
# — see `damage_history` / `_back_buffer_age`) are copied to the window and
# presented. Copying only the damage instead of the whole target keeps the
# scaled blit proportional to the edit.
#
# The walk runs in both modes: in the partial mode it also names the rects to
# repaint. A full frame repaints and presents the whole window whatever the walk
# found, because the full mode must not depend on the walk to be right.
function _render_window!(backend::SdlBackend, res::SdlWindowResources,
                         canvas::GraphicsCanvas)::Bool
    partial = backend.partial_render
    debug = backend.debug_dirty
    bg = res.bg
    renderer = res.renderer
    scale = Float32(res.ratio)

    if !_ensure_ss_target!(res)
        # No usable retained target — fall back to the classic full repaint
        # straight to the window backbuffer.
        computed, _ = _walk_window_change!(res, canvas)
        changed = res.first_paint || !isempty(computed)
        res.first_paint = false
        SDL_RenderSetScale(renderer, scale, scale)
        SDL_SetRenderDrawColor(renderer, bg[1], bg[2], bg[3], bg[4])
        SDL_RenderClear(renderer)
        _render_canvas!(renderer, canvas, 0, 0, _ClipEdges(0, 0, res.width, res.height), res.ratio)
        SDL_RenderSetScale(renderer, 1.0f0, 1.0f0)
        SDL_RenderPresent(renderer)
        return changed
    end

    # Decide the rectangles to repaint. On the first paint the whole window must
    # be cleared (the target is undefined and margins outside the content have no
    # element to mark them dirty), so the region is the full window, but the
    # walk still runs for its records.
    computed, moves = _walk_window_change!(res, canvas)
    changed = res.first_paint || !isempty(computed)
    if !partial || res.first_paint
        rects = [(0, 0, res.width, res.height)]
        records = nothing
    else
        isempty(computed) && return false   # nothing invalidated — skip paint/present
        rects = _limit_dirty_rects(computed)
        records = res.dirty_bounds
    end
    res.first_paint = false

    rss = Float32(res.ss) * scale
    SDL_SetRenderTarget(renderer, res.target)
    # The pixels that stay in the box of a move go to their new place first. A full
    # paint covers each box, so it copies nothing.
    copied = _copy_moved_boxes!((box, offset) -> _copy_target_box!(res, box, offset), rects, moves)
    SDL_RenderSetScale(renderer, rss, rss)
    _paint_dirty_rects!(renderer, canvas, rects, bg, res.width, res.height, res.ratio; records)
    SDL_RenderSetScale(renderer, 1.0f0, 1.0f0)
    SDL_SetRenderTarget(renderer, C_NULL)

    # Copy only the damaged rects from the retained target to the window
    # back-buffer, rather than the whole (supersampled) target, so the scaled
    # blit tracks the edit instead of the window. The back-buffer we just rendered
    # into was last presented `age` frames ago (EGL/GLX buffer age, queried now
    # that the window framebuffer is current), so to bring it current we re-copy
    # every frame's damage since then — the rects of the last `age` frames.
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
        damage = _DirtyRegion()
        foreach(r -> _add_dirty_rect!(damage, r), rects)
        foreach(r -> _add_dirty_rect!(damage, r), copied)
        for i in 1:(age - 1), r in res.damage_history[i]
            _add_dirty_rect!(damage, r)
        end
        for r in damage.rects
            src = Ref(SDL_Rect(round(Int32, r[1] * rss), round(Int32, r[2] * rss),
                               round(Int32, (r[3] - r[1]) * rss), round(Int32, (r[4] - r[2]) * rss)))
            dst = Ref(SDL_Rect(round(Int32, r[1] * scale), round(Int32, r[2] * scale),
                               round(Int32, (r[3] - r[1]) * scale), round(Int32, (r[4] - r[2]) * scale)))
            SDL_RenderCopy(renderer, res.target, src, dst)
        end
    end
    # Record this frame's content damage (most-recent first) for future copies.
    pushfirst!(res.damage_history, vcat(rects, copied))
    length(res.damage_history) > _DAMAGE_HISTORY_CAP && resize!(res.damage_history, _DAMAGE_HISTORY_CAP)

    if debug
        # Outline this frame's repainted rects on the window. The boxes are drawn
        # straight onto the back-buffer (not into `res.target`), so they would
        # ghost across frames; the forced full copy above repaints over the
        # previous frame's outlines, leaving only the current ones visible.
        SDL_RenderSetScale(renderer, scale, scale)
        _outline_dirty_rects!(renderer, _get_held_outline!(backend, res, rects), 1)
        SDL_RenderSetScale(renderer, 1.0f0, 1.0f0)
    end
    SDL_RenderPresent(renderer)
    changed
end

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
# through the generic BackendModule seams without naming ProjecturedSDL, so the
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

"""
    open_offscreen_renderer(width, height; supersample = 2, density = 1) -> renderer

Open an offscreen, `supersample`-oversized software renderer for a logical
`width × height` canvas drawn at export `density`, and answer its handle: the big
surface, its renderer, and the sizing it was built with, `width` and `height`
among them. The saved image is the logical size times `density` (device pixels),
so output stays crisp on HiDPI displays independent of the generating machine.
The content draws at a zoom of 1; [`with_offscreen_zoom`](@ref) gives another.
Pass the handle to [`close_offscreen_renderer`](@ref) at the end.
"""
function open_offscreen_renderer(width::Integer, height::Integer;
                                  supersample::Integer = 2, density::Real = 1)
    # A software renderer on a surface needs no video of SDL, so an offscreen render
    # runs on any thread, such as the thread of a code unit, and with no display.
    TTF_Init()
    S  = max(1, Int(supersample))
    sc = Float64(density)
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
    (surface = surface, renderer = renderer, S = S, sc = sc, out_w = out_w, out_h = out_h,
     width = Int(width), height = Int(height), zoom = 1.0)
end

"""
    with_offscreen_zoom(renderer, zoom) -> renderer

The handle of the same offscreen renderer, with its content drawn at `zoom`, as
a window at that zoom draws it: the content is `width / zoom × height / zoom`
logical pixels, drawn at the density times the zoom, so it fills the same frame
larger. An overlay of a frame, such as a pointer, still draws at the density of
the frame, in its logical pixels.
"""
with_offscreen_zoom(off, zoom::Real) = merge(off, (; zoom = Float64(zoom)))

# The logical size of the content of `off` at its zoom, and the scale that the
# glyphs of the content rasterize at.
_get_offscreen_content_size(off) = (round(Int, off.width / off.zoom), round(Int, off.height / off.zoom))
_get_offscreen_content_scale(off) = off.sc * off.zoom

# Clear `off` to `background` and render `canvas` (logical size `width × height`)
# into it, at the zoom of `off`. The glyphs rasterize at the device size for the
# export density `off.sc` times the zoom, which is the scale of the renderer.
function _render_canvas_offscreen!(off, canvas::GraphicsCanvas, width::Integer,
                                   height::Integer, background::NTuple{4,UInt8})
    scale = _get_offscreen_content_scale(off)
    SDL_RenderSetScale(off.renderer, Float32(scale * off.S), Float32(scale * off.S))
    r, g, b, a = background
    SDL_SetRenderDrawColor(off.renderer, r, g, b, a)
    SDL_RenderClear(off.renderer)
    _render_canvas!(off.renderer, canvas, 0, 0, _ClipEdges(0, 0, Int(width), Int(height)), scale)
    nothing
end

# Render `overlay` over the picture of `off`, in the logical pixels of the frame
# and at the density of the frame, whatever the zoom of the content.
function _render_overlay_offscreen!(off, overlay::GraphicsCanvas)
    SDL_RenderSetScale(off.renderer, Float32(off.sc * off.S), Float32(off.sc * off.S))
    _render_canvas!(off.renderer, overlay, 0, 0, _ClipEdges(0, 0, off.width, off.height), off.sc)
    nothing
end

# The surface to save: the box-downsampled output when supersampling (a fresh
# surface the caller must `SDL_FreeSurface`), or the big surface itself when not
# (do not free it separately — `close_offscreen_renderer` owns it).
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

"""
    close_offscreen_renderer(renderer) -> nothing

Free the surface and the renderer that [`open_offscreen_renderer`](@ref) opened.
"""
function close_offscreen_renderer(off)
    _evict_renderer_textures!(off.renderer)
    SDL_DestroyRenderer(off.renderer)
    SDL_FreeSurface(off.surface)
    nothing
end

"""
    write_image(canvas::GraphicsCanvas, filename::AbstractString;
                width::Integer = 800, height::Integer = 600,
                background::NTuple{4,UInt8} = (0xf9, 0xf9, 0xfb, 0xff)) -> ImageFile

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
                     background::NTuple{4,UInt8} = (0xf9, 0xf9, 0xfb, 0xff),
                     supersample::Integer = 2,
                     density::Real = 1)
    off = open_offscreen_renderer(width, height; supersample=supersample, density=density)
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
        close_offscreen_renderer(off)
    end
    ImageFile(filename)
end

# ── Content bounds ──────────────────────────────────────────────────────
#
# `write_image` sizes an image to the bounds of what SDL draws
# (`_bounds_of_canvas`), at the density that the glyphs rasterize at.

# The bounds of what SDL draws for `canvas` at `ratio`, from the origin of the
# canvas: `(minx, miny, maxx, maxy)`, all 0 for an empty canvas.
function _get_drawn_content_bounds(canvas::GraphicsCanvas, ratio::Float64)
    bounds = _bounds_of_canvas(canvas, 0, 0, ratio)
    bounds === nothing ? (0, 0, 0, 0) : bounds
end

"""
    write_image(document, projection, filename::AbstractString;
                width=nothing, height=nothing,
                max_width::Integer = 1200, max_height::Integer = 800,
                background::NTuple{4,UInt8} = (0xf9, 0xf9, 0xfb, 0xff)) -> ImageFile

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
    TextToGraphics(measure = FontFileMeasure()),
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
                     background::NTuple{4,UInt8} = (0xf9, 0xf9, 0xfb, 0xff),
                     supersample::Integer = 2,
                     density::Real = 1)
    # Initialize before printing: the projection measures text (opening fonts),
    # which requires SDL_ttf to be up. The render needs no video of SDL.
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
    # `_get_drawn_content_bounds` returns (minx, miny, maxx, maxy). The natural size
    # must span the full extent — including any content at negative coordinates —
    # so subtract a negative min rather than dropping it.
    minx, miny, maxx, maxy = _get_drawn_content_bounds(canvas, Float64(density))
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
        minx, miny, maxx, maxy = _get_drawn_content_bounds(canvas, Float64(density))
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
                background=background, supersample=supersample, density=density)
end

"""
    GraphicsCanvasToImageFile(filename; width=800, height=600,
                               background=(0xf9,0xf9,0xfb,0xff))

Printer-only projection. On `print_document` it renders the input
`GraphicsCanvas` offscreen and saves to `filename` (BMP). The `output` field
of the returned `SimpleIoMap` is an `ImageFile` document. Has no reader.

```julia
proj = ChainingProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure = FontFileMeasure()),
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
                                    background = (0xf9, 0xf9, 0xfb, 0xff))
    GraphicsCanvasToImageFile(String(filename), Int(width), Int(height),
                               NTuple{4,UInt8}(background))
end

function print_document(p::GraphicsCanvasToImageFile,
                           recursion, canvas::GraphicsCanvas, ctx)
    output = write_image(canvas, p.filename;
                         width=p.width, height=p.height, background=p.background)
    SimpleIoMap(p, canvas, output)
end

function map_reference_forward(
        ::GraphicsCanvasToImageFile, iomap, reference)
    nothing
end

function map_reference_backward(
        ::GraphicsCanvasToImageFile, iomap, reference)
    nothing
end

# ════════════════════════════════════════════════════════════════════════
# Offscreen frame emission — the rendering primitive for headless video.
# (`record_video` itself lives in the opt-in `ProjecturedVideo` package, which
#  pulls FFMPEG; this package exports the offscreen primitives it builds on.)
# ════════════════════════════════════════════════════════════════════════


"""
    write_offscreen_frames!(renderer, canvas; background, folder, frame, count = 1,
                            overlay = nothing) -> nothing

Render `canvas` once at the zoom of `renderer`, with `overlay` (a canvas, or
`nothing`) over it at the density of the frame, and write it as `count`
identical frames, the state held on screen for `count` frames of video time,
into `folder` as `frame_000001.png` and on, advancing the counter `frame`.
"""
function write_offscreen_frames!(off, canvas::GraphicsCanvas; background::NTuple{4,UInt8},
                                 folder::AbstractString, frame::Ref{Int}, count::Integer = 1,
                                 overlay::Union{GraphicsCanvas,Nothing} = nothing)
    count <= 0 && return nothing
    _render_canvas_offscreen!(off, canvas, _get_offscreen_content_size(off)..., background)
    overlay === nothing || _render_overlay_offscreen!(off, overlay)
    out_surface = _offscreen_output_surface(off)
    try
        for _ in 1:count
            frame[] += 1
            # PNG (lossless, compressed) rather than raw BMP: UI frames are mostly
            # flat colour and compress ~10-50x, so the frame pile stays small
            # instead of filling the disk quota on a long high-resolution recording.
            fn = joinpath(folder, "frame_$(lpad(frame[], 6, '0')).png")
            IMG_SavePNG(out_surface, fn) == 0 ||
                error("write_offscreen_frames!: IMG_SavePNG failed for $fn: $(unsafe_string(SDL_GetError()))")
        end
    finally
        out_surface !== off.surface && SDL_FreeSurface(out_surface)
    end
    nothing
end


# What a partial paint into an offscreen renderer keeps from frame to frame: the
# records of the dirty walk, in a resource record with no window, and the rects
# of the last frame that repainted something. The outline of those rects stays
# on each frame until the next repaint, as a window keeps its last picture.
mutable struct _OffscreenPaintState
    res::SdlWindowResources
    last_rects::Vector{NTuple{4,Int}}    # the rectangles of the last frame that painted
    last_copies::Vector{NTuple{4,Int}}   # the boxes whose pixels the last frame copied
    last_drawn::Int                      # the leaves that the last frame drew, or -1 in a full paint
end

"""
    make_offscreen_paint_state(renderer) -> state

What a partial paint into `renderer` keeps from frame to frame, for
[`render_offscreen_changes!`](@ref), at the zoom of `renderer`: a renderer at
another zoom needs a new one.
"""
function make_offscreen_paint_state(off)
    width, height = _get_offscreen_content_size(off)
    res = SdlWindowResources(C_NULL, off.renderer, :offscreen, UInt32(0), "",
                             width, height, 0, 0, :default, (0x00, 0x00, 0x00, 0xff),
                             off.S, _get_offscreen_content_scale(off), 1.0, C_NULL, 0, 0, true,
                             Dict{UInt,NTuple{4,Int}}(), _PaintedGeometry(), Vector{NTuple{4,Int}}[],
                             C_NULL)
    _OffscreenPaintState(res, NTuple{4,Int}[], NTuple{4,Int}[], 0)
end

"""
    render_offscreen_changes!(renderer, state, canvas; background) -> rects

Render `canvas` into `renderer` as a window with `partial_render` does: the
surface keeps its pixels, the pixels that stay in the box of a viewport whose
content only moved are copied to their new place, and only the rects that the
dirty walk finds are painted again. The first frame paints everything. Answers
the rects painted, empty when nothing changed. The state keeps the boxes copied
and the leaves drawn of the last frame, and the rects of the last frame that
painted.
"""
function render_offscreen_changes!(off, state::_OffscreenPaintState, canvas::GraphicsCanvas;
                                   background::NTuple{4,UInt8})
    res = state.res
    if _is_painted_geometry_full(res)
        _forget_painted_geometry!(res)
        res.first_paint = true
    end
    computed, moves = _compute_dirty_change(res, canvas)
    res.painted.baseline == 0 && (res.painted.baseline = _count_painted_records(res))
    rects = res.first_paint ? [(0, 0, res.width, res.height)] : _limit_dirty_rects(computed)
    records = res.first_paint ? nothing : res.dirty_bounds
    res.first_paint = false
    state.last_copies = NTuple{4,Int}[]
    state.last_drawn = 0
    isempty(rects) && return rects
    state.last_rects = rects
    state.last_copies = _copy_moved_boxes!((box, offset) -> _copy_surface_box!(off, res, box, offset), rects, moves)
    scale = _get_offscreen_content_scale(off)
    SDL_RenderSetScale(off.renderer, Float32(scale * off.S), Float32(scale * off.S))
    paint = _paint_dirty_rects!(off.renderer, canvas, rects, background, res.width, res.height, scale; records)
    state.last_drawn = paint === nothing ? -1 : paint.drawn
    rects
end

"""
    write_offscreen_frame_with_overlay!(renderer, overlay; outline, folder, frame) -> nothing

Write the picture of `renderer` as the next frame into `folder`, with `overlay`
(a canvas, or `nothing`) drawn over it and the red outline of the rects
`outline` around it, advancing the counter `frame`. Both go on a copy of the
picture and never into `renderer`, so a partial paint finds the surface as it
left it. The overlay is in the logical pixels of the frame, and the rects are
in those of the content, which the zoom of `renderer` makes larger.
"""
function write_offscreen_frame_with_overlay!(off, overlay; outline::Vector{NTuple{4,Int}},
                                             folder::AbstractString, frame::Ref{Int})
    out = off.S > 1 ? _downsample_surface(off.surface, off.out_w, off.out_h, off.S) :
                      SDL_DuplicateSurface(off.surface)
    try
        if overlay !== nothing || !isempty(outline)
            renderer = SDL_CreateSoftwareRenderer(out)
            SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
            SDL_RenderSetScale(renderer, Float32(off.sc), Float32(off.sc))
            overlay === nothing ||
                _render_canvas!(renderer, overlay, 0, 0, _ClipEdges(0, 0, off.width, off.height), off.sc)
            # Two pixels: a video halves the resolution of its colours, and a
            # line of one pixel fades to a trace.
            zoomed = [ntuple(i -> round(Int, rect[i] * off.zoom), 4) for rect in outline]
            _outline_dirty_rects!(renderer, zoomed, 2)
            SDL_RenderFlush(renderer)
            _evict_renderer_textures!(renderer)
            SDL_DestroyRenderer(renderer)
        end
        frame[] += 1
        fn = joinpath(folder, "frame_$(lpad(frame[], 6, '0')).png")
        IMG_SavePNG(out, fn) == 0 ||
            error("write_offscreen_frame_with_overlay!: IMG_SavePNG failed for $fn: $(unsafe_string(SDL_GetError()))")
    finally
        SDL_FreeSurface(out)
    end
    nothing
end

"""
    write_offscreen_picture_with_overlay!(renderer, picture, overlay; filename) -> nothing

Draw `overlay` over the frame saved in the file `picture` and save the result as
`filename`. The frame has the size of the output of `renderer`, so the overlay
is drawn at the density of the output, as
[`write_offscreen_frame_with_overlay!`](@ref) draws it.
"""
function write_offscreen_picture_with_overlay!(off, picture::AbstractString, overlay::GraphicsCanvas;
                                               filename::AbstractString)
    surface = IMG_Load(picture)
    surface == C_NULL &&
        error("write_offscreen_picture_with_overlay!: failed to load $picture: $(unsafe_string(SDL_GetError()))")
    try
        renderer = SDL_CreateSoftwareRenderer(surface)
        SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
        SDL_RenderSetScale(renderer, Float32(off.sc), Float32(off.sc))
        _render_canvas!(renderer, overlay, 0, 0, _ClipEdges(0, 0, off.width, off.height), off.sc)
        SDL_RenderFlush(renderer)
        _evict_renderer_textures!(renderer)
        SDL_DestroyRenderer(renderer)
        IMG_SavePNG(surface, filename) == 0 ||
            error("write_offscreen_picture_with_overlay!: IMG_SavePNG failed for $filename: $(unsafe_string(SDL_GetError()))")
    finally
        SDL_FreeSurface(surface)
    end
    nothing
end


# ════════════════════════════════════════════════════════════════════════
# Application lifecycle
# ════════════════════════════════════════════════════════════════════════

function BackendModule.initialize_backend!(backend::SdlBackend)
    @assert _start_sdl_video!() "SDL init failed: $(unsafe_string(SDL_GetError()))"
    @assert TTF_Init() == 0 "TTF init failed: $(unsafe_string(SDL_GetError()))"
    SDL_StartTextInput()   # enable SDL_TEXTINPUT events (explicit for portability)
    _detect_display_density!()
    backend.display.density = _PROBED_DISPLAY_DENSITY[]
    # The work area that keeps a popup and a tooltip on the screen. A frame reads
    # it here, and not from SDL and `xrandr`.
    _read_work_areas!(backend)
    # Start with no input owed: a backend that is opened again must not answer
    # with an event left over from its last life.
    empty!(backend.pending_inputs)
    backend.pending_motion = nothing
    backend.modifiers = _current_modifiers()
    # The wake event, registered once per SDL life. `SDL_RegisterEvents`
    # answers `(Cuint)-1` when the pool is exhausted; the wait then degrades
    # to its timeout slices and nothing else is lost.
    registered = SDL_RegisterEvents(Int32(1))
    backend.wake_event_type = registered == typemax(UInt32) ? UInt32(0) : registered
    nothing
end

function BackendModule.quit_backend!(backend::SdlBackend)
    empty!(backend.pending_inputs)
    backend.pending_motion = nothing
    SDL_StopTextInput()
    # Free cached textures while their renderers are still alive (before SDL_Quit).
    _clear_text_texture_cache!()
    _free_shape_cursors!(backend)
    empty!(backend.drawn_canvases)
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

# ── A window that never takes the key focus ─────────────────────────────
#
# SDL on Cocoa makes each window that it shows the key window, and its class
# `SDLWindow` answers YES when AppKit asks whether a window can become the key or
# the main window. A tooltip that takes the key focus takes it from the window
# under it: SDL then reports a leave of that window, and AppKit uses the next
# click on it only to make it key again.
#
# So the backend answers the two questions itself, on the class `SDLWindow`, once
# a process: NO for a window that carries the mark below, and the answer of SDL
# for every other window. The mark is an associated object of the window, so it
# goes away with the window. The class of a window stays as it is: SDL observes the
# `visible` key of each window, and that observation already gave each window a
# class of its own.

# The subsystems of `SDL_SysWMinfo` that the backend reads, and the size of the
# struct: the version in 3 bytes and the subsystem, then a union of 64 bytes. The
# binding has no type for it, so the backend reads it by offset.
const _SDL_SYSWM_X11 = 2
const _SDL_SYSWM_COCOA = 4
const _SDL_SYSWMINFO_SIZE = 72

# The windowing subsystem of `win`, and the first handle of the union: the
# `NSWindow` on Cocoa, the `Display` on X11. `nothing` when SDL gives no
# information.
function _find_native_window_handle(win::Ptr{SDL_Window})
    buffer = zeros(UInt8, _SDL_SYSWMINFO_SIZE)
    version = Ref{SDL_version}()
    SDL_GetVersion(version)
    buffer[1], buffer[2], buffer[3] = version[].major, version[].minor, version[].patch
    answered, subsystem, handle = GC.@preserve buffer begin
        (@ccall(LibSDL2.libsdl2.SDL_GetWindowWMInfo(win::Ptr{SDL_Window},
                                                    pointer(buffer)::Ptr{UInt8})::Cint),
         unsafe_load(Ptr{Cint}(pointer(buffer, 5))),
         unsafe_load(Ptr{Ptr{Cvoid}}(pointer(buffer, 9))))
    end
    answered == 0 ? nothing : (subsystem = Int(subsystem), handle = handle)
end

# The name of the selector whose address is the mark, both its key and its value.
const _NEVER_KEY_WINDOW_MARK = "projecturedNeverKeyWindow"

# The methods of `SDLWindow` that the answer replaced, by their selectors: empty
# until the answer is in place.
const _REPLACED_KEY_WINDOW_METHODS = Dict{Ptr{Cvoid},Ptr{Cvoid}}()

_get_selector(name::AbstractString) =
    ccall((:sel_registerName, _LIBOBJC), Ptr{Cvoid}, (Cstring,), name)

# The answer to `canBecomeKeyWindow` and `canBecomeMainWindow` of an `SDLWindow`:
# NO for a marked window, and the answer of SDL for any other. AppKit asks on the
# main thread. `BOOL` is one byte on arm64 and on x86_64.
function _answer_key_window_question(window::Ptr{Cvoid}, selector::Ptr{Cvoid})::UInt8
    mark = _get_selector(_NEVER_KEY_WINDOW_MARK)
    ccall((:objc_getAssociatedObject, _LIBOBJC), Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}),
          window, mark) == C_NULL || return 0x00
    original = get(_REPLACED_KEY_WINDOW_METHODS, selector, C_NULL)
    original == C_NULL && return 0x01
    ccall(original, UInt8, (Ptr{Cvoid}, Ptr{Cvoid}), window, selector)
end

# Put the answer above in place of the two methods of `SDLWindow`, once a process.
# Answers whether it is in place.
function _install_key_window_answer!()
    isempty(_REPLACED_KEY_WINDOW_METHODS) || return true
    class = ccall((:objc_getClass, _LIBOBJC), Ptr{Cvoid}, (Cstring,), "SDLWindow")
    class == C_NULL && return false
    answer = @cfunction(_answer_key_window_question, UInt8, (Ptr{Cvoid}, Ptr{Cvoid}))
    for name in ("canBecomeKeyWindow", "canBecomeMainWindow")
        selector = _get_selector(name)
        method = ccall((:class_getInstanceMethod, _LIBOBJC), Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}),
                       class, selector)
        types = ccall((:method_getTypeEncoding, _LIBOBJC), Ptr{Cchar}, (Ptr{Cvoid},), method)
        _REPLACED_KEY_WINDOW_METHODS[selector] =
            ccall((:class_replaceMethod, _LIBOBJC), Ptr{Cvoid},
                  (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cchar}), class, selector, answer, types)
    end
    true
end

# Mark the window `win` so that it never takes the key focus: SDL shows it in
# front, and the key focus stays in the window that has it. A window that is not
# a window of Cocoa needs no mark, and gets none.
function _refuse_key_focus!(win::Ptr{SDL_Window})
    found = _find_native_window_handle(win)
    (found === nothing || found.subsystem != _SDL_SYSWM_COCOA || found.handle == C_NULL) &&
        return nothing
    _install_key_window_answer!() || return nothing
    mark = _get_selector(_NEVER_KEY_WINDOW_MARK)
    # OBJC_ASSOCIATION_ASSIGN (0): the value is the mark itself, and it is not retained.
    ccall((:objc_setAssociatedObject, _LIBOBJC), Cvoid,
          (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Csize_t), found.handle, mark, mark, 0)
    nothing
end

# ════════════════════════════════════════════════════════════════════════
# Device I/O
# ════════════════════════════════════════════════════════════════════════

# How long one wait slice blocks this thread in SDL. The cooperative tasks of
# this thread — the MCP server, the assistant, the turn of an agent with its
# HTTP servers — run only between slices, so the slice is the 10 ms cadence the
# polling loop had, with any number of threads.
const _WAIT_SLICE_SECONDS = 0.01

# A wait of at most this long, as between the frames of an animation or before
# a feed that is due soon, waits in Julia and not in SDL, so the tasks of this
# thread and their I/O run for the whole wait.
const _JULIA_WAIT_LIMIT_SECONDS = 0.1

# One step of a wait in Julia: the step of the timers of libuv. An input event
# ends the wait within one step.
const _JULIA_WAIT_STEP_SECONDS = 0.001

# The longest wait before the read that a frame which changed the display owes:
# one frame of an animation, 30 frames a second.
const _DISPLAY_UPDATE_WAIT_SECONDS = 1 / 30

# Block until the SDL queue holds an event or `milliseconds` pass, without
# removing anything: the NULL event pointer is SDL's look-only form, so
# everything stays queued for `run_read_stage!`. Must run on the thread that
# initialized the video subsystem — it pumps events.
#
# The wait calls SDL directly: the generated LibSDL2 wrapper carries no `gc_safe`
# option, and a collection on another thread must not stall behind a blocked
# wait. The call names `LibSDL2.libsdl2`, which the JLL sets when it loads, so the
# library is found at run time. A constant keeps the path of the build machine,
# and a bundle then waits on a second SDL that has no window and no events.
_wait_for_queued_event(milliseconds::Integer) =
    (@ccall gc_safe=true LibSDL2.libsdl2.SDL_WaitEventTimeout(
        C_NULL::Ptr{Cvoid}, Cint(milliseconds)::Cint)::Cint) == 1

# Whether the SDL queue holds an event, without a wait and without removing
# anything: `SDL_PollEvent` with no event pumps the events of the window system
# and looks. Must run on the thread that initialized the video subsystem.
_has_queued_event() = (@ccall LibSDL2.libsdl2.SDL_PollEvent(C_NULL::Ptr{Cvoid})::Cint) == 1

"""
    wait_for_input(backend::SdlBackend, devices, timeout_seconds) -> Nothing

Block until the SDL queue holds an event, [`wake_backend!`](@ref) pushes the
wake event, or `timeout_seconds` passes. The queue is only looked at, never
read: everything stays for `run_read_stage!`. An event this backend already owes
(`pending_inputs`) ends the wait before it starts, the read that a changed display
owes (`display_updates`) comes within 1/30 s, and a held motion sample
caps the timeout at the rest of its rate-limit interval, so the last sample
of a pointer that stopped is delivered on time.

A wait of at most 0.1 s, as between the frames of an animation, waits in
Julia: it looks at the queue, and sleeps 1 ms between the looks, so the
cooperative tasks of this thread and their I/O run for the whole wait, and an
input event ends it within 1 ms. A longer wait, as when nothing animates, blocks
in SDL in GC-safe slices of 10 ms with a `yield` between them, so an input event
ends it at once.
"""
function BackendModule.wait_for_input(backend::SdlBackend, devices, timeout_seconds)
    isempty(backend.pending_inputs) || return nothing
    backend.system_colors_change === nothing || return nothing
    timeout = Float64(timeout_seconds)
    # The read that a changed display owes comes within one frame of an
    # animation, and not at once: an animation changes the display in each
    # frame, and a read at once would draw the frames back to back, with no
    # turn for the tasks of this thread.
    isempty(backend.display_updates) || (timeout = min(timeout, _DISPLAY_UPDATE_WAIT_SECONDS))
    if backend.pending_motion !== nothing
        remaining = _HOVER_MOTION_INTERVAL - (time() - backend.last_hover_motion)
        remaining <= 0 && return nothing
        timeout = min(timeout, remaining)
    end
    deadline = time() + timeout                       # Inf stays Inf
    if timeout <= _JULIA_WAIT_LIMIT_SECONDS
        while time() < deadline
            _has_queued_event() && return nothing
            sleep(_JULIA_WAIT_STEP_SECONDS)           # the cooperative tasks' turn, with their I/O
        end
        return nothing
    end
    while true
        this_slice = min(_WAIT_SLICE_SECONDS, deadline - time())
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
    take_from_devices!(backend::SdlBackend, devices) -> WindowInput or nothing

Poll the SDL event queue once and return an `WindowInput` wrapping a
backend-agnostic inner event, with the time that SDL stamped on it:
- `SDL_QUIT`                           → `WindowInput(:none, WindowQuit(; time))`
- `SDL_WINDOWEVENT_CLOSE` for a window → `WindowInput(<id>, WindowClose(; time))`
- `SDL_WINDOWEVENT_RESIZED`            → `WindowInput(<id>, WindowResize(w, h; time))`
- `SDL_KEYDOWN`                        → `WindowInput(<id>, KeyDown)` (Escape included)
  and, for Return, keypad Enter and Tab, the `KeyPress` of `'\\n'` or `'\\t'` after it
- `SDL_KEYUP`                          → `WindowInput(<id>, KeyUp)`
- `SDL_TEXTINPUT`                      → `WindowInput(<id>, KeyPress)`
- `SDL_MOUSEBUTTONDOWN`                → `WindowInput(<id>, MouseDown)`
- `SDL_MOUSEBUTTONUP`                  → `WindowInput(<id>, MouseUp)`
- `SDL_MOUSEMOTION`                    → `WindowInput(<id>, MouseMove)` (coalesced)
- `SDL_MOUSEWHEEL`                     → `WindowInput(<id>, MouseScroll)`
- a change of the colour settings of the system, which a query found after
  `SDL_WINDOWEVENT_FOCUS_GAINED`, → `WindowInput(:none, SystemColorsChange)`

`<id>` is the `WindowDocument.id` of the originating window (looked up
in `backend.window_ids`), or `:none` if the SDL event carries no window
id or refers to a window the backend does not track.

The backend emits only raw events; the `MouseClick` click is synthesised from
the `MouseDown`/`MouseUp` pair by the gesture tracking projection, not here.

## Pointer motion is coalesced

A pointer reports its position far more often than a frame can act on one, so a
poll finds a run of motion events queued. Only the newest of them says where the
pointer *is*; the older ones say where it was. This call collapses such a run and
answers with the newest sample, rather than answering with the oldest and
leaving the newer ones for a later call to discard — which is what made the
highlight trail the pointer by a frame.

Order is preserved. An event that is not motion ends the run: the held motion is
answered first and the other event is kept in `backend.pending_inputs` for the
next call, so a click never overtakes the motion that led to it.

A run of wheel events of one window with the same modifiers is merged the same
way, into one `MouseScroll` with the sum of the turns and the position and the
time of the newest. Any other event ends it, so the order stays.

Idle motion (no button held) is still rate-limited to one sample per
`_HOVER_MOTION_INTERVAL`. A blocked sample is *held* in
`backend.pending_motion`, not dropped: a pointer that stops sends nothing more,
and dropping its last sample would leave the highlight one step behind for as
long as the pointer rests there. A held sample is answered anyway when another
event waits behind it, because order outranks the rate limit.

The move that `write_to_devices!` queues after a frame that changed a window waits
as a motion sample too, after the `DisplayUpdate` of that frame.
"""
function BackendModule.take_from_devices!(backend::SdlBackend, devices)
    # What a previous call owes: the event that ended a motion run, and the
    # `KeyPress` of a Return or a Tab.
    isempty(backend.pending_inputs) || return _take_wheel_run!(backend, popfirst!(backend.pending_inputs))
    # A window that showed a changed frame: the readers find their part of the
    # view again before they read the input that came after it.
    isempty(backend.display_updates) || return popfirst!(backend.display_updates)
    # A change of the colour settings of the system, which a query found.
    change = backend.system_colors_change
    change === nothing || (backend.system_colors_change = nothing; return change)
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
        motion === nothing && return _take_wheel_run!(backend, other)
        # Before the `KeyPress` that the poll of `other` owes.
        pushfirst!(backend.pending_inputs, other)
        return motion
    end
    motion === nothing && return nothing
    # The shape of the pointer follows the motion at once, before the rate limit.
    motion.event isa MouseMove &&
        _update_pointer_shape!(backend, motion.window_id, motion.event.x, motion.event.y)
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

# `input`, with the wheel events of the same window and the same modifiers that
# come right after it on the queue added to it. A fast turn puts many notches on
# the queue. Without the merge each takes a frame of its own, and a slow frame
# keeps the view behind the wheel. The merged event holds the sum of the turns,
# and the position and the time of the newest. Any other event ends the run and
# waits for the next call, so the order stays. Nothing merges while an older
# input or the update of a frame waits.
function _take_wheel_run!(backend::SdlBackend, input)
    (input isa WindowInput && input.event isa MouseScroll) || return input
    while isempty(backend.pending_inputs) && isempty(backend.display_updates) &&
          backend.pending_motion === nothing
        other, newer = _poll_window_input(backend)
        if newer !== nothing
            backend.pending_motion = newer
            break
        end
        other === nothing && break
        if other isa WindowInput && other.window_id == input.window_id &&
           other.event isa MouseScroll && other.event.modifiers == input.event.modifiers
            input = WindowInput(input.window_id, _merge_wheel_events(input.event, other.event))
            continue
        end
        # Before the `KeyPress` that the poll of `other` owes.
        pushfirst!(backend.pending_inputs, other)
        break
    end
    input
end

# One wheel event for `older` and `newer`: the sum of their turns, whole and with
# their fractions, at the position and the time of `newer`.
_merge_wheel_events(older::MouseScroll, newer::MouseScroll) =
    MouseScroll(older.dx + newer.dx, older.dy + newer.dy, newer.x, newer.y, newer.modifiers;
                time = newer.time, precise_dx = older.precise_dx + newer.precise_dx,
                precise_dy = older.precise_dy + newer.precise_dy)

"""
    _poll_window_input(backend) -> (other, motion)

Pop SDL events until one of them surfaces as a `WindowInput`, and answer a pair
in which exactly one member is non-`nothing`: `motion` for a `MouseMove`,
`other` for every other input. An SDL event the backend does not surface (a
window event it ignores, a text input that maps to no key, a button with no name)
is skipped here, so `(nothing, nothing)` means the queue is empty and nothing else.

`take_from_devices!` runs it in a loop and keeps only the newest motion.
"""
function _poll_window_input(backend::SdlBackend)
    # SDL reports window units; the events hold logical pixels. Each event converts
    # with the window unit ratio of its own window.
    event_ref = Ref{SDL_Event}()
    while Bool(SDL_PollEvent(event_ref))
        evt = event_ref[]
        t = evt.type
        event_time = _get_sdl_event_time(evt.common.timestamp)

        if t == SDL_QUIT
            return (WindowInput(:none, WindowQuit(; time = event_time)), nothing)

        elseif t == SDL_DISPLAYEVENT
            # A monitor came or went: the work area and the area of each display
            # are read again. The editor gets no input for it.
            _read_work_areas!(backend)
            continue

        elseif t == 0x00000200  # SDL_WINDOWEVENT
            # event byte 1 = SDL_WindowEventID
            sub = evt.window.event
            wid = _lookup_window_id(backend, evt.window.windowID)
            # Named, not numbered: the focus a window gains (12) and the focus it
            # loses (13) are one number apart.
            if sub == UInt8(SDL_WINDOWEVENT_CLOSE)
                return (WindowInput(wid, WindowClose(; time = event_time)), nothing)
            elseif sub == UInt8(SDL_WINDOWEVENT_FOCUS_LOST)
                return (WindowInput(wid, WindowDefocus(; time = event_time)), nothing)
            elseif sub == UInt8(SDL_WINDOWEVENT_FOCUS_GAINED)
                # A person can change the colour settings of the system in another
                # window, so the backend asks again. A change comes later, as a
                # `SystemColorsChange`.
                _start_system_colors_query!(backend)
                continue
            elseif sub == UInt8(SDL_WINDOWEVENT_LEAVE)
                return (WindowInput(wid, WindowLeave(; time = event_time)), nothing)
            elseif sub == UInt8(SDL_WINDOWEVENT_RESIZED)  # external/user only
                # SDL reports window units; the document works in logical pixels.
                unit_ratio = _get_window_unit_ratio(backend, wid)
                nw = _to_logical(Int(evt.window.data1), unit_ratio)
                nh = _to_logical(Int(evt.window.data2), unit_ratio)
                # Mark the resource as already at this size so the reconciler's
                # _update_window_geometry! doesn't issue a redundant
                # SDL_SetWindowSize back at the OS (which would fight the drag).
                res = get(backend.windows, wid, nothing)
                if res !== nothing
                    res.width = nw
                    res.height = nh
                end
                return (WindowInput(wid, WindowResize(nw, nh;
                                                      time = event_time)), nothing)
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
            backend.modifiers = sdl_modifiers(evt.key.keysym.mod)
            keydown = sdl_to_keydown(keysym, evt.key.keysym.mod, is_repeat;
                                     time = event_time)
            # SDL gives no `SDL_TEXTINPUT` for Return and Tab: their `KeyPress` is
            # owed after the `KeyDown`, at each down and each repeat.
            char = find_typed_character(keydown.key)
            char === nothing ||
                push!(backend.pending_inputs,
                      WindowInput(wid, KeyPress(char, string(char), keydown.modifiers, keydown.time)))
            return (WindowInput(wid, keydown), nothing)

        elseif t == 0x00000301  # SDL_KEYUP
            wid = _lookup_window_id(backend, evt.key.windowID)
            backend.modifiers = sdl_modifiers(evt.key.keysym.mod)
            keyup = sdl_to_keyup(evt.key.keysym.sym, evt.key.keysym.mod;
                                 time = event_time)
            return (WindowInput(wid, keyup), nothing)

        elseif t == 0x00000303  # SDL_TEXTINPUT
            kp = sdl_to_keypress(evt; modifiers = backend.modifiers, time = event_time)
            kp === nothing && continue
            wid = _lookup_window_id(backend, evt.text.windowID)
            return (WindowInput(wid, kp), nothing)

        elseif t == 0x00000401  # SDL_MOUSEBUTTONDOWN
            button = _sdl_button_sym(evt.button.button)
            button === nothing && continue    # a button with no name makes no event
            mods = backend.modifiers
            wid = _lookup_window_id(backend, evt.button.windowID)
            unit_ratio = _get_window_unit_ratio(backend, wid)
            x, y = _to_logical(Int(evt.button.x), unit_ratio), _to_logical(Int(evt.button.y), unit_ratio)
            return (WindowInput(wid, MouseDown(button, x, y, mods; time = event_time)),
                    nothing)

        elseif t == 0x00000402  # SDL_MOUSEBUTTONUP
            button = _sdl_button_sym(evt.button.button)
            button === nothing && continue    # a button with no name makes no event
            mods = backend.modifiers
            wid = _lookup_window_id(backend, evt.button.windowID)
            unit_ratio = _get_window_unit_ratio(backend, wid)
            x, y = _to_logical(Int(evt.button.x), unit_ratio), _to_logical(Int(evt.button.y), unit_ratio)
            return (WindowInput(wid, MouseUp(button, x, y, mods; time = event_time)),
                    nothing)

        elseif t == 0x00000400  # SDL_MOUSEMOTION
            buttons = _get_held_mouse_buttons(evt.motion.state)
            mods = backend.modifiers
            wid = _lookup_window_id(backend, evt.motion.windowID)
            unit_ratio = _get_window_unit_ratio(backend, wid)
            # The motion slot of the pair. The caller keeps only the newest of a
            # run of these, and applies the rate limit to what it keeps.
            return (nothing, WindowInput(wid,
                MouseMove(_to_logical(Int(evt.motion.x), unit_ratio),
                          _to_logical(Int(evt.motion.y), unit_ratio), buttons, mods;
                          time = event_time)))

        elseif t == 0x00000403  # SDL_MOUSEWHEEL
            mx_ref, my_ref = Ref{Cint}(0), Ref{Cint}(0)
            SDL_GetMouseState(mx_ref, my_ref)
            mods = backend.modifiers
            wid = _lookup_window_id(backend, evt.wheel.windowID)
            unit_ratio = _get_window_unit_ratio(backend, wid)
            dx, dy = Int(evt.wheel.x), Int(evt.wheel.y)
            # The turn with its fraction, which a touchpad gives. SDL adds the
            # fractions up into the whole notches of `x` and `y`. An SDL that
            # does not fill the fraction leaves 0 beside a whole notch.
            precise_dx, precise_dy = Float64(evt.wheel.preciseX), Float64(evt.wheel.preciseY)
            (precise_dx == 0 && dx != 0) && (precise_dx = Float64(dx))
            (precise_dy == 0 && dy != 0) && (precise_dy = Float64(dy))
            if mods.shift && dx == 0 && precise_dx == 0
                dx, dy = dy, 0
                precise_dx, precise_dy = precise_dy, 0.0
            end
            return (WindowInput(wid,
                MouseScroll(dx, dy, _to_logical(Int(mx_ref[]), unit_ratio),
                            _to_logical(Int(my_ref[]), unit_ratio), mods; time = event_time,
                            precise_dx, precise_dy)),
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

This runs before `write_to_devices!` ever sees a `ScreenDocument`, and it fills
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

# The window's current size in logical pixels. SDL reports window units, which
# is what `WindowDocument` sizes are converted to when the window is created.
function _native_window_size(res::SdlWindowResources)
    w = Ref{Cint}(0); h = Ref{Cint}(0)
    SDL_GetWindowSize(res.win, w, h)
    unit_ratio = _get_window_unit_ratio(res, res.ratio)
    (_to_logical(Int(w[]), unit_ratio), _to_logical(Int(h[]), unit_ratio))
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
    write_to_devices!(backend::SdlBackend, devices, screen::ScreenDocument)

Reconcile live native SDL windows against the projection-output
`ScreenDocument`. Windows whose id no longer appears are destroyed;
new ids cause a window to be opened; existing windows have their
geometry / title / style updated as needed, then repainted with the
matching `WindowDocument.content` canvas.

Each window is drawn at the device pixel ratio of the `Display` of `backend`,
which `configure_devices!` sets. The reconciler does not read `devices`.

A frame that changed a window, and a window that closed, can put another part
under a pointer that does not move. So after such a write the backend queues a
`MouseMove` at the point where the pointer is now, in the window under it, with
the buttons that are held now. The readers read it as any move, and find the part
under the pointer in the new frame. A move to the same point changes no part and
no pixel, so the next frame queues no more.

The backend keeps the canvas of each window, and sets the cursor of the system to
the shape that `find_pointer_shape` finds at the pointer in it: after each frame
here, and at each motion in `take_from_devices!`. It makes the cursor of each shape
once, and sets it only when the shape changes.
"""
function BackendModule.write_to_devices!(backend::SdlBackend, devices::Vector{Device}, screen::ScreenDocument)
    _keep_device_geometry_at_new_zoom!(backend, screen)
    ratio = get_device_pixel_ratio(backend.display)
    desired_ids = Set{Symbol}()
    for w in screen.windows
        w isa WindowDocument || continue
        push!(desired_ids, w.id)
    end

    # Close windows whose document disappeared. A window that closes changes
    # what the pointer is on.
    changed = false
    for id in collect(keys(backend.windows))
        if !(id in desired_ids)
            res = backend.windows[id]
            delete!(backend.window_ids, res.sdl_id)
            _close_native_window!(res)
            delete!(backend.windows, id)
            delete!(backend.recent_repaints, id)
            delete!(backend.drawn_canvases, id)
            changed = true
        end
    end

    # Open / update / paint each desired window.
    for w in screen.windows
        w isa WindowDocument || continue
        canvas = w.content
        canvas isa GraphicsCanvas ||
            error("write_to_devices!: WindowDocument(id=:$(w.id)).content is $(typeof(canvas)), expected GraphicsCanvas")
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
            _adopt_native_position!(res, w, ratio)
            _update_window_geometry!(res, w, ratio)
        end
        if _render_window!(backend, res, canvas)
            _queue_display_update!(backend, w.id)
            changed = true
        end
        backend.drawn_canvases[w.id] = canvas
    end
    changed && _queue_pointer_move!(backend)
    _update_pointer_shape_at_pointer!(backend)
    nothing
end

# Report that window `id` shows a frame that differs from the one before. One
# update for each window waits, with the time of its latest frame.
function _queue_display_update!(backend::SdlBackend, id::Symbol)
    update = WindowInput(id, DisplayUpdate(; time = time()))
    index = findfirst(input -> input.window_id === id, backend.display_updates)
    index === nothing ? push!(backend.display_updates, update) :
                        (backend.display_updates[index] = update)
    nothing
end

# Queue a move at the point where the pointer is now, in the window under it, with
# the buttons that are held now and the modifiers of the last key event read. A
# frame that changed a window can put another part under a pointer that does not
# move, and the readers find it by this move. It waits as a motion sample, so a
# newer motion replaces it. A pointer on no window of this backend gives no move.
function _queue_pointer_move!(backend::SdlBackend)
    id = _find_pointer_window(backend)
    id === nothing && return nothing
    unit_ratio = _get_window_unit_ratio(backend, id)
    x_ref, y_ref = Ref{Cint}(0), Ref{Cint}(0)
    buttons = _get_held_mouse_buttons(UInt32(SDL_GetMouseState(x_ref, y_ref)))
    backend.pending_motion = WindowInput(id,
        MouseMove(_to_logical(Int(x_ref[]), unit_ratio), _to_logical(Int(y_ref[]), unit_ratio),
                  buttons, backend.modifiers; time = time()))
    nothing
end

# The id of the window of this backend that the pointer is on, or `nothing`.
function _find_pointer_window(backend::SdlBackend)
    focus = SDL_GetMouseFocus()
    focus == C_NULL && return nothing
    get(backend.window_ids, UInt32(SDL_GetWindowID(focus)), nothing)
end

# ── The shape of the pointer ───────────────────────────────────────────

# The cursor of the system for each shape that SDL has one for.
const _SYSTEM_CURSOR_OF_SHAPE = Dict{Symbol,SDL_SystemCursor}(
    :arrow                   => SDL_SYSTEM_CURSOR_ARROW,
    :ibeam                   => SDL_SYSTEM_CURSOR_IBEAM,
    :double_arrow_horizontal => SDL_SYSTEM_CURSOR_SIZEWE,
    :double_arrow_vertical   => SDL_SYSTEM_CURSOR_SIZENS,
    :pointing_hand           => SDL_SYSTEM_CURSOR_HAND,
    :crossed_circle          => SDL_SYSTEM_CURSOR_NO,
    :hourglass               => SDL_SYSTEM_CURSOR_WAIT)

# SDL has no open and no closed hand of the system, so the backend makes each from
# the glyph of the Lucide font that shows it: `hand` and `grab`.
const _GLYPH_OF_SHAPE = Dict{Symbol,Char}(:open_hand => Char(0xe1d7), :closed_hand => Char(0xe1e6))

# The size of the glyph of a cursor, in logical pixels.
const _GLYPH_CURSOR_SIZE = 22

# Set the cursor of the system to the shape at the point `(x, y)` of the window
# `id`, in the canvas that the window drew last. A window that drew nothing yet
# changes nothing.
function _update_pointer_shape!(backend::SdlBackend, id::Symbol, x::Int, y::Int)
    canvas = get(backend.drawn_canvases, id, nothing)
    canvas === nothing && return nothing
    _set_pointer_shape!(backend, find_pointer_shape(canvas, x, y))
end

# Set the cursor of the system to the shape at the pointer, in the window under it.
function _update_pointer_shape_at_pointer!(backend::SdlBackend)
    id = _find_pointer_window(backend)
    id === nothing && return nothing
    unit_ratio = _get_window_unit_ratio(backend, id)
    x_ref, y_ref = Ref{Cint}(0), Ref{Cint}(0)
    SDL_GetMouseState(x_ref, y_ref)
    _update_pointer_shape!(backend, id, _to_logical(Int(x_ref[]), unit_ratio),
                           _to_logical(Int(y_ref[]), unit_ratio))
end

# Set the cursor of the system to `shape` when it is another shape than the one
# set last. `:default` and a shape that SDL does not know are the arrow.
function _set_pointer_shape!(backend::SdlBackend, shape::Symbol)
    shape === backend.pointer_shape && return nothing
    cursor = _get_shape_cursor!(backend, shape)
    cursor == C_NULL || SDL_SetCursor(cursor)
    backend.pointer_shape = shape
    nothing
end

# The cursor of `shape`, made the first time that the backend shows it. SDL sizes
# a cursor in window units, so its glyph is drawn at the window unit ratio.
_get_shape_cursor!(backend::SdlBackend, shape::Symbol) =
    get!(backend.cursors, shape) do
        glyph = get(_GLYPH_OF_SHAPE, shape, nothing)
        glyph === nothing ?
            SDL_CreateSystemCursor(get(_SYSTEM_CURSOR_OF_SHAPE, shape, SDL_SYSTEM_CURSOR_ARROW)) :
            _make_glyph_cursor(glyph, _get_window_unit_ratio(get_device_pixel_ratio(backend.display)))
    end

# A cursor that shows `glyph` of the Lucide font in black with a white outline, so
# that it shows on any background, with its hot spot in the middle. The arrow of
# the system when the glyph does not draw.
function _make_glyph_cursor(glyph::Char, ratio::Float64)
    handle = _get_font(with_font_size(StyleFont("Lucide", 20), _GLYPH_CURSOR_SIZE), ratio)  # @style: the cursor of the system, not the look of the editor
    black = _render_glyph(handle, glyph, SDL_Color(0x00, 0x00, 0x00, 0xff))
    white = _render_glyph(handle, glyph, SDL_Color(0xff, 0xff, 0xff, 0xff))
    if black === nothing || white === nothing
        black === nothing || SDL_FreeSurface(black[1])
        white === nothing || SDL_FreeSurface(white[1])
        return SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_ARROW)
    end
    info = unsafe_load(black[1])
    outline = max(1, round(Int, ratio))
    width, height = Int(info.w) + 2 * outline, Int(info.h) + 2 * outline
    image = SDL_CreateRGBSurfaceWithFormat(UInt32(0), Cint(width), Cint(height),
                                           Cint(32), UInt32(SDL_PIXELFORMAT_ARGB8888))
    cursor = Ptr{SDL_Cursor}(C_NULL)
    if image != C_NULL
        SDL_FillRect(image, C_NULL, SDL_MapRGBA(unsafe_load(image).format, 0x00, 0x00, 0x00, 0x00))
        for surface in (white[1], black[1])
            SDL_SetSurfaceBlendMode(surface, SDL_BLENDMODE_BLEND)
        end
        for dx in -outline:outline, dy in -outline:outline
            (dx == 0 && dy == 0) && continue
            SDL_BlitSurface(white[1], C_NULL, image,
                            Ref(SDL_Rect(Cint(outline + dx), Cint(outline + dy), info.w, info.h)))
        end
        SDL_BlitSurface(black[1], C_NULL, image,
                        Ref(SDL_Rect(Cint(outline), Cint(outline), info.w, info.h)))
        cursor = SDL_CreateColorCursor(image, Cint(width ÷ 2), Cint(height ÷ 2))
        SDL_FreeSurface(image)
    end
    SDL_FreeSurface(black[1])
    SDL_FreeSurface(white[1])
    cursor == C_NULL ? SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_ARROW) : cursor
end

# Free every cursor that the backend made, and show the arrow of the system again.
function _free_shape_cursors!(backend::SdlBackend)
    for cursor in values(backend.cursors)
        cursor == C_NULL || SDL_FreeCursor(cursor)
    end
    empty!(backend.cursors)
    backend.pointer_shape = :default
    nothing
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

Keep a window that fits its content on the screen. A window that would cross an
edge of the area of its display is moved inside it. A tooltip that would then
hold the pointer goes to the side of the pointer instead: a tooltip under the
pointer covers the very thing it is about, and the next move of the pointer
closes it. A popup stays under the pointer, because the pointer goes into it to
choose.

A window of a fixed size is left alone, and so is one whose place the backend
chooses ([`is_automatic_window_place`](@ref)).

The areas are the ones that `backend.display_areas` holds, in pixels at the zoom
1, and the place and the size of a window are in logical pixels at the zoom of
the display, so the areas are divided by the zoom. This function runs at each
frame, so it asks SDL and `xrandr` nothing.
"""
function _place_fitted_window!(backend::SdlBackend, w::WindowDocument)
    maximum_size = w.maximum_size
    (maximum_size[1] <= 0 && maximum_size[2] <= 0) && return w
    is_automatic_window_place(w) && return w
    zoom = backend.display.zoom
    areas = [Tuple(round(Int, value / zoom) for value in area) for area in _get_display_areas(backend)]
    (x, y) = compute_window_place(Int(w.x), Int(w.y), Int(w.width), Int(w.height);
                                  areas, pointer = w.style === :tooltip ?
                                                   get_pointer_position(backend) : nothing)
    (w.x == x && w.y == y) && return w
    w.x = x
    w.y = y
    w
end

# The place of a window that the window manager chose. It can put a window
# elsewhere than asked, at the first frame or when a person moves it. The document
# takes that place when it asks for no place of its own, so a popup opens at the
# window and not where the window was first asked to be. SDL gives the place in
# window units, and `ratio` is the device pixel ratio of this frame.
function _adopt_native_position!(res::SdlWindowResources, w::WindowDocument, ratio::Float64)
    x_ref, y_ref = Ref{Cint}(0), Ref{Cint}(0)
    SDL_GetWindowPosition(res.win, x_ref, y_ref)
    unit_ratio = _get_window_unit_ratio(res, ratio)
    x, y = _to_logical(Int(x_ref[]), unit_ratio), _to_logical(Int(y_ref[]), unit_ratio)
    (x == res.x && y == res.y) && return w
    if w.x == res.x && w.y == res.y
        w.x = x
        w.y = y
    end
    res.x = x
    res.y = y
    w
end

# How far a window that had to move stays from the pointer.
const _POINTER_GAP = 8

"""
    compute_window_place(x, y, width, height; areas, pointer) -> (x, y)

Where a window of that size goes: inside the area of the display that holds its
point, and beside `pointer` rather than under it. `areas` are the usable areas of
the displays, each `(x, y, width, height)` in screen coordinates, the main display
first. The point is `pointer`, the pointer in screen coordinates, or the place of
the window when `pointer` is `nothing`; a point on no display takes the first
area.
"""
function compute_window_place(x::Int, y::Int, width::Int, height::Int; areas, pointer)
    point = pointer === nothing ? (x, y) : (Int(pointer[1]), Int(pointer[2]))
    (left, top, area_width, area_height) = _find_display_area(areas, point)
    x + width  > left + area_width  && (x = left + area_width  - width)
    y + height > top + area_height && (y = top + area_height - height)
    x = max(x, left)
    y = max(y, top)
    if pointer !== nothing && x <= pointer[1] < x + width && y <= pointer[2] < y + height
        beside = Int(pointer[1]) - width - _POINTER_GAP
        x = beside >= left ? beside : Int(pointer[1]) + _POINTER_GAP
    end
    (x, y)
end

# The area of `areas` that holds `point`, or the first one when none holds it.
function _find_display_area(areas, point)
    for area in areas
        (area[1] <= point[1] < area[1] + area[3] && area[2] <= point[2] < area[2] + area[4]) &&
            return area
    end
    first(areas)
end

# The usable areas of the displays, or, with one display, the work area of
# `backend.display` at the origin.
_get_display_areas(backend::SdlBackend) =
    isempty(backend.display_areas) ?
        [(0, 0, Int(backend.display.width), Int(backend.display.height))] : backend.display_areas

# Read the work area that `backend.display` holds and the usable area of each
# display. A frame places a popup and a tooltip with them, and asks SDL nothing.
function _read_work_areas!(backend::SdlBackend)
    backend.display.width, backend.display.height = get_sdl_display_size()
    backend.display_areas = _read_display_areas(backend)
    nothing
end

# The usable area of each display, `(x, y, width, height)` in logical pixels at the
# zoom 1, the main display first. With one display there is none: the work area of
# `backend.display` serves, as `get_sdl_display_size` finds it, also where SDL folds
# several monitors of X11 into one display.
function _read_display_areas(backend::SdlBackend)
    count = SDL_GetNumVideoDisplays()
    count <= 1 && return NTuple{4,Int}[]
    unit_ratio = _get_window_unit_ratio(_PROBED_DISPLAY_DENSITY[])
    areas = NTuple{4,Int}[]
    for index in 0:(count - 1)
        rect = Ref(SDL_Rect(Int32(0), Int32(0), Int32(0), Int32(0)))
        SDL_GetDisplayUsableBounds(Int32(index), rect) == 0 || continue
        bounds = rect[]
        (bounds.w > 0 && bounds.h > 0) || continue
        push!(areas, (_to_logical(Int(bounds.x), unit_ratio), _to_logical(Int(bounds.y), unit_ratio),
                      _to_logical(Int(bounds.w), unit_ratio), _to_logical(Int(bounds.h), unit_ratio)))
    end
    areas
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
    # SDL takes window units.
    unit_ratio = _get_window_unit_ratio(res, ratio)
    if w.width != res.width || w.height != res.height || ratio != res.ratio
        SDL_SetWindowSize(res.win, Int32(max(_to_device(w.width, unit_ratio), 1)),
                                   Int32(max(_to_device(w.height, unit_ratio), 1)))
        res.width = Int(w.width)
        res.height = Int(w.height)
        res.ratio = ratio
    end
    if !is_automatic_window_place(w) && (w.x != res.x || w.y != res.y)
        SDL_SetWindowPosition(res.win, _get_native_window_place(w, unit_ratio)...)
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
# The zoom of the display
# ════════════════════════════════════════════════════════════════════════
#
# The zoom of an editor is in its `Appearance`; a step of it writes the `zoom` of
# the `Display` of the editor, which this backend shares. The device pixel ratio
# is the density of the display times its zoom, so a new zoom magnifies every
# pixel. The drawing finds the new zoom.

# Keep the device size and the device place of each window when the zoom changed
# since the last frame: its logical width, height, `x` and `y` change by the old
# zoom over the new one, so the operating system does not resize or move the
# window, and the content lays out for the new logical size, as after a resize by
# the person. The place that the backend last applied changes with it, so no
# window is moved again. Every window then repaints in full, because every pixel
# moves. A change of the density, such as the probe that the first window runs,
# changes no logical size; the next frame takes the place of each window again.
function _keep_device_geometry_at_new_zoom!(backend::SdlBackend, screen::ScreenDocument)
    previous = backend.drawn_zoom
    zoom = Float64(backend.display.zoom)
    backend.drawn_zoom = zoom
    (previous == 0.0 || previous == zoom || !isfinite(previous / zoom)) && return nothing
    factor = previous / zoom
    for w in screen.windows
        w isa WindowDocument || continue
        w.width  = max(1, round(Int, Int(w.width)  * factor))
        w.height = max(1, round(Int, Int(w.height) * factor))
        if !is_automatic_window_place(w)
            w.x, w.y = _scale_place(Int(w.x), Int(w.y), factor)
        end
    end
    for res in values(backend.windows)
        res.x, res.y = _scale_place(res.x, res.y, factor)
        res.first_paint = true
    end
    nothing
end

# A place on the screen at a new zoom. The place that lets the backend choose
# stays as it is.
_scale_place(x::Int, y::Int, factor::Float64) =
    (x, y) == AUTOMATIC_WINDOW_PLACE ? (x, y) : (round(Int, x * factor), round(Int, y * factor))

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
    # A load into a surface needs no video of SDL.
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
BackendModule.get_display_size(::SdlBackend) = get_sdl_display_size()

# Fill the first `Display` in `devices` with the usable size and the density of the
# real display, and draw with it from now on: its `zoom` then steps with
# Ctrl+= and Ctrl+-. The density is the one the probe finds, so the zoom of an
# editor does not reach the `Display` of another. Mouse/Keyboard are left at their
# defaults — SDL2 cannot reliably report button count or keyboard layout.
function BackendModule.configure_devices!(backend::SdlBackend, devices)
    index = findfirst(device -> device isa Display, devices)
    index === nothing && return nothing
    display = devices[index]::Display
    display.width, display.height = get_sdl_display_size()
    display.density = _PROBED_DISPLAY_DENSITY[]
    backend.display = display
    backend.display_areas = _read_display_areas(backend)
    return nothing
end
