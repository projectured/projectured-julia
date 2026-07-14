# Fragment of `DeviceModule` — the mouse device.

"""
    Mouse()

A mouse input device. Included among the `devices` passed to
`read_from_devices(backend, devices)` to poll for mouse events.
"""
struct Mouse <: Device end
