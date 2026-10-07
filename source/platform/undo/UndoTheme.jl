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

`make_undo_projection` gives the projection of the undo history its styles with
`get_undo_style`, from a theme scaled or not; a projection built with no styles
holds the plain values of the default theme.
"""
@theme struct UndoTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("DejaVu Sans Mono", 13)
    "The label and the number of a step."
    index_text::ThemeText = TextRole(:text_muted)
    "A step that can be taken back."
    step_text::ThemeText = TextRole(:text)
    "A step that can be put back."
    ahead_text::ThemeText = TextRole(:text_faint)
    "The line the history shows while it holds no step."
    empty_text::ThemeText = TextRole(:text_faint)
    "The line for where the document stands now."
    marker_text::ThemeText = TextRole(:accent_text; weight = 700)
    "A step the history stops at, because it can not be undone."
    barrier_text::ThemeText = TextRole(:warning_text; weight = 700)
end
