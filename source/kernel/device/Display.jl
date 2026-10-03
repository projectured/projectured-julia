# Fragment of `DeviceModule` — the display device.

"""
    Display(; width = 1280, height = 800, density = 1.0, zoom = 1.0)

A display. `width` and `height` give its usable size in logical pixels. `density`
is the number of device pixels in one logical pixel of the hardware: `2.0` on a
display with twice the usual pixel density. `zoom` is the uniform zoom of the
editor that draws on the display. `density` and `zoom` must be above 0, and the
constructor throws an `ArgumentError` for another value, `NaN` too.

The SDL backend draws each logical pixel as `get_device_pixel_ratio(display)`
device pixels. Layout works in logical pixels, so a change of `density` or `zoom`
changes the size on the screen and not the layout. The web backend sends `zoom`
to the browser, which draws at the ratio of the browser times `zoom`. The console
and video backends do not read the `Display`.
"""
mutable struct Display <: Device
    width::Int
    height::Int
    density::Float64
    zoom::Float64
    function Display(width, height, density, zoom)
        density > 0 ||
            throw(ArgumentError("the density of a display must be above 0, got $density"))
        zoom > 0 ||
            throw(ArgumentError("the zoom of a display must be above 0, got $zoom"))
        new(width, height, density, zoom)
    end
end

Display(; width::Integer = 1280, height::Integer = 800, density::Real = 1.0,
        zoom::Real = 1.0) =
    Display(width, height, Float64(density), Float64(zoom))

"""
    get_device_pixel_ratio(display::Display) -> Float64

The number of device pixels that a backend draws for one logical pixel: the
`density` of the hardware times the `zoom` of the editor.
"""
get_device_pixel_ratio(display::Display) = display.density * display.zoom
