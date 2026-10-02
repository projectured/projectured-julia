# Fragment of `GestureLogModule` — the theme of the gesture log: the text of
# its index, its gesture, its operation, its muted line, and its empty line.

"""
    GestureLogTheme

The theme of the gesture log. `@theme` declares it, so `ScaledGestureLogTheme`
holds each value times its scale, and `GestureLogTheme()` is the default theme.

- `index_text` — the number of the entry.
- `gesture_text` — what the user did.
- `operation_text` — the operation it made.
- `muted_text` — a line that records a selection, which is context and not a
  change.
- `empty_text` — the line the log shows while it holds no gesture.

A gesture log reads the scaled theme through its `UntrackedCell` style fields;
with no theme it holds the plain values of the default theme.
"""
@theme struct GestureLogTheme
    index_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
    gesture_text::StyleText = StyleText(font_dejavu_monospace_bold_16, color_solarized_cyan)
    operation_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_700)
    muted_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
    empty_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
end

# The style field of a gesture log projection that holds the text `name` of the
# theme `theme`: a `GestureLogTheme`, a scaled one, or `nothing` for the default
# values.
_get_gesturelog_style(theme, name::Symbol) =
    make_style_field(GestureLogTheme, scale_theme(theme), StyleText, name)
