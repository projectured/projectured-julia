# Fragment of `GestureHelpModule` — the theme of the gesture map, the command
# palette, and the panel the palette draws itself on.

"""
    GestureHelpTheme

The theme of the gesture map and the command palette. `@theme` declares it, so
`ScaledGestureHelpTheme` holds each value times its scale, and
`GestureHelpTheme()` is the default theme.

- `map_header_text` — the heading of a domain's group of rows in the gesture map.
- `map_gesture_text` — a gesture that can fire.
- `map_description_text` — what a gesture does.
- `map_muted_text` — a row that cannot fire for the current selection.
- `palette_query_text` — the line the person types into.
- `palette_header_text` — the heading of a domain's group of rows in the palette.
- `palette_selected_text` — the chosen row.
- `palette_command_text` — a row that can run.
- `palette_muted_text` — a row that cannot run right now.
- `palette_background` and `palette_border` — the fill and the border of the
  panel the palette draws itself on.
- `palette_radius` — the radius of the corners of the panel.
- `palette_border_width` — the width of the border of the panel.
- `palette_padding` — the room between the edge of the panel and its text.

A gesture-help projection reads the scaled theme through its `UntrackedCell`
style fields; with no theme it holds the plain values of the default theme.
"""
@theme struct GestureHelpTheme
    map_header_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    map_gesture_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_green)
    map_description_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_default)
    map_muted_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    palette_query_text::StyleText = StyleText(font_dejavu_monospace_bold_20, color_solarized_blue)
    palette_header_text::StyleText = StyleText(font_dejavu_monospace_bold_20, color_solarized_violet)
    palette_selected_text::StyleText = StyleText(font_dejavu_monospace_bold_20, color_solarized_green)
    palette_command_text::StyleText = StyleText(font_dejavu_monospace_regular_20, color_default)
    palette_muted_text::StyleText = StyleText(font_dejavu_monospace_regular_20, color_solarized_gray)
    palette_background::StyleColor = color_solarized_background_lighter
    palette_border::StyleColor = color_solarized_blue
    palette_radius::Radius = Radius(6)
    palette_border_width::LineWidth = LineWidth(2)
    palette_padding::Spacing = Spacing(10)
end

# The style field of a gesture-help projection that holds the field `name` of
# the theme `theme`, of the value type `T`: a `GestureHelpTheme`, a scaled one,
# or `nothing` for the default values.
_get_gesturehelp_style(theme, ::Type{T}, name::Symbol) where {T} =
    make_style_field(GestureHelpTheme, scale_theme(theme), T, name)

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
