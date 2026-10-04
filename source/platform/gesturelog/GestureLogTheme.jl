# Fragment of `GestureLogModule` — the theme of the gesture log: the text of
# its index, its gesture, its operation, its muted line, and its empty line.

"""
    GestureLogTheme

The fonts and the colors of the Gestures panel: an entry's number, its
gesture, the change it makes and the line it shows when empty.

The theme of the gesture log. `@theme` declares it, so `ScaledGestureLogTheme`
holds each value times its scale, and `GestureLogTheme()` is the default theme.

The fields are the text styles of a gesture log entry's index, gesture,
operation, muted line and empty line. Each field has a docstring that says
what it draws, which the appearance tab shows under its name.

`make_gesture_log_projection` gives the projection of a gesture log its styles
with `get_gesture_log_style`, from a theme scaled or not; a projection built
with no styles holds the plain values of the default theme.
"""
@theme struct GestureLogTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("DejaVu Sans Mono", 13)
    "The number of the entry."
    index_text::TextRole = TextRole(color_slate_500)
    "The gesture that the entry records."
    gesture_text::TextRole = TextRole(color_solarized_cyan; weight = 700)
    "The operation the gesture makes."
    operation_text::TextRole = TextRole(color_slate_700)
    "A line that records a selection, which is context and not a change."
    muted_text::TextRole = TextRole(color_slate_500)
    "The line the log shows while it holds no gesture."
    empty_text::TextRole = TextRole(color_slate_500)
    "The surface of the panel that shows the log over the content of a window: dark and translucent, so the content stays readable and the light text of the log reads over any content."
    panel_background::StyleColor = StyleColor(0.0, 0.0, 0.0, 0.72)
    "The space between the panel and the edges of the window."
    panel_margin::Spacing = Spacing(12)
    "The space inside the panel, around the lines of the log."
    panel_padding::Spacing = Spacing(8)
    "The radius of the corners of the panel."
    panel_radius::Radius = Radius(4)
end

"""
    make_gesture_log_panel_theme() -> GestureLogTheme

The gesture log theme of the panel over a window: light text for the dark
background of the panel.
"""
make_gesture_log_panel_theme() =
    GestureLogTheme(index_text = TextRole(color_gray159), operation_text = TextRole(color_gray223),
                    muted_text = TextRole(color_solarized_gray), empty_text = TextRole(color_solarized_gray))

# The two presets, for the appearance tab.
get_theme_presets(::Type{GestureLogTheme}) =
    Pair{String,Any}["Light" => GestureLogTheme, "Panel" => make_gesture_log_panel_theme]
