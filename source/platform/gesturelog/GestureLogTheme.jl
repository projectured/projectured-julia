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

A gesture log reads the scaled theme through its `UntrackedCell` style fields;
with no theme it holds the plain values of the default theme.
"""
@theme struct GestureLogTheme
    "The number of the entry."
    index_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
    "The gesture that the entry records."
    gesture_text::StyleText = StyleText(font_dejavu_monospace_bold_16, color_solarized_cyan)
    "The operation the gesture makes."
    operation_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_700)
    "A line that records a selection, which is context and not a change."
    muted_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
    "The line the log shows while it holds no gesture."
    empty_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
end

# The style field of a gesture log projection that holds the text `name` of the
# theme `theme`: a `GestureLogTheme`, a scaled one, or `nothing` for the default
# values.
_get_gesturelog_style(theme, name::Symbol) =
    make_style_field(GestureLogTheme, scale_theme(theme), StyleText; name)
