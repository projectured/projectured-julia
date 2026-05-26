"""
    MouseModule

Backend-agnostic mouse event types. Projection readers work with these
structs and remain independent of any particular backend.
"""
module MouseModule

import ..DeviceModule: Device

export Mouse, MouseClick, MouseMove, MouseScroll

"""
    Mouse()

A mouse input device. Passed to `read_from_device(backend, mouse)`
to poll for mouse events.
"""
struct Mouse <: Device end

"""
    MouseClick(button::Symbol, x::Int, y::Int)

Backend-agnostic mouse button event. `button` is one of:
`:left`, `:middle`, `:right`.
`x` and `y` are pixel coordinates relative to the window.
"""
struct MouseClick
    button::Symbol
    x::Int
    y::Int
end

"""
    MouseMove(x::Int, y::Int)

Backend-agnostic mouse motion event.
`x` and `y` are pixel coordinates relative to the window.
"""
struct MouseMove
    x::Int
    y::Int
end

"""
    MouseScroll(dx::Int, dy::Int, x::Int, y::Int)

Backend-agnostic mouse wheel event.
`dx` and `dy` are scroll deltas (positive = right/down).
`x` and `y` are the cursor position at the time of the scroll.
"""
struct MouseScroll
    dx::Int
    dy::Int
    x::Int
    y::Int
end

end # module
