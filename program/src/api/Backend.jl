"""
    BackendModule

Abstract backend interface. A `Backend` encapsulates everything needed to
initialise, shut down, read input from, and write output to a particular
display/input system (e.g. SDL). Concrete subtypes live in `backend/Sdl.jl`
etc.
"""
module BackendModule

export Backend, init!, quit!, measure_text

"""
    Backend

Abstract supertype for all display/input backends.
"""
abstract type Backend end

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
