# Fragment of `SyntaxModule` — the theme of the syntax: the text of each kind of
# leaf, of the delimiters, and of the parts of an insertion.

"""
    SyntaxTheme

The theme of the syntax projections. `@theme` declares it, so `ScaledSyntaxTheme`
holds each value times its scale, and `SyntaxTheme()` is the default theme.

The fields are in groups: the leaves, the reflection of an object, the
collections, the insertion, the delimiter under the pointer and the font of
an undelimited node. Each field has a docstring that says what it draws,
which the appearance tab shows as its tooltip.

A syntax projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme. A domain
that prints its own leaves styles them with a theme of its own.
"""
@theme struct SyntaxTheme
    "A boolean value."
    bool_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
    "A number value."
    number_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    "A string value."
    string_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    "The quotes around a string or a character."
    quote_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    "A symbol, in the reflected display of an object."
    symbol_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
    "The value `nothing`, in the reflected display of an object."
    nothing_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    "A boolean value, in the reflected display of an object."
    reflected_bool_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    "The name of the type of an object."
    type_name_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    "The name of a field."
    field_name_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    "The muted italic text of an undefined field, of a cycle and of an empty placeholder."
    note_text::StyleText = StyleText(font_ubuntu_monospace_italic_20, color_solarized_gray)
    "A bracket."
    delimiter_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
    "A comma."
    separator_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    "The prefix and the suffix, and the placeholder of an empty buffer, of the insertion."
    label_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    "The typed text of the insertion while it names nothing yet."
    typed_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_default)
    "The continuation that a completion offers."
    hint_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_completion_hint)
    "The color of the typed text of the insertion while it names nothing."
    wrong_color::StyleColor = color_solarized_red
    "The color of the typed text of the insertion while it names one thing."
    found_color::StyleColor = color_solarized_green
    "The color of the delimiters around the part under the pointer."
    lit_delimiter::StyleColor = color_solarized_orange
    "The font of the indentation and the line breaks of a node with no delimiter of its own, such as the body of a block."
    font::StyleFont = font_ubuntu_monospace_regular_20
end

# The style field of type `T` of a syntax projection that holds the field `name`
# of the syntax theme: `make_style_field` of `SyntaxTheme`.
_get_syntax_style(theme, ::Type{T}, name::Symbol) where {T} = make_style_field(SyntaxTheme, theme, T; name)
