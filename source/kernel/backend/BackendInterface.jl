# Fragment of `BackendModule` — the backend **contract**: the abstract `Backend`
# type every backend subtypes, and the open generics a backend package answers
# with a method for its own concrete type. Nothing here carries a body — the
# concrete backends live in packages above the kernel, and the fallback behaviours
# for the capabilities a backend can lack sit in `BackendDefaults.jl`.

"""
    Backend

Abstract supertype for all display/input backends.

A backend starts with three calls, in this order, before the first print:
`initialize_backend!`, then `configure_devices!` with the devices of the editor,
then `open_native_windows!` with the first document. `quit_backend!` ends it.
"""
abstract type Backend end

"""
    initialize_backend!(backend)

Initialize the backend: load its libraries and make the state that the other
generics use. It opens no window; `open_native_windows!` opens the windows.
"""
function initialize_backend! end

"""
    quit_backend!(backend)

Tear down the backend and release resources.
"""
function quit_backend! end

"""
    write_to_devices!(backend, devices, document)

Render `document` to all output devices in `devices` using `backend`. A concrete
backend adds a method dispatched on its own type; there is deliberately no
catch-all, so an unimplemented backend raises `MethodError` rather than silently
doing nothing.

A backend that shows windows reports each frame that it shows and that differs
from the frame before: its next `take_from_devices!` answers
`WindowInput(window_id, DisplayUpdate(; time))` for that window, and its
`wait_for_input` does not block while such an input waits. A frame that shows
nothing new reports nothing, so the loop can sleep. A backend that can not tell
reports nothing, and a reader that keeps a part of the view as its state then
finds it again only at the next input.
"""
function write_to_devices! end

"""
    open_native_windows!(backend, document)

Open the native window of every window `document` names, then correct `document`
to the size that the window system gives the window.

The backend opens the windows once, before the first print. The window system can
give a window another size than the size in the document: a window manager that
keeps a window inside the work area gives a decorated window less height. The
size is known only after the window exists. A document laid out before that has
a size that the window never has, so the size arrives as a resize and the whole
document computes a second time. When the windows open first, the second layout
does not happen.

A backend with no windows of its own leaves this at the no-op default.
"""
function open_native_windows! end

"""
    take_from_devices!(backend, devices) -> WindowInput or nothing

Poll all input devices in one shot and return the next event — a `WindowInput`
carrying an `Event` — or `nothing` when there is none. A concrete backend
adds a method dispatched on its own type (typically polling a shared event queue
and classifying events across device types), and it is where a platform's raw
events are translated into that vocabulary: a device reports only what happened,
never a gesture derived from several events.
"""
function take_from_devices! end

"""
    wait_for_input(backend, devices, timeout_seconds) -> Nothing

Block until an input event arrives, [`wake_backend!`](@ref) is called, or
`timeout_seconds` passes — whichever comes first. `timeout_seconds` must be
above 0, and `Inf` is legal. The timeout is the time to the next deadline, such
as the next tick of an animation. A backend can divide a long wait into slices,
so that the other tasks on its thread run.
"""
function wait_for_input end

"""
    wake_backend!(backend) -> Nothing

End a [`wait_for_input`](@ref) in progress, from any task or thread. The one
function of this contract that must be thread-safe: everything else runs on
the editor task.
"""
function wake_backend! end

"""
    get_pointer_position(::Backend) -> (x, y)

The current global mouse pointer position in the logical pixels of the screen,
the space of the place of a window, or `(-1, -1)` when the backend cannot find it. `(-1, -1)` is a legal answer, and the default gives
it for a backend that adds no method of its own.
"""
function get_pointer_position end

"""
    get_display_size(backend) -> (width, height)

The usable size of the display in logical pixels, as `backend` finds it, or the
default `(1280, 800)` for a backend that cannot find the size of a display.
"""
function get_display_size end

"""
    find_system_colors(backend) -> SystemColors or nothing

The colour settings of the operating system, as `backend` finds them: the mode,
the contrast and the accent, as a `SystemColors`. `nothing` when `backend` can not
find them, which is the default. A backend that finds them reports a later change
as a `SystemColorsChange`. The call waits for the system for a short time at most,
and answers `nothing` when the system does not answer in that time.
"""
function find_system_colors end

"""
    configure_devices!(backend, devices)

Fill in the physical properties of each device in `devices` from what `backend`
finds about the real hardware, such as the size and the density of a `Display`.
The call changes the devices in place. A backend that draws with a device keeps
that device, so a later change of the device changes what the backend draws. A
backend that finds nothing leaves the devices at their defaults.
"""
function configure_devices! end

"""
    write_image(document, projection, filename; kwargs...)
    write_image(canvas, filename; kwargs...)

Render to a raster image file. Implemented by a rendering backend package via
offscreen software rendering; forward-declared here so callers need not name it.
"""
function write_image end

"""
    record_video(document, projection; gestures, filename, kwargs...)

Render a timeline of gestures to a video file (offscreen frames assembled into a
movie). Implemented by a rendering backend package that also has a video encoder
available; forward-declared here so callers need not name it.
"""
function record_video end

"""
    render_canvas(canvas) -> image

Rasterize a graphics-canvas document to an image document. Implemented by a
rendering backend package; forward-declared here so callers need not name it.
"""
function render_canvas end

"""
    decode_image(filename) -> (data::Vector{UInt8}, width, height)

Decode an image file to raw RGBA pixels. Implemented by a backend package with an
image decoder; forward-declared here so callers need not name it.
"""
function decode_image end
