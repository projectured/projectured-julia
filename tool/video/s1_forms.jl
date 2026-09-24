# The forms of screenplay S1, which `record_rotating_vector.jl` types and a probe
# can evaluate headless.

# The forms before the canvas has a pane of its own.
const FIRST_FORMS = [
    "clock = editor.clock",
    "canvas = GraphicsCanvas([GraphicsRect(0, 0, 300, 300; color = color_solarized_background_lighter)]; w = 300, h = 300)",
]

# The forms after it. Each `add!` returns nothing, so its result row says
# `nothing`, and the picture changes only where it is: in its pane, and in the one
# row that made it.
const LATER_FORMS = [
    "add!(elements...) = foreach(element -> push!(canvas.elements, element), elements)",
    "add!(GraphicsCircle(90, 90, 60; color = color_transparent, border_width = 2, border_color = color_solarized_content_darker))",
    "phase() = -0.5 * get_reactive_clock_time(clock)",
    "dot = GraphicsCircle(() -> 90 + 60 * cos(phase()), () -> 90 - 60 * sin(phase()), 5; color = color_solarized_magenta)",
    "add!(dot)",
    "add!(GraphicsPolyline(() -> [(170 + i, 90 - 60 * sin(phase() - i / 50)) for i in 0:120]; color = color_solarized_blue, width = 2))",
    "add!(GraphicsPolyline(() -> [(90 + 60 * cos(phase() - i / 50), 170 + i) for i in 0:120]; color = color_solarized_green, width = 2))",
    "add!(GraphicsLine(170, () -> dot.cy, () -> dot.cx, () -> dot.cy; color = color_solarized_content_lighter, dash = (5, 5)))",
    "add!(GraphicsLine(() -> dot.cx, 170, () -> dot.cx, () -> dot.cy; color = color_solarized_content_lighter, dash = (5, 5)))",
    "add!(GraphicsLine(170, 90, 290, 90), GraphicsLine(170, 30, 170, 150))",
    "add!(GraphicsLine(90, 170, 90, 290), GraphicsLine(30, 170, 150, 170))",
]
