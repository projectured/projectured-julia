"""
    DeviceModule

The input and output devices. A device holds the physical properties of one
piece of hardware that an editor uses, and it has no behaviour. A backend fills
the properties that it can find. The display also holds the zoom of the editor,
and gives the ratio of device pixels to logical pixels.

The module lives in four fragments that share this namespace:

- [`DeviceInterface.jl`](DeviceInterface.jl) — `Device`, the supertype of every
  device.
- [`Keyboard.jl`](Keyboard.jl) — the `Keyboard` device and its layout.
- [`Mouse.jl`](Mouse.jl) — the `Mouse` device, its buttons and its scroll wheel.
- [`Display.jl`](Display.jl) — the `Display` device, its size, its scale and its
  zoom, and `get_device_pixel_ratio`.
"""
module DeviceModule

export Device
export Keyboard
export Mouse
export Display, get_device_pixel_ratio

include("DeviceInterface.jl")
include("Keyboard.jl")
include("Mouse.jl")
include("Display.jl")

end # module
