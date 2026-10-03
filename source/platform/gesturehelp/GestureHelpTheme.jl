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

A gesture-help projection reads the scaled theme through its `UntrackedCell`
style fields; with no theme it holds the plain values of the default theme.
"""
@theme struct GestureHelpTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("DejaVu Sans Mono", 14)
    "The heading of a domain's group of rows in the gesture map."
    map_header_text::TextRole = TextRole(color_solarized_blue; family = "Ubuntu Mono", weight = 700)
    "A gesture that can fire."
    map_gesture_text::TextRole = TextRole(color_solarized_green; family = "Ubuntu Mono", weight = 700)
    "What a gesture does."
    map_description_text::TextRole = TextRole(color_default; family = "Ubuntu Mono")
    "A row that cannot fire for the current selection."
    map_muted_text::TextRole = TextRole(color_solarized_gray; family = "Ubuntu Mono")
    "The line the person types into."
    palette_query_text::TextRole = TextRole(color_solarized_blue; weight = 700)
    "The heading of a domain's group of rows in the palette."
    palette_header_text::TextRole = TextRole(color_solarized_violet; weight = 700)
    "The chosen row."
    palette_selected_text::TextRole = TextRole(color_solarized_green; weight = 700)
    "A row that can run."
    palette_command_text::TextRole = TextRole(color_default)
    "A row that cannot run right now."
    palette_muted_text::TextRole = TextRole(color_solarized_gray)
    "The fill of the panel the palette draws itself on."
    palette_background::StyleColor = color_solarized_background_lighter
    "The border of the panel the palette draws itself on."
    palette_border::StyleColor = color_solarized_blue
    "The radius of the corners of the panel."
    palette_radius::Radius = Radius(6)
    "The width of the border of the panel."
    palette_border_width::LineWidth = LineWidth(2)
    "The space between the edge of the panel and its text."
    palette_padding::Spacing = Spacing(10)
end

# The style field of a gesture-help projection that holds the field `name` of
# the theme `theme`, of the value type `T`: a `GestureHelpTheme`, a scaled one,
# or `nothing` for the default values.
_get_gesturehelp_style(theme, ::Type{T}, name::Symbol) where {T} =
    make_style_field(GestureHelpTheme, scale_theme(theme), T; name)

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
