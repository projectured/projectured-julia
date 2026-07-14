# Fragment of `EventModule` — the window events.
#
# All four report something the user did to a window. Which window is not part of
# the event: it is the `EventEnvelope`'s `window_id`, so a window event names no
# window type and stays pure input vocabulary.

"""
    WindowQuit()

The user requested to quit the entire application. It is a *request* the
application may refuse.
"""
struct WindowQuit <: DeviceEvent end

"""
    WindowClose()

The user requested to close one window (its native close button). A *request*
the application may refuse — the event reports what the user did, not what must
happen. The window it refers to is the enclosing envelope's `window_id`.
"""
struct WindowClose <: DeviceEvent end

"""
    WindowResize(width, height)

The user resized a window's native frame. `width`/`height` are the new pixel size
of the window's content area.
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
