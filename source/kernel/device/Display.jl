# Fragment of `DeviceModule` — the display device.

"""
    Display(; width=1280, height=800, scale=1.0)

A display output device. It carries the physical properties of the display it
renders to — `width`×`height` in pixels and the HiDPI `scale` factor —
defaulting to a display-free fallback until the real display is queried. It
carries no per-window state: the live windows are reconciled on demand against
the output it is asked to render.

Multi-monitor support would express each physical display as its own `Display`
(not implemented yet).
"""
mutable struct Display <: Device
    width::Int
    height::Int
    scale::Float64
end

Display(; width::Int=1280, height::Int=800, scale::Real=1.0) =
    Display(width, height, Float64(scale))
