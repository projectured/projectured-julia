"""
    DeviceModule

The I/O devices: inert marker types that name what to poll for input and render
for output. Its fragments:

- [`Device.jl`](Device.jl) — the `Device` supertype every device subtypes.
- [`Keyboard.jl`](Keyboard.jl) — the `Keyboard` device.
- [`Mouse.jl`](Mouse.jl) — the `Mouse` device.
- [`Screen.jl`](Screen.jl) — the `Screen` device.

A device carries no per-device state; it names an endpoint and nothing more.
"""
module DeviceModule

export Device, Keyboard, Mouse, Screen

# Device.jl first — the concrete devices below subtype the `Device` it declares.
include("Device.jl")
include("Keyboard.jl")
include("Mouse.jl")
include("Screen.jl")

end # module
