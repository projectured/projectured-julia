# Fragment of `GestureHelpModule` — the theme of the gesture map, the command
# palette, and the panel the palette draws itself on.

"""
    GestureHelpTheme

The fonts and the colors of the gesture map and the command palette: a
heading, a gesture, its description and the search field.

The theme of the gesture map and the command palette. `@theme` declares it, so
`ScaledGestureHelpTheme` holds each value times its scale, and
`GestureHelpTheme()` is the default theme.

The fields are in two groups: the text of the gesture map's rows, and the
text, the fill, the border and the spacing of the command palette and its
panel. Each field has a docstring that says what it draws, which the
appearance tab shows under its name.

`make_gesture_map_projection` and `make_command_palette_projection` give their
projection its styles with `get_gesture_help_style`, from a theme scaled or
not; a projection built with no styles holds the plain values of the default
theme.
"""
@theme struct GestureHelpTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("DejaVu Sans Mono", 14)
    "The heading of a domain's group of rows in the gesture map."
    map_header_text::TextRole = TextRole(:heading; family = "Ubuntu Mono", weight = 700)
    "A gesture that can fire."
    map_gesture_text::TextRole = TextRole(:accent_text; family = "Ubuntu Mono", weight = 700)
    "What a gesture does."
    map_description_text::TextRole = TextRole(:text; family = "Ubuntu Mono")
    "A row that cannot fire for the current selection."
    map_muted_text::TextRole = TextRole(:text_faint; family = "Ubuntu Mono")
    "The line the person types into."
    palette_query_text::TextRole = TextRole(:text; weight = 700)
    "The heading of a domain's group of rows in the palette."
    palette_header_text::TextRole = TextRole(:heading; weight = 700)
    "The chosen row."
    palette_selected_text::TextRole = TextRole(:accent_text; weight = 700)
    "A row that can run."
    palette_command_text::TextRole = TextRole(:text)
    "A row that cannot run right now."
    palette_muted_text::TextRole = TextRole(:text_faint)
    "The fill of the panel the palette draws itself on."
    palette_background::ThemeColor = ColorRole(:surface)
    "The border of the panel the palette draws itself on."
    palette_border::ThemeColor = ColorRole(:border_strong)
    "The radius of the corners of the panel."
    palette_radius::Radius = Radius(6)
    "The width of the border of the panel."
    palette_border_width::LineWidth = LineWidth(2)
    "The space between the edge of the panel and its text."
    palette_padding::Spacing = Spacing(10)
end

# The themes that a wrapper of the gesture help gives its chains: the gesture help
# theme, the syntax theme and the text theme of the `Appearance` of the build, or
# none with no appearance wrapper.
function _get_gesture_help_themes(parts::EditorParts)
    appearance = get(parts.arguments, :appearance, nothing)
    appearance isa Appearance ||
        return (theme = nothing, syntax_theme = nothing, text_theme = nothing)
    (theme = get_scaled_theme!(appearance, GestureHelpTheme),
     syntax_theme = get_scaled_theme!(appearance, SyntaxTheme),
     text_theme = get_scaled_theme!(appearance, TextTheme))
end
