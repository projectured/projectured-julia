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
    index_text::TextRole = TextRole(:text_muted)
    "The gesture that the entry records."
    gesture_text::TextRole = TextRole(:accent_text; weight = 700)
    "The operation the gesture makes."
    operation_text::TextRole = TextRole(:text)
    "A line that records a selection, which is context and not a change."
    muted_text::TextRole = TextRole(:text_faint)
    "The line the log shows while it holds no gesture."
    empty_text::TextRole = TextRole(:text_faint)
    "The surface of the panel that shows the log over the content of a window: dark and translucent, so the content stays readable and the light text of the log reads over any content."
    panel_background::StyleColor = ColorRole(:surface_inverse)
    "The space between the panel and the edges of the window."
    panel_margin::Spacing = Spacing(12)
    "The space inside the panel, around the lines of the log."
    panel_padding::Spacing = Spacing(8)
    "The radius of the corners of the panel."
    panel_radius::Radius = Radius(4)
end

"""
    make_gesture_log_panel_theme() -> GestureLogTheme

The gesture log theme of the panel over a window: the texts of the inverse
surface of the panel, dark in the light mode and light in the dark mode.
"""
make_gesture_log_panel_theme() =
    GestureLogTheme(index_text = TextRole(:text_inverse_muted),
                    gesture_text = TextRole(:text_inverse; weight = 700),
                    operation_text = TextRole(:text_inverse), muted_text = TextRole(:text_inverse_muted),
                    empty_text = TextRole(:text_inverse_muted))

# The two presets, for the appearance tab: the log on a surface, and on its panel.
get_theme_presets(::Type{GestureLogTheme}) =
    Pair{String,Any}["Plain" => GestureLogTheme, "Panel" => make_gesture_log_panel_theme]
