# Fragment of `DeviceModule` — the screen device.

"""
    Screen()

A screen / display output device. Included among the `devices` an editor is given
to indicate that it wants to render onto a display. It describes the hardware
target only and carries no per-window state: the live windows are reconciled on
demand by whatever drives the device, against the output it is asked to write.

Multi-monitor support would express each physical display as its own `Screen`
(not implemented yet).
"""
struct Screen <: Device end
