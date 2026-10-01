# Fragment of `MathModule` — the theme of a formula: the text of the linear
# form, and the font, the ink and the selection wash of the typeset form.

"""
    MathTheme

The theme of the Math projections. `@theme` declares it, so `ScaledMathTheme`
holds each value times its scale, and `MathTheme()` is the default theme.

The linear form (`MathToSyntax`):
- `variable_text` — a variable.
- `operator_text` — an operator, and the `/` of a fraction.
- `chrome_text` — a parenthesis, a brace, a bracket and the insertion leaf.
- `symbol_text` — a symbol.
- `name_text` — the name of a function, a radical, a big operator, a
  differential, a derivative, an accent, a matrix and a case list.
- `word_text` — a run of plain text.
- `equals_text` — the `=` of an assignment.

The typeset form (`MathConfig`):
- `font` — the upright face: a number, an operator, a function name, a symbol.
- `slanted_font` — the oblique face: a variable.
- `ink` — the color every part is set in.
- `hint` — the color of an empty slot.
- `selection_wash` — the color a selected box washes itself with.

A Math projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct MathTheme
    variable_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
    operator_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
    chrome_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    symbol_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_violet)
    name_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    word_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_default)
    equals_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    font::StyleFont = font_dejavu_sans_regular_20
    slanted_font::StyleFont = font_dejavu_sans_italic_20
    ink::StyleColor = color_default
    hint::StyleColor = color_solarized_gray
    selection_wash::StyleColor = StyleColor(0.15, 0.39, 0.68, 0.22)
end

# The style field of type `T` of a Math projection that holds the field `name`
# of the theme `theme`: a `MathTheme`, a scaled one, or `nothing` for the
# default values.
_get_math_style(theme, ::Type{T}, name::Symbol) where {T} =
    make_style_field(MathTheme, scale_theme(theme), T, name)
