# Fragment of `JuliaModule` — the theme of the Julia syntax: the text of each
# kind of token, the plain and the hint text of the insertion hole, and the
# colors of its commitability.

"""
    JuliaTheme

The theme of the Julia projections. `@theme` declares it, so `ScaledJuliaTheme`
holds each value times its scale, and `JuliaTheme()` is the default theme.

- `identifier_text` — a variable, and the label of an object that stands in the
  code, such as a widget a person pasted into a form.
- `literal_text` — a number, a string, a character, a chunk of an interpolated
  string, the quotes of a string interpolation, and a docstring.
- `punctuation_text` — a quote, a delimiter, a separator, a brace and a fence.
- `keyword_text` — a keyword, `true`, `false` and `nothing`.
- `symbol_text` — a symbol, `<:`, `->`, and the `\$` of a string interpolation.
- `operator_text` — an operator, the dot of a field access, a range, `::`, `=`
  and `?:`.
- `callee_text` — the called function, and the name of a macro.
- `name_text` — the name of a module.
- `plain_text` — the path of a `using`, and the typed text of the insertion.
- `hint_text` — the completion that the insertion offers.
- `wrong_color` and `found_color` — the color of the typed text of the
  insertion while it names nothing, and while it names one thing.

A Julia projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct JuliaTheme
    identifier_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_violet)
    literal_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    punctuation_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    keyword_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
    symbol_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    operator_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
    callee_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
    name_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    plain_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_default)
    hint_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_completion_hint)
    wrong_color::StyleColor = color_solarized_red
    found_color::StyleColor = color_solarized_green
end

# The style field of type `T` of a Julia projection that holds the field `name`
# of the theme `theme`: a `JuliaTheme`, a scaled one, or `nothing` for the
# default values.
_get_julia_style(theme, ::Type{T}, name::Symbol) where {T} =
    make_style_field(JuliaTheme, scale_theme(theme), T, name)
