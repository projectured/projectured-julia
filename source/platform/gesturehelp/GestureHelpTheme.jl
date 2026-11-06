# Fragment of `GestureHelpModule` — the theme of the gesture map.

"""
    GestureHelpTheme

The fonts and the colors of the gesture map: a heading, a gesture, its
description and a row that can not fire. `@theme` declares it, so
`ScaledGestureHelpTheme` holds each value times its scale, and
`GestureHelpTheme()` is the default theme. Each field has a docstring that says
what it draws, which the appearance tab shows under its name. The command palette
is a list of the widget slice, and the widget theme draws it.

`make_gesture_map_projection` gives its projection its styles with
`get_gesture_help_style`, from a theme scaled or not; a projection built with no
styles holds the plain values of the default theme.
"""
@theme struct GestureHelpTheme
    "The heading of a domain's group of rows in the gesture map."
    map_header_text::ThemeText = TextRole(:text_muted; font_role = :section)
    "A gesture that can fire."
    map_gesture_text::ThemeText = TextRole(:accent_text; font_role = :label)
    "What a gesture does."
    map_description_text::ThemeText = TextRole(:text; font_role = :text)
    "A row that cannot fire for the current selection."
    map_muted_text::ThemeText = TextRole(:text_faint; font_role = :text)
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
