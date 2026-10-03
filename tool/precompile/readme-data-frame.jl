# The run of the recording "readme-data-frame": what the README of the release
# repository tells a user to write, then a few gestures in its window.
#
# It runs in `environment/readme-data-frame`, which holds the packages of the
# README and nothing else, so that what it records is what such a session
# compiles. The gestures are real SDL events on the queue of the window, so they
# take the path that a hand takes. Needs a display.

using Projectured, DataFrames, SimpleDirectMediaLayer

const SDL = SimpleDirectMediaLayer.LibSDL2

# The event types of SDL that the gestures push.
const KEYDOWN, KEYUP = 0x00000300, 0x00000301
const MOUSEMOTION, MOUSEBUTTONDOWN, MOUSEBUTTONUP, MOUSEWHEEL =
    0x00000400, 0x00000401, 0x00000402, 0x00000403

# The window of the editor: the largest window that SDL knows.
function find_editor_window()
    found, area = UInt32(0), 0
    for id in UInt32(1):UInt32(64)
        window = SDL.SDL_GetWindowFromID(id)
        window == C_NULL && continue
        width, height = Ref{Cint}(0), Ref{Cint}(0)
        SDL.SDL_GetWindowSize(window, width, height)
        if width[] * height[] > area
            found, area = id, Int(width[] * height[])
        end
    end
    found == 0 && error("the driver finds no window of the editor")
    window = SDL.SDL_GetWindowFromID(found)
    width, height = Ref{Cint}(0), Ref{Cint}(0)
    SDL.SDL_GetWindowSize(window, width, height)
    found, Int(width[]), Int(height[])
end

# Push one event of type `T` with the fields `values`; every other field is 0, so
# the event fits each version of the SDL bindings.
function push_event!(T, values)
    fields = (haskey(values, name) ? values[name] : fieldtype(T, name)(0) for name in fieldnames(T))
    event = Ref{SDL.SDL_Event}()
    GC.@preserve event begin
        base = Base.unsafe_convert(Ptr{SDL.SDL_Event}, event)
        unsafe_store!(convert(Ptr{T}, base), T(fields...))
        SDL.SDL_PushEvent(event)
    end
    sleep(0.5)
end

move!(window, x, y) = push_event!(SDL.SDL_MouseMotionEvent,
    Dict(:type => MOUSEMOTION, :windowID => window, :x => Int32(x), :y => Int32(y)))

turn_wheel!(window, steps) = push_event!(SDL.SDL_MouseWheelEvent,
    Dict(:type => MOUSEWHEEL, :windowID => window, :y => Int32(steps)))

function click!(window, x, y)
    for (type, state) in ((MOUSEBUTTONDOWN, 0x01), (MOUSEBUTTONUP, 0x00))
        push_event!(SDL.SDL_MouseButtonEvent,
            Dict(:type => type, :windowID => window, :button => 0x01, :state => state,
                 :clicks => 0x01, :x => Int32(x), :y => Int32(y)))
    end
end

function press!(window, scancode, key)
    keysym = SDL.SDL_Keysym(scancode, Int32(key), UInt16(0), UInt32(0))
    for (type, state) in ((KEYDOWN, 0x01), (KEYUP, 0x00))
        push_event!(SDL.SDL_KeyboardEvent,
            Dict(:type => type, :windowID => window, :state => state, :keysym => keysym))
    end
end

display_in_editor(DataFrame(n = 1:100_000, square = (1:100_000) .^ 2))
try
    sleep(8)    # the first frames
    window, width, height = find_editor_window()
    x, y = width ÷ 2, height ÷ 2
    move!(window, x, y)
    turn_wheel!(window, -3)
    turn_wheel!(window, 3)
    click!(window, x, y)
    press!(window, SDL.SDL_SCANCODE_DOWN, SDL.SDLK_DOWN)
    press!(window, SDL.SDL_SCANCODE_RIGHT, SDL.SDLK_RIGHT)
    press!(window, SDL.SDL_SCANCODE_F2, SDL.SDLK_F2)
    press!(window, SDL.SDL_SCANCODE_ESCAPE, SDL.SDLK_ESCAPE)
    sleep(3)
finally
    close_display_editor!()
end
println("driver: done")
