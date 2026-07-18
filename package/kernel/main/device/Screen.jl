# Fragment of `DeviceModule` — the screen device.

"""
    Screen()

A screen / display output device. It names the hardware target only and carries
no per-window state: the live windows are reconciled on demand against the output
it is asked to render.

Multi-monitor support would express each physical display as its own `Screen`
(not implemented yet).
"""
struct Screen <: Device end
