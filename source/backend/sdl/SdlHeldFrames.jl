# Fragment of `SdlModule` — the held frames of the SDL backend: what its windows
# show and take while a code unit of the editor runs on a thread of its own.
#
# A held frame pumps the events of the window system, so each window answers it.
# It takes the events out of the queue of SDL, puts the keys and the window events
# back for the frames after the unit, in their order, and drops the pointer input
# of the windows of the backend that starts during the hold; a press from before
# the hold keeps its release. It filters with no lock of SDL held: an event filter
# of SDL runs Julia code under the lock of the queue, and a collection that starts
# there waits for a thread that waits for that lock to push an event. A press
# on the Stop control of the busy bar, or Escape while the bar shows, is the stop;
# the close of a window and the quit of the application are the close. A window
# presents its retained picture again when the window system shows it or changes
# its size, with the busy bar from half a second on.
#
# The bar draws only textures that `prepare_held_frames!` made before the unit
# started, because the unit owns the text state of the backend, its fonts and its
# glyphs, while it runs. A held frame reads no document, and the bar reads no
# theme for the same reason.

# A texture of a word of the bar, and its size in device pixels.
struct _HeldTexture
    texture::Ptr{SDL_Texture}
    width::Cint
    height::Cint
end

# The textures of the busy bar of one window, made by its renderer: the words of
# each part of the unit, the digits and the unit of the time, the two controls,
# the notice that a stop has no effect, and the question whether to quit.
struct _HeldBarTextures
    parts::Vector{_HeldTexture}
    digits::Vector{_HeldTexture}
    seconds::_HeldTexture
    stop::_HeldTexture
    quit::_HeldTexture
    notice::_HeldTexture
    question::_HeldTexture
end

# The state of the held frames of one unit, which the loop reads and writes.
mutable struct _HeldFrames
    textures::Dict{Symbol,_HeldBarTextures}
    window_ids::Set{UInt32}
    wake_event_type::UInt32
    started_ticks::UInt32
    bar_ticks::UInt32                         # 0 before the bar shows
    pressed_before::Set{UInt8}                # the buttons down at the start of the hold
    kept_releases::Set{Tuple{UInt8,UInt32}}   # their releases, by button and time
    is_stop_asked::Bool
    is_quit_confirmed::Bool
    is_escape_eaten::Bool
    closes::Int
    needs_present::Bool
    # The Stop and the Quit control of the bar of each window, in the coordinates
    # of its events: (x0, y0, x1, y1), or nothing where the bar shows none.
    controls::Dict{UInt32,Tuple{Any,Any}}
    shown::Tuple{Int,Int,Bool,Bool}           # the second, the part, the notice and the question shown last
    vsync_off::Set{Symbol}                    # the windows whose vertical sync the hold turned off
    events::Vector{SDL_Event}                 # the buffer that the events of the queue go through
end

# The held frames of each backend that holds them now.
const _HELD_FRAMES = IdDict{SdlBackend,_HeldFrames}()

# The kinds of SDL events that the filter reads, and the offsets of their fields.
const _SDL_QUIT_EVENT = 0x100
const _SDL_WINDOW_EVENT = 0x200
const _SDL_KEY_DOWN_EVENT = 0x300
const _SDL_KEY_UP_EVENT = 0x301
const _SDL_MOUSE_MOTION_EVENT = 0x400
const _SDL_MOUSE_BUTTON_DOWN_EVENT = 0x401
const _SDL_MOUSE_BUTTON_UP_EVENT = 0x402
const _SDL_MOUSE_WHEEL_EVENT = 0x403
const _SDL_WINDOW_CLOSE = 0x0e
const _SDL_WINDOW_SHOWN_AGAIN = (0x03, 0x05, 0x06)   # exposed, resized, size changed
const _SDL_ESCAPE_KEY = Int32(27)

_get_event_kind(event::Ptr{UInt8}) = unsafe_load(Ptr{UInt32}(event))
_get_event_ticks(event::Ptr{UInt8}) = unsafe_load(Ptr{UInt32}(event + 4))
_get_event_window(event::Ptr{UInt8}) = unsafe_load(Ptr{UInt32}(event + 8))

# Take each event out of the queue of SDL, and give back the ones that the hold
# keeps, in their order. A kept event goes through again in the next held frame,
# so each rule gives the same answer the second time.
function _filter_held_events!(held::_HeldFrames)
    events = held.events
    kept = SDL_Event[]
    while true
        count = Int(SDL_PeepEvents(events, Cint(length(events)), SDL_GETEVENT,
                                   SDL_FIRSTEVENT, SDL_LASTEVENT))
        count <= 0 && break
        GC.@preserve events begin
            for index in 1:count
                _is_held_event_kept!(held, Ptr{UInt8}(pointer(events, index))) &&
                    push!(kept, events[index])
            end
        end
        count < length(events) && break
    end
    isempty(kept) || SDL_PeepEvents(kept, Cint(length(kept)), SDL_ADDEVENT,
                                    SDL_FIRSTEVENT, SDL_LASTEVENT)
    nothing
end

const _SDL_POLL_SENTINEL_EVENT = 0x7f00

function _is_held_event_kept!(held::_HeldFrames, event::Ptr{UInt8})
    kind = _get_event_kind(event)
    (kind == held.wake_event_type || kind == _SDL_POLL_SENTINEL_EVENT) && return false
    if kind == _SDL_QUIT_EVENT
        held.closes += 1
        return false
    end
    _get_event_window(event) in held.window_ids || return true
    ticks = _get_event_ticks(event)
    _SDL_MOUSE_MOTION_EVENT <= kind <= _SDL_MOUSE_WHEEL_EVENT &&
        return _is_held_pointer_kept!(held, kind, ticks, event)
    (kind == _SDL_KEY_DOWN_EVENT || kind == _SDL_KEY_UP_EVENT) &&
        return _is_held_key_kept!(held, kind, ticks, event)
    if kind == _SDL_WINDOW_EVENT
        change = unsafe_load(Ptr{UInt8}(event + 12))
        if change == _SDL_WINDOW_CLOSE
            held.closes += 1
            return false
        end
        change in _SDL_WINDOW_SHOWN_AGAIN && (held.needs_present = true)
    end
    true
end

function _is_held_pointer_kept!(held::_HeldFrames, kind::UInt32, ticks::UInt32, event::Ptr{UInt8})
    ticks < held.started_ticks && return true
    button = unsafe_load(Ptr{UInt8}(event + 16))
    if kind == _SDL_MOUSE_BUTTON_UP_EVENT
        (button, ticks) in held.kept_releases && return true
        if button in held.pressed_before
            delete!(held.pressed_before, button)
            push!(held.kept_releases, (button, ticks))
            return true
        end
    elseif kind == _SDL_MOUSE_BUTTON_DOWN_EVENT
        x = Int(unsafe_load(Ptr{Int32}(event + 20)))
        y = Int(unsafe_load(Ptr{Int32}(event + 24)))
        stop, quit = get(held.controls, _get_event_window(event), (nothing, nothing))
        _is_inside(stop, x, y) && (held.is_stop_asked = true)
        _is_inside(quit, x, y) && (held.is_quit_confirmed = true)
    end
    false
end

_is_inside(::Nothing, x, y) = false
_is_inside(box, x, y) = box[1] <= x < box[3] && box[2] <= y < box[4]

function _is_held_key_kept!(held::_HeldFrames, kind::UInt32, ticks::UInt32, event::Ptr{UInt8})
    unsafe_load(Ptr{Int32}(event + 20)) == _SDL_ESCAPE_KEY || return true
    if kind == _SDL_KEY_DOWN_EVENT && held.bar_ticks != 0 && ticks >= held.bar_ticks
        held.is_stop_asked = true
        held.is_escape_eaten = true
        return false
    elseif kind == _SDL_KEY_UP_EVENT && held.is_escape_eaten
        held.is_escape_eaten = false
        return false
    end
    true
end

# ── The protocol ────────────────────────────────────────────────────────────

function BackendModule.prepare_held_frames!(backend::SdlBackend, devices, parts)
    pressed = SDL_GetMouseState(C_NULL, C_NULL)
    held = _HeldFrames(Dict{Symbol,_HeldBarTextures}(), Set{UInt32}(), backend.wake_event_type,
                       SDL_GetTicks(), UInt32(0),
                       Set{UInt8}(UInt8(button) for button in 1:8 if pressed & (UInt32(1) << (button - 1)) != 0),
                       Set{Tuple{UInt8,UInt32}}(), false, false, false, 0, true,
                       Dict{UInt32,Tuple{Any,Any}}(), (-1, 0, false, false), Set{Symbol}(),
                       Vector{SDL_Event}(undef, 64))
    for (id, res) in backend.windows
        push!(held.window_ids, res.sdl_id)
        (res.renderer == C_NULL || res.style in (:tooltip, :popup)) && continue
        held.textures[id] = _make_held_bar_textures(res, parts)
    end
    _HELD_FRAMES[backend] = held
    nothing
end

function BackendModule.run_held_frame!(backend::SdlBackend, devices, state::HeldFrameState)
    held = get(_HELD_FRAMES, backend, nothing)
    held === nothing && return (sleep(0.01); :none)
    # Events that the hold keeps for later end a wait of SDL at once, so with such
    # events in the queue the frame waits by the clock.
    _count_queued_events() == 0 ? _wait_for_queued_event(10) : sleep(0.01)
    SDL_PumpEvents()
    if held.bar_ticks == 0 && state.seconds >= 0.5
        held.bar_ticks = SDL_GetTicks()
        held.needs_present = true
    end
    state.seconds >= 0.1 && _set_pointer_shape!(backend, :hourglass)
    _filter_held_events!(held)
    shown = (floor(Int, state.seconds), state.current, state.is_stop_pending, state.is_quit_asked)
    if held.needs_present || (held.bar_ticks != 0 && shown != held.shown)
        for res in values(backend.windows)
            _present_held_window!(held, res, state)
        end
        held.needs_present = false
        held.shown = shown
    end
    answer = held.is_quit_confirmed && state.is_quit_asked ? :quit :
             held.closes > 0 ? :close :
             held.is_stop_asked ? :stop : :none
    held.is_stop_asked = false
    held.is_quit_confirmed = false
    held.closes = 0
    # The services of the thread of the loop run between two held frames.
    yield()
    answer
end

function BackendModule.end_held_frames!(backend::SdlBackend, devices)
    held = pop!(_HELD_FRAMES, backend, nothing)
    held === nothing && return nothing
    for (id, res) in backend.windows
        id in held.vsync_off && res.renderer != C_NULL && SDL_RenderSetVSync(res.renderer, 1)
        _present_retained_picture!(res)
    end
    for textures in values(held.textures)
        for texture in _list_held_textures(textures)
            texture.texture == C_NULL || SDL_DestroyTexture(texture.texture)
        end
    end
    _update_pointer_shape_at_pointer!(backend)
    nothing
end

# How many events wait in the queue of SDL.
_count_queued_events() =
    Int(SDL_PeepEvents(Ptr{SDL_Event}(C_NULL), 0, SDL_PEEKEVENT, SDL_FIRSTEVENT, SDL_LASTEVENT))

# ── The picture ─────────────────────────────────────────────────────────────

# The retained picture of `res` at its own size at the top left, so after a resize
# the rest shows the background, and the busy bar over it once it shows.
function _present_held_window!(held::_HeldFrames, res::SdlWindowResources, state::HeldFrameState)
    (res.renderer == C_NULL || res.target == C_NULL) && return nothing
    renderer = res.renderer
    SDL_SetRenderTarget(renderer, C_NULL)
    SDL_RenderSetScale(renderer, 1.0f0, 1.0f0)
    SDL_SetRenderDrawColor(renderer, res.bg...)
    SDL_RenderClear(renderer)
    width = Cint(round(Int, res.target_w / res.ss))
    height = Cint(round(Int, res.target_h / res.ss))
    SDL_RenderCopy(renderer, res.target, C_NULL, Ref(SDL_Rect(0, 0, width, height)))
    textures = get(held.textures, res.id, nothing)
    held.bar_ticks == 0 || textures === nothing || _draw_held_bar!(held, res, textures, state)
    started = time()
    SDL_RenderPresent(renderer)
    # A present that waits for the vertical sync makes each held frame slow, so the
    # hold turns the sync of that window off until it ends.
    if time() - started > 0.05 && !(res.id in held.vsync_off)
        SDL_RenderSetVSync(renderer, 0)
        push!(held.vsync_off, res.id)
    end
    nothing
end

# The bar at the bottom of the window: the words of the part that runs, or the
# notice, or the question; the time; and the controls at the right.
function _draw_held_bar!(held::_HeldFrames, res::SdlWindowResources, textures::_HeldBarTextures,
                         state::HeldFrameState)
    renderer = res.renderer
    output_width, output_height = Ref{Cint}(0), Ref{Cint}(0)
    SDL_GetRendererOutputSize(renderer, output_width, output_height)
    window_width, window_height = Ref{Cint}(0), Ref{Cint}(0)
    SDL_GetWindowSize(res.win, window_width, window_height)
    to_window = output_width[] > 0 ? window_width[] / output_width[] : 1.0
    padding = Cint(round(Int, 8 * res.ratio))
    line = maximum(texture.height for texture in (textures.stop, textures.seconds))
    top = output_height[] - line - 2 * padding
    # @style: the busy bar draws while the code unit owns the documents and the theme
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
    SDL_SetRenderDrawColor(renderer, 0x1e, 0x3c, 0x78, 0xf0)
    SDL_RenderFillRect(renderer, Ref(SDL_Rect(0, top, output_width[], output_height[] - top)))
    words = state.is_quit_asked ? textures.question :
            state.is_stop_pending ? textures.notice :
            textures.parts[clamp(state.current, 1, length(textures.parts))]
    x = _copy_held_texture!(renderer, words, padding, top + padding) + padding
    for digit in string(floor(Int, state.seconds))
        x = _copy_held_texture!(renderer, textures.digits[digit - '0' + 1], x, top + padding)
    end
    _copy_held_texture!(renderer, textures.seconds, x + padding ÷ 2, top + padding)
    right = output_width[] - padding
    stop = _draw_held_control!(renderer, textures.stop, right, top + padding ÷ 2, padding,
                               (0xa0, 0x28, 0x28, 0xff))
    quit = nothing
    if state.is_quit_asked
        quit = _draw_held_control!(renderer, textures.quit, stop[1] - padding, top + padding ÷ 2,
                                   padding, (0x60, 0x60, 0x60, 0xff))
    end
    scale(box) = box === nothing ? nothing :
        Tuple(round(Int, value * to_window) for value in box)
    held.controls[res.sdl_id] = (scale(stop), scale(quit))
    nothing
end

# A control whose right edge is at `right`: a filled box with its word inside, and
# the box in device pixels, (x0, y0, x1, y1).
function _draw_held_control!(renderer, texture::_HeldTexture, right, top, padding, color)
    width = texture.width + 2 * padding
    height = texture.height + padding
    left = right - width
    SDL_SetRenderDrawColor(renderer, color...)
    SDL_RenderFillRect(renderer, Ref(SDL_Rect(left, top, width, height)))
    _copy_held_texture!(renderer, texture, left + padding, top + padding ÷ 2)
    (Int(left), Int(top), Int(left + width), Int(top + height))
end

# Copy `texture` with its top left at `(x, y)`, and answer the right edge.
function _copy_held_texture!(renderer, texture::_HeldTexture, x, y)
    texture.texture == C_NULL && return x
    SDL_RenderCopy(renderer, texture.texture, C_NULL, Ref(SDL_Rect(x, y, texture.width, texture.height)))
    x + texture.width
end

# The whole retained picture of `res`, presented once: a held frame drew the bar
# on the buffers of the window and not into the picture, so the next frames copy
# the whole picture too, into every buffer that the bar was on.
function _present_retained_picture!(res::SdlWindowResources)
    (res.renderer == C_NULL || res.target == C_NULL) && return nothing
    SDL_SetRenderTarget(res.renderer, C_NULL)
    SDL_RenderSetScale(res.renderer, 1.0f0, 1.0f0)
    SDL_RenderCopy(res.renderer, res.target, C_NULL, C_NULL)
    SDL_RenderPresent(res.renderer)
    res.damage_history = [[(0, 0, res.width, res.height)] for _ in 1:_DAMAGE_HISTORY_CAP]
    nothing
end

# ── The words ───────────────────────────────────────────────────────────────

# @style: the busy bar draws while the code unit owns the documents and the theme
const _HELD_BAR_FONT = StyleFont("Ubuntu", 13)
const _HELD_BAR_TEXT_COLOR = (0xff, 0xff, 0xff, 0xff)
# The longest words of a part that the bar shows.
const _HELD_BAR_PART_CHARACTERS = 90

function _make_held_bar_textures(res::SdlWindowResources, parts)
    make(text) = _make_held_texture(res, text)
    shown = [length(part) > _HELD_BAR_PART_CHARACTERS ?
                 string(first(part, _HELD_BAR_PART_CHARACTERS - 1), "…") : String(part)
             for part in parts]
    isempty(shown) && push!(shown, "The code runs")
    _HeldBarTextures([make(part) for part in shown], [make(string(digit)) for digit in 0:9],
                     make("s"), make("Stop (Esc)"), make("Quit without saving"),
                     make("The code does not stop: it computes."),
                     make("The code does not stop. Quit without saving?"))
end

function _make_held_texture(res::SdlWindowResources, text::AbstractString)
    rendered = _render_text_surface(text, _HELD_BAR_FONT, res.ratio, _HELD_BAR_TEXT_COLOR)
    rendered === nothing && return _HeldTexture(C_NULL, Cint(0), Cint(0))
    surface = first(rendered)
    texture = SDL_CreateTextureFromSurface(res.renderer, surface)
    info = unsafe_load(surface)
    SDL_FreeSurface(surface)
    _HeldTexture(texture, info.w, info.h)
end

_list_held_textures(textures::_HeldBarTextures) =
    _HeldTexture[textures.parts..., textures.digits..., textures.seconds, textures.stop,
                 textures.quit, textures.notice, textures.question]
