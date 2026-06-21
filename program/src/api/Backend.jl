"""
    BackendModule

Abstract backend interface. A `Backend` encapsulates everything needed to
initialise, shut down, read input from, and write output to a particular
display/input system (e.g. SDL). Concrete subtypes live in `backend/Sdl.jl`
etc.
"""
module BackendModule

export Backend, init!, quit!, measure_text, make_backend

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
    init!(::Backend)

Initialise the backend (create windows, load libraries, …).
"""
function init!(::Backend) end

"""
    quit!(::Backend)

Tear down the backend and release resources.
"""
function quit!(::Backend) end

"""
    measure_text(::Backend, text, font) -> (Int, Int)

Return the `(pixel_width, pixel_height)` of `text` rendered in `font`.
"""
function measure_text(::Backend, text, font) end

end # module
