"""
    BackendModule

Abstract backend interface. A `Backend` encapsulates everything needed to
initialise, shut down, read input from, and write output to a particular
display/input system (e.g. SDL). Concrete subtypes live in opt-in backend
packages such as `ProjecturedSdl` (`package/sdl`).
"""
module BackendModule

export Backend, init!, quit!, measure_text, make_backend, write_image, record_video,
       render_canvas, decode_image, display_size, set_display_size_provider!,
       pointer_position

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
    init!(backend)

Initialise the backend (create windows, load libraries, …).
"""
function init! end

"""
    quit!(backend)

Tear down the backend and release resources.
"""
function quit! end

"""
    measure_text(backend, text, font) -> (Int, Int)

Return the `(pixel_width, pixel_height)` of `text` rendered in `font`.
"""
function measure_text end

"""
    pointer_position(::Backend) -> (x, y)

The current global mouse pointer position in screen pixels, or `(-1, -1)` when
the backend cannot report it. Implemented by the SDL backend; used to place a
follower window (e.g. the hover reference inspector) near the cursor. A
projection that needs it takes a `pointer` closure over this so it stays free
of any concrete backend dependency (the same indirection as `measure_text`).
"""
pointer_position(::Backend) = (-1, -1)

"""
    write_image(document, projection, filename; kwargs...)
    write_image(canvas, filename; kwargs...)

Render to a raster image file. Implemented by a rendering backend (currently the
SDL backend, via offscreen software rendering) — the method lives wherever that
backend does, so it is only available when that backend's optional dependency is
loaded. Generic forward-declaration kept here so callers need not name the
concrete backend module.
"""
function write_image end

"""
    record_video(document, projection, gestures, filename; kwargs...)

Render a timeline of gestures to a video file. Implemented by the SDL backend
(offscreen frames assembled with `ffmpeg`), so it requires both the SDL backend
and `FFMPEG` to be available. Generic forward-declaration kept here so callers
need not name the concrete backend module.
"""
function record_video end

"""
    render_canvas(canvas::GraphicsCanvas) -> GraphicsImage

Rasterize a graphics canvas to an image. Implemented by a rendering backend
(the SDL backend), so it needs that backend's optional dependency. Generic
forward-declaration so callers (e.g. the graphics-caching projection) need not
name the concrete backend module.
"""
function render_canvas end

"""
    decode_image(filename) -> (data::Vector{UInt8}, width, height)

Decode an image file to raw RGBA pixels. Implemented by the SDL backend (the
only image decoder), so it requires SDL. Generic forward-declaration so callers
need not name the concrete backend module.
"""
function decode_image end

# Display-size provider: a rendering backend that can query the real display
# (the SDL backend) registers a provider; without one, a fixed default is used
# so headless/SDL-free callers still get a sensible size.
const _DISPLAY_SIZE_PROVIDER = Ref{Any}(nothing)

"""
    set_display_size_provider!(f)

Register `f(; display)` as the real display-size source (called by a backend
that can query the display, e.g. SDL).
"""
set_display_size_provider!(f) = (_DISPLAY_SIZE_PROVIDER[] = f)

"""
    display_size(; display=0) -> (width, height)

The display's pixel size when a backend has registered a provider (e.g. SDL),
otherwise a fixed SDL-free default `(1280, 800)`.
"""
function display_size(; display::Integer=0)
    p = _DISPLAY_SIZE_PROVIDER[]
    p === nothing ? (1280, 800) : p(; display=display)
end

end # module
