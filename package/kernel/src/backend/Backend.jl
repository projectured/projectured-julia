"""
    BackendModule

Abstract backend interface — layer 6, independent sibling of the device
layer. A `Backend` encapsulates everything needed to initialise, shut down,
read input from, and write output to a particular display/input system.
Concrete subtypes and the methods of the generic functions declared here
live in **opt-in backend packages** that depend on this kernel; this module
carries only the abstract type and the forward-declared generics, so generic
code can name a capability (measure text, write an image, …) without
referencing any concrete backend at load time. A generic that isn't
implemented because its backend package isn't loaded raises a `MethodError`
(or, for the `make_backend` factory seam, a helpful error).

Renamed from `BackendApiModule` in kernel plan P6; the old name lives on as
an alias in `ProjecturedDomain`.
"""
module BackendModule

export Backend, initialize_backend!, quit_backend!, measure_text, make_backend, write_image, record_video,
       render_canvas, decode_image, get_pointer_position

"""
    Backend

Abstract supertype for all display/input backends.
"""
abstract type Backend end

"""
    make_backend(kind::Symbol; kwargs...) -> Backend

Construct a backend by symbolic `kind` (`:sdl`, `:web`, `:console`, …). Concrete
backend modules add a method `make_backend(::Val{kind}; kwargs...)` returning the
backend instance. This indirection lets callers select a backend without naming
its concrete type, so a backend whose implementation lives in an optional package
extension need not be referenced at load time. When no method is registered for
`kind` (e.g. its optional dependency is not loaded), a helpful error is raised.
"""
make_backend(kind::Symbol; kwargs...) = make_backend(Val(kind); kwargs...)
make_backend(::Val{K}; kwargs...) where {K} = error(
    "No backend registered for :$(K). Is the package/extension that provides it loaded?")

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
the backend cannot report it (the default). A caller that needs it — e.g. to
place a follower window near the cursor — closes over this behind a `pointer`
callback so it stays free of any concrete backend dependency (the same
indirection as `measure_text`).
"""
get_pointer_position(::Backend) = (-1, -1)

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

# `get_display_size` + its provider glue (mutable global state) live in `DisplayModule`
# (device/Display.jl), not in this pure interface.

end # module
