"""
    DeviceModule

The device *interface* — the contract for rendering a document to, and polling
input from, a set of devices, plus the concrete devices an editor is given.

`read_from_devices` and `write_to_devices` are pure interface stubs: a concrete
implementation adds the methods, dispatching on its own type. The interface names
no such type, so a device does not depend on whatever drives it — the two
abstractions are independent siblings, and only the implementation binds them
together.

The module lives in four fragments that share this namespace:

- [`Device.jl`](Device.jl) — the contract: the `Device` supertype and the two
  batch I/O generics a backend answers.
- [`Keyboard.jl`](Keyboard.jl) — the `Keyboard` device.
- [`Mouse.jl`](Mouse.jl) — the `Mouse` device.
- [`Screen.jl`](Screen.jl) — the `Screen` device.
"""
module DeviceModule

export Device, Keyboard, Mouse, Screen, write_to_devices, read_from_devices

# Device.jl first — the concrete devices below subtype the `Device` it declares.
include("Device.jl")
include("Keyboard.jl")
include("Mouse.jl")
include("Screen.jl")

end # module
