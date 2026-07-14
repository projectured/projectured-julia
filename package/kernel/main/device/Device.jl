"""
    DeviceModule

The device *interface* — the contract for rendering a document to, and polling
input from, a set of devices, plus the concrete devices an editor is given
(`Keyboard`, `Mouse`, `Screen`, one fragment file each).

`read_from_devices` and `write_to_devices` are pure interface stubs: a concrete
implementation adds the methods, dispatching on its own type. The interface names
no such type, so a device does not depend on whatever drives it — the two
abstractions are independent siblings, and only the implementation binds them
together.
"""
module DeviceModule

export Device, Keyboard, Mouse, Screen, write_to_devices, read_from_devices

"""
    Device

Abstract supertype for all I/O devices (screen, keyboard, mouse, …).
"""
abstract type Device end

"""
    write_to_devices(backend, devices, document)

Render `document` to all output devices in `devices` using `backend`. A concrete
backend adds a method dispatched on its own type; there is deliberately no
catch-all, so an unimplemented backend raises `MethodError` rather than silently
doing nothing.
"""
function write_to_devices end

"""
    read_from_devices(backend, devices) -> EventEnvelope or nothing

Poll all input devices in one shot and return the next event — an `EventEnvelope`
carrying a `DeviceEvent` — or `nothing` when there is none. A concrete backend
adds a method dispatched on its own type (typically polling a shared event queue
and classifying events across device types), and it is where a platform's raw
events are translated into that vocabulary: a device reports only what happened,
never a gesture derived from several events.
"""
function read_from_devices end

include("Keyboard.jl")
include("Mouse.jl")
include("Screen.jl")

end # module
