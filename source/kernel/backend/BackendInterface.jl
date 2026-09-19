# Fragment of `BackendModule` — the backend **contract**: the abstract `Backend`
# type every backend subtypes, and the open generics a backend package answers
# with a method for its own concrete type. Nothing here carries a body — the
# concrete backends live in opt-in packages, and the fallback behaviours for the
# capabilities a backend may decline sit in `BackendDefaults.jl`.

"""
    Backend

Abstract supertype for all display/input backends.
"""
abstract type Backend end

"""
    initialize_backend!(backend)

Initialise the backend (create windows, load libraries, …).
"""
function initialize_backend! end

"""
    quit_backend!(backend)

Tear down the backend and release resources.
"""
function quit_backend! end

"""
    measure_text(backend, text, font) -> (Int, Int)

Return the `(pixel_width, pixel_height)` of `text` rendered in `font`.
"""
function measure_text end

"""
    write_to_devices(backend, devices, document)

Render `document` to all output devices in `devices` using `backend`. A concrete
backend adds a method dispatched on its own type; there is deliberately no
catch-all, so an unimplemented backend raises `MethodError` rather than silently
doing nothing.
"""
function write_to_devices end

"""
    open_native_windows!(backend, document)

Open the native window of every window `document` names, then correct `document`
to the geometry the window system granted.

Called once, before the first projection. A window system is free to refuse the
size it is asked for — a manager that keeps a window inside the work area grants
less height than a decorated window asks for — and it answers only after the
window exists. A document laid out before that answer is laid out at a size the
window never has, so the answer arrives as a resize and the whole document
computes a second time. Opening the windows first turns that second layout into
none.

A backend with no windows of its own leaves this at the no-op default.
"""
function open_native_windows! end

"""
    read_from_devices(backend, devices) -> WindowInput or nothing

Poll all input devices in one shot and return the next event — a `WindowInput`
carrying a `DeviceEvent` — or `nothing` when there is none. A concrete backend
adds a method dispatched on its own type (typically polling a shared event queue
and classifying events across device types), and it is where a platform's raw
events are translated into that vocabulary: a device reports only what happened,
never a gesture derived from several events.
"""
function read_from_devices end

"""
    wait_for_input(backend, devices, timeout_seconds) -> Nothing

Block until an input event arrives, [`wake_backend!`](@ref) is called, or
`timeout_seconds` passes — whichever comes first. The editor loop calls it
between frames, and the timeout it passes is the nearest deadline it knows
(an animation tick, a feed's flush). `Inf` is legal, and a backend may slice
a long wait internally to keep cooperative tasks on its thread scheduled.
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

The current global mouse pointer position in screen pixels, or `(-1, -1)` when
the backend cannot report it — a legal answer, and the one a backend that adds
no method of its own gives. A caller that needs the position — e.g. to place a
follower window near the cursor — closes over this behind a `pointer` callback
so it stays free of any concrete backend dependency (the same indirection as
`measure_text`).
"""
function get_pointer_position end

"""
    get_display_size(backend; display=0) -> (width, height)

The pixel size of display `display` as reported by `backend`, or the
display-free default `(1280, 800)` for a backend that cannot query a display.
"""
function get_display_size end

"""
    configure_devices!(backend, devices)

Fill in the physical properties of each device in `devices` from what `backend`
can discover about the real hardware — e.g. a `Display`'s resolution and HiDPI
scale. A backend that discovers nothing leaves the devices at their defaults.
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
    record_video(document, projection, gestures, filename; kwargs...)

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
