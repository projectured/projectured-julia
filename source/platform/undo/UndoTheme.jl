# Fragment of `UndoModule` — the theme of the undo history: the text of its
# index, its steps, its marker, and its barrier.

"""
    UndoTheme

The fonts and the colors of the undo history: a step, the current marker, a
barrier and the line it shows when empty.

The theme of the undo history. `@theme` declares it, so `ScaledUndoTheme` holds
each value times its scale, and `UndoTheme()` is the default theme.

The fields are the text styles of a step's index, a step that can be taken
back or put back, the empty line, the current marker and a barrier step. Each
field has a docstring that says what it draws, which the appearance tab shows
under its name.

The history reads the scaled theme through its `UntrackedCell` style fields;
with no theme it holds the plain values of the default theme.
"""
@theme struct UndoTheme
    "The label and the number of a step."
    index_text::StyleText = StyleText(StyleFont("DejaVu Sans Mono", 16), color_slate_500)
    "A step that can be taken back."
    step_text::StyleText = StyleText(StyleFont("DejaVu Sans Mono", 16), color_slate_700)
    "A step that can be put back."
    ahead_text::StyleText = StyleText(StyleFont("DejaVu Sans Mono", 16), color_slate_500)
    "The line the history shows while it holds no step."
    empty_text::StyleText = StyleText(StyleFont("DejaVu Sans Mono", 16), color_slate_500)
    "The line for where the document stands now."
    marker_text::StyleText = StyleText(StyleFont("DejaVu Sans Mono", 16; weight = 700), color_solarized_cyan)
    "A step the history stops at, because it can not be undone."
    barrier_text::StyleText = StyleText(StyleFont("DejaVu Sans Mono", 16; weight = 700), color_solarized_orange)
end

# The style field of an undo projection that holds the text `name` of the theme
# `theme`: an `UndoTheme`, a scaled one, or `nothing` for the default values.
_get_undo_style(theme, name::Symbol) = make_style_field(UndoTheme, scale_theme(theme), StyleText; name)
