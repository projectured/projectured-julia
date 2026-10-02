# Fragment of `UndoModule` — the theme of the undo history: the text of its
# index, its steps, its marker, and its barrier.

"""
    UndoTheme

The theme of the undo history. `@theme` declares it, so `ScaledUndoTheme` holds
each value times its scale, and `UndoTheme()` is the default theme.

- `index_text` — the label and the number of a step.
- `step_text` — a step that can be taken back.
- `ahead_text` — a step that can be put back.
- `empty_text` — the line the history shows while it holds no step.
- `marker_text` — the line for where the document stands now.
- `barrier_text` — a step the history stops at, because it can not be undone.

The history reads the scaled theme through its `UntrackedCell` style fields;
with no theme it holds the plain values of the default theme.
"""
@theme struct UndoTheme
    index_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
    step_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_700)
    ahead_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
    empty_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
    marker_text::StyleText = StyleText(font_dejavu_monospace_bold_16, color_solarized_cyan)
    barrier_text::StyleText = StyleText(font_dejavu_monospace_bold_16, color_solarized_orange)
end

# The style field of an undo projection that holds the text `name` of the theme
# `theme`: an `UndoTheme`, a scaled one, or `nothing` for the default values.
_get_undo_style(theme, name::Symbol) = make_style_field(UndoTheme, scale_theme(theme), StyleText, name)
