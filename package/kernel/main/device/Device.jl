"""
    DeviceModule

The device *interface* — the first module of layer 5. Declares the batch I/O
used to render a document to, and poll input from, a set of devices. These are
pure interface stubs: a concrete backend adds the methods, dispatching on its
own backend type (e.g. `write_to_devices(::SomeBackend, devices, doc)`). The
interface itself names no backend type, so `Device` does not depend on
`Backend` — the two abstractions are independent siblings, and only a
concrete implementation binds them together.
"""
module DeviceModule

export Device, write_to_devices, read_from_devices

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
    read_from_devices(backend, devices) -> event or nothing

Poll all input devices in one shot and return the next event, or `nothing`.
A concrete backend adds a method dispatched on its own type (typically polling a
shared event queue and classifying events across device types).
"""
function read_from_devices end

end # module
