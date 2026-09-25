# Fragment of `DeviceModule` — the display device.

"""
    Display(; width = 1280, height = 800, scale = 1.0, zoom = 1.0)

A display. `width` and `height` give its usable size in logical pixels. `scale`
is the number of device pixels in one logical pixel of the hardware: `2.0` on a
display with twice the usual pixel density. `zoom` is the uniform zoom of the
editor that draws on the display.

A backend draws each logical pixel as `get_device_pixel_ratio(display)` device
pixels. Layout works in logical pixels, so a change of `scale` or `zoom` changes
the size on the screen and not the layout.
"""
mutable struct Display <: Device
    width::Int
    height::Int
    scale::Float64
    zoom::Float64
end

Display(; width::Integer = 1280, height::Integer = 800, scale::Real = 1.0,
        zoom::Real = 1.0) =
    Display(width, height, Float64(scale), Float64(zoom))

"""
    get_device_pixel_ratio(display::Display) -> Float64

The number of device pixels that a backend draws for one logical pixel: the
`scale` of the hardware times the `zoom` of the editor.
"""
get_device_pixel_ratio(display::Display) = display.scale * display.zoom
