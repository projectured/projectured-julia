# Fragment of `SdlModule` — the workload of the window on SDL. The inputs of a
# workload step go into the event queue of SDL as the events of a device, so that
# the translation of the events of SDL runs as it runs for a hand.

"""
    run_sdl_window_workload(run_workload = run_window_workload) -> Nothing

Run the gestures of a window on an `SdlBackend` under the dummy video driver,
which opens no display and loads no OpenGL: `run_workload(; backend)` runs them,
and the default runs the window of the platform. The package calls it in its
`@compile_workload`, so that its image holds the code that SDL runs for a click,
a key and the windows that they open. A program with a window of its own passes
the workload of that window.
"""
function run_sdl_window_workload(run_workload::Function = run_window_workload)
    withenv("SDL_VIDEODRIVER" => "dummy") do
        try
            run_workload(; backend = SdlBackend())
        finally
            SDL_SetEventFilter(C_NULL, C_NULL)
        end
    end
    nothing
end

function _drop_focus_event(::Ptr{Cvoid}, event::Ptr{Cvoid})::Cint
    unsafe_load(Ptr{UInt32}(event)) == UInt32(SDL_WINDOWEVENT) || return Cint(1)
    sub = unsafe_load(Ptr{SDL_WindowEvent}(event)).event
    (sub == UInt8(SDL_WINDOWEVENT_FOCUS_GAINED) || sub == UInt8(SDL_WINDOWEVENT_FOCUS_LOST)) ?
        Cint(0) : Cint(1)
end

# The dummy video driver gives the focus to each window that opens. So a popup
# takes the focus from the main window, and the loss of the focus of the main
# window closes the popup. A window manager leaves the focus where it was when a
# popup menu opens. The workload keeps the focus events out of the queue. SDL
# drops each event of its queue when a filter is set, so the filter is set once.
function send_workload_inputs!(backend::SdlBackend, inputs::Vector{WindowInput})
    filter = @cfunction(_drop_focus_event, Cint, (Ptr{Cvoid}, Ptr{Cvoid}))
    current, userdata = Ref{Ptr{Cvoid}}(C_NULL), Ref{Ptr{Cvoid}}(C_NULL)
    (SDL_GetEventFilter(current, userdata) == SDL_TRUE && current[] == filter) ||
        SDL_SetEventFilter(filter, C_NULL)
    for input in inputs
        _push_workload_event!(backend, input.window_id, input.event)
    end
    # A held frame keeps a pointer event only from before its start, and SDL counts
    # time in milliseconds, so the next call on the editor starts after the events.
    sleep(0.002)
    nothing
end

# The inputs of a hand only: the events of the keyboard and the mouse. A call on
# the editor wakes it with an event of its own, and a window that changes each
# frame, such as a chart of the frame times, reports each new picture, and
# neither is an input that a step waits for.
has_workload_inputs(backend::SdlBackend) =
    !isempty(backend.pending_inputs) || backend.pending_motion !== nothing ||
    SDL_HasEvents(UInt32(SDL_KEYDOWN), UInt32(SDL_MOUSEWHEEL)) == SDL_TRUE

# Push the SDL event of `event` for the window `window_id`. SDL has no text input
# for Return and Tab, and the backend types them from their key.
function _push_workload_event!(backend::SdlBackend, window_id::Symbol, event)
    window = findfirst(==(window_id), backend.window_ids)
    # The window closed after the step found its target.
    window === nothing && return nothing
    ratio = _get_window_unit_ratio(backend, window_id)
    units(value) = round(Int32, value * ratio)
    if event isa MouseMove
        _push_sdl_event!(_make_sdl_event(SDL_MouseMotionEvent; type = UInt32(SDL_MOUSEMOTION),
                                         windowID = window, x = units(event.x), y = units(event.y)))
    elseif event isa Union{MouseDown,MouseUp}
        down = event isa MouseDown
        _push_sdl_event!(_make_sdl_event(SDL_MouseButtonEvent;
            type = UInt32(down ? SDL_MOUSEBUTTONDOWN : SDL_MOUSEBUTTONUP), windowID = window,
            button = _get_sdl_button(event.button), state = down ? 0x01 : 0x00, clicks = 0x01,
            x = units(event.x), y = units(event.y)))
    elseif event isa Union{KeyDown,KeyUp}
        down = event isa KeyDown
        keysym = SDL_Keysym(SDL_SCANCODE_UNKNOWN, _find_sdl_keysym(event.key),
                            _get_sdl_modifiers(event.modifiers), UInt32(0))
        _push_sdl_event!(_make_sdl_event(SDL_KeyboardEvent;
            type = UInt32(down ? SDL_KEYDOWN : SDL_KEYUP), windowID = window,
            state = down ? 0x01 : 0x00, keysym))
    elseif event isa KeyPress && !(event.char in ('\n', '\t'))
        bytes = codeunits(event.text)
        text = ntuple(i -> i <= length(bytes) ? reinterpret(Cchar, bytes[i]) : Cchar(0), 32)
        _push_sdl_event!(_make_sdl_event(SDL_TextInputEvent; type = UInt32(SDL_TEXTINPUT),
                                         windowID = window, text))
    end
    nothing
end

# A struct of an SDL event with the fields of `values` and zero in each other field.
_make_sdl_event(type::Type; values...) =
    type((haskey(values, name) ? values[name] : zero(fieldtype(type, name))
          for name in fieldnames(type))...)

function _push_sdl_event!(event)
    union = Ref{SDL_Event}()
    GC.@preserve union begin
        pointer = Base.unsafe_convert(Ptr{SDL_Event}, union)
        Libc.memset(pointer, 0, sizeof(SDL_Event))
        unsafe_store!(Ptr{typeof(event)}(pointer), event)
        SDL_PushEvent(pointer) == 1 || error("SDL_PushEvent: " * unsafe_string(SDL_GetError()))
    end
    nothing
end

# The SDL key code that `sdl_keysym_to_symbol` reads as `key`: a code of a
# character, or a code of a key with no character, which SDL marks with bit 30.
function _find_sdl_keysym(key::Symbol)
    for code in Iterators.flatten((Int32(0):Int32(127), Int32(1 << 30):Int32((1 << 30) + 300)))
        sdl_keysym_to_symbol(code) === key && return code
    end
    Int32(0)
end

_get_sdl_button(button::Symbol) =
    button === :left ? 0x01 : button === :middle ? 0x02 : button === :right ? 0x03 :
    button === :back ? 0x04 : 0x05

# The left keys of the modifiers, as `sdl_modifiers` reads them.
_get_sdl_modifiers(modifiers::ModifierKeys) =
    UInt16((modifiers.shift ? 0x0001 : 0x0000) | (modifiers.ctrl ? 0x0040 : 0x0000) |
           (modifiers.alt ? 0x0100 : 0x0000) | (modifiers.meta ? 0x0400 : 0x0000))
