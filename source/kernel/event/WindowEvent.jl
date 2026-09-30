# Fragment of `EventModule` — the window events. Each reports what the user did to a
# window. The window is not in the event but in the `window_id` of the
# `WindowInput` that holds it, so a window event names no window type.

"""
    WindowQuit(; time)

The user asked to quit the whole application. It is a request, and the application
can ignore it. `time` is the time of the input (see `Event`).
"""
struct WindowQuit <: Event
    time::Float64
end

WindowQuit(; time::Real) = WindowQuit(Float64(time))

"""
    WindowClose(; time)

The user asked to close one window, with its close button. It is a request, and the
application can ignore it: the event reports what the user did, not what must
happen. The window is the `window_id` of the `WindowInput` that holds the event.
"""
struct WindowClose <: Event
    time::Float64
end

WindowClose(; time::Real) = WindowClose(Float64(time))

"""
    WindowResize(width, height; time)
    WindowResize(width, height, time)

The user changed the size of a window. `width` and `height` are the new size of its
content area, in logical pixels.
"""
struct WindowResize <: Event
    width::Int
    height::Int
    time::Float64
end

WindowResize(width::Int, height::Int; time::Real) =
    WindowResize(width, height, Float64(time))

"""
    WindowDefocus(; time)

A window lost input focus.
"""
struct WindowDefocus <: Event
    time::Float64
end

WindowDefocus(; time::Real) = WindowDefocus(Float64(time))

"""
    WindowLeave(; time)

The pointer left a window. A pointer that crosses from one widget to another inside
a window moves, and the code that tracks the widgets makes a `MouseLeave` from the
motion; a pointer that goes out of the window moves over nothing that the window
sees, so the source reports it as this event.
"""
struct WindowLeave <: Event
    time::Float64
end

WindowLeave(; time::Real) = WindowLeave(Float64(time))
