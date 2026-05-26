"""
    WindowModule

Backend-agnostic window device. The `Window` struct describes a window
to be created; the actual native resources are managed by the backend
(see `backend/Sdl.jl` for the SDL implementation).
"""
module WindowModule

import ..DeviceModule: Device

export Window, QuitEvent

"""
    Window

A display output device. The backend creates the native window/renderer
and associates them with this object via backend-specific fields.

Fields set at construction:
- `title`  — window title
- `width`  — initial width in pixels
- `height` — initial height in pixels
- `bg`     — background RGBA tuple

The `handle` field is backend-managed (set by `open_window!` or a
backend-specific constructor). Generic code must not access it.
"""
mutable struct Window <: Device
    title::String
    width::Int
    height::Int
    bg::NTuple{4,UInt8}
    handle::Any          # backend-specific native resources
end

function Window(title::AbstractString, width::Integer, height::Integer;
                bg::NTuple{4,Integer} = (253, 246, 227, 255))
    Window(String(title), Int(width), Int(height),
           (UInt8(bg[1]), UInt8(bg[2]), UInt8(bg[3]), UInt8(bg[4])),
           nothing)
end

"""
    QuitEvent

Backend-agnostic event signalling that the user requested to quit
(e.g. closed the window or pressed Escape).
"""
struct QuitEvent end

end # module
