"""
    DisplayModule

Display-size query with a provider indirection. A rendering backend that can
query the real display (the SDL backend) registers a provider via
`set_display_size_provider!`; without one, a fixed SDL-free default is
returned so headless callers still get a sensible size. It holds
**process-global provider state**, so it lives beside `BackendModule` in
the backend layer rather than folding into it. Moved from `device/` to
`backend/` in kernel plan P6 — the display is a rendering concept, not an
input-device one.
"""
module DisplayModule

export get_display_size, set_display_size_provider!

# A rendering backend that can query the real display (the SDL backend) registers
# a provider; without one, a fixed default is used so headless/SDL-free callers
# still get a sensible size.
const _DISPLAY_SIZE_PROVIDER = Ref{Any}(nothing)

"""
    set_display_size_provider!(f)

Register `f(; display)` as the real display-size source (called by a backend
that can query the display, e.g. SDL).
"""
set_display_size_provider!(f) = (_DISPLAY_SIZE_PROVIDER[] = f)

"""
    get_display_size(; display=0) -> (width, height)

The display's pixel size when a backend has registered a provider (e.g. SDL),
otherwise a fixed SDL-free default `(1280, 800)`.
"""
function get_display_size(; display::Integer=0)
    p = _DISPLAY_SIZE_PROVIDER[]
    p === nothing ? (1280, 800) : p(; display=display)
end

end # module
