"""
    DeviceModule

Device interface. Declares per-device and batch I/O functions, all
dispatched on a `Backend` first argument so the backend provides the
*how* while the device identifies the *what*.
"""
module DeviceModule

import ..BackendModule: Backend

export Device, write_to_device, read_from_device, write_to_devices, read_from_devices

"""
    Device

Abstract supertype for all I/O devices (screen, keyboard, mouse, …).
"""
abstract type Device end

"""
    write_to_device(::Backend, device, document)

Render or transmit `document` to a single `device` using the backend.
"""
function write_to_device(::Backend, device, document) end

"""
    read_from_device(::Backend, device)

Poll a single `device` for the next pending input event using the backend.
Returns `nothing` if no event is available.
"""
function read_from_device(::Backend, device) end

"""
    write_to_devices(::Backend, devices, document)

Render `document` to all output devices in `devices`. Backends with
shared rendering contexts (e.g. SDL) can override this to batch writes.
"""
function write_to_devices(::Backend, devices, document) end

"""
    read_from_devices(::Backend, devices)

Poll all input devices in one shot and return the next event, or `nothing`.
Backends with a shared event queue (e.g. SDL) override this to poll once
and classify events across device types.
"""
function read_from_devices(::Backend, devices) end

end # module