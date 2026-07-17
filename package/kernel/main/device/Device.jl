# Fragment of `DeviceModule` — the device **contract**: the `Device` supertype
# every device subtypes, and the two batch I/O generics a concrete backend
# answers with a method dispatched on its own type. The concrete devices an
# editor is given live in the sibling `Keyboard.jl` / `Mouse.jl` / `Screen.jl`
# fragments.

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
    read_from_devices(backend, devices) -> WindowInput or nothing

Poll all input devices in one shot and return the next event — an `WindowInput`
carrying a `DeviceEvent` — or `nothing` when there is none. A concrete backend
adds a method dispatched on its own type (typically polling a shared event queue
and classifying events across device types), and it is where a platform's raw
events are translated into that vocabulary: a device reports only what happened,
never a gesture derived from several events.
"""
function read_from_devices end
