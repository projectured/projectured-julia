"""
    ScreenModule

Backend-agnostic screen device. `Screen <: Device` describes the
hardware target — the display the editor renders onto. It carries no
per-window state; the live native windows are managed by the backend
based on the projection-output `ScreenDocument` (see
`document/ScreenDocument.jl`).
"""
module ScreenModule

import ..DeviceModule: Device

export Screen, QuitEvent

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
    QuitEvent

Backend-agnostic event signalling that the user requested to quit
the entire application (e.g. `SDL_QUIT`, or Escape in the focused
window). Per-window close requests are signalled by a
`WindowCloseRequest` carried inside an `EventEnvelope`.
"""
struct QuitEvent end

end # module
