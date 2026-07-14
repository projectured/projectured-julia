# Fragment of `BackendModule` — the backend **contract**: the abstract `Backend`
# type every backend subtypes, and the open generics a backend package answers
# with a method for its own concrete type. Nothing here carries a body — the
# concrete backends live in opt-in packages, and the one behaviour the contract
# supplies for itself (what a backend that cannot report a pointer position
# says) sits in `BackendDefaults.jl`.
#
# `get_display_size` + its provider glue (mutable global state) live in
# `DisplayModule` (backend/Display.jl), not in this contract.

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
rendering backend package; forward-declared here so callers (e.g. a
graphics-caching projection) need not name it.
"""
function render_canvas end

"""
    decode_image(filename) -> (data::Vector{UInt8}, width, height)

Decode an image file to raw RGBA pixels. Implemented by a backend package with an
image decoder; forward-declared here so callers need not name it.
"""
function decode_image end
