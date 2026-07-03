"""
    ScreenDeviceModule

Backend-agnostic screen device. `Screen <: Device` describes the
hardware target — the display the editor renders onto. It carries no
per-window state; the live native windows are managed by the backend
based on the projection-output `ScreenDocument` (see
`document/ScreenDocument.jl`).
"""
module ScreenDeviceModule

import ..DeviceApiModule: Device

export Screen, WindowQuit

"""
    Screen()

A screen / display output device. Passed to `application` in the
`devices` list to indicate that the editor wants to render onto a
display. The backend opens, updates, and closes native windows on
demand to match the projection-output `ScreenDocument` — no per-window
state lives on `Screen` itself.

Multi-monitor support would express each physical display as its own
`Screen` device (not implemented yet).
"""
struct Screen <: Device end

"""
    WindowQuit

Backend-agnostic event signalling that the user requested to quit
the entire application (e.g. `SDL_QUIT`, or Escape in the focused
window). It is a *request* the application may refuse. Per-window
close requests are signalled by a `WindowClose` carried inside an
`EventEnvelope`.
"""
struct WindowQuit end

end # module
