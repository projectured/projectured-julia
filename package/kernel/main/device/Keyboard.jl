# Fragment of `DeviceModule` — the keyboard device.

"""
    Keyboard()

A keyboard input device. Included among the `devices` passed to
`read_from_devices(backend, devices)` to poll for keyboard events.
"""
struct Keyboard <: Device end
