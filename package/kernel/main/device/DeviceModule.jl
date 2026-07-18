"""
    DeviceModule

The I/O devices: inert marker types that name what to poll for input and render
for output. Its fragments:

- [`Device.jl`](Device.jl) — the `Device` supertype every device subtypes.
- [`Keyboard.jl`](Keyboard.jl) — the `Keyboard` device.
- [`Mouse.jl`](Mouse.jl) — the `Mouse` device.
- [`Display.jl`](Display.jl) — the `Display` device.

A device carries no per-device state; it names an endpoint and nothing more.
"""
module DeviceModule

export Device, Keyboard, Mouse, Display

include("Device.jl")
include("Keyboard.jl")
include("Mouse.jl")
include("Display.jl")

end # module
