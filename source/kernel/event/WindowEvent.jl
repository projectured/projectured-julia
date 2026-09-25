# Fragment of `EventModule` — the window events. Each reports what the user did to a
# window. The window is not in the event but in the `window_id` of the
# `WindowInput` that holds it, so a window event names no window type.

"""
    WindowQuit()

The user asked to quit the whole application. It is a request, and the application
can ignore it.
"""
struct WindowQuit <: DeviceEvent end

"""
    WindowClose()

The user asked to close one window, with its close button. It is a request, and the
application can ignore it: the event reports what the user did, not what must
happen. The window is the `window_id` of the `WindowInput` that holds the event.
"""
struct WindowClose <: DeviceEvent end

"""
    WindowResize(width, height)

The user changed the size of a window. `width` and `height` are the new size of its
content area, in pixels.
"""
struct WindowResize <: DeviceEvent
    width::Int
    height::Int
end

"""
    WindowDefocus()

A window lost input focus.
"""
struct WindowDefocus <: DeviceEvent end
