# Fragment of `SyntaxModule` — the theme of the syntax: the text of each kind of
# leaf, of the delimiters, and of the parts of an insertion.

"""
    SyntaxTheme

The theme of the syntax projections. `@theme` declares it, so `ScaledSyntaxTheme`
holds each value times its scale, and `SyntaxTheme()` is the default theme.

- **Leaves** — `bool_text`, `number_text`, `string_text` and `quote_text` (the
  quotes around a string or a character), and for a reflected value
  `symbol_text`, `nothing_text` and `reflected_bool_text`.
- **Reflection** — `type_name_text` (the name of the type of an object),
  `field_name_text`, and `note_text`, the muted italic text of an undefined
  field, of a cycle and of an empty placeholder.
- **Collections** — `delimiter_text` (a bracket) and `separator_text` (a comma).
- **Insertion** — `label_text` (the prefix and the suffix, and the placeholder of
  an empty buffer), `typed_text` (the typed text while it names nothing yet),
  `hint_text` (the continuation that a completion offers), and `wrong_color` and
  `found_color`, the colors of a typed text that names nothing and one that
  names one thing.
- `lit_delimiter` — the color of the delimiters around the part under the
  pointer.
- `font` — the font of the indentation and the line breaks of a node that has no
  delimiter of its own, such as the body of a block; a node with a delimiter
  takes its font.

A syntax projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme. A domain
that prints its own leaves styles them with a theme of its own.
"""
@theme struct SyntaxTheme
    bool_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
    number_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    string_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    quote_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    symbol_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
    nothing_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    reflected_bool_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    type_name_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    field_name_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    note_text::StyleText = StyleText(font_ubuntu_monospace_italic_20, color_solarized_gray)
    delimiter_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
    separator_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    label_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    typed_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_default)
    hint_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_completion_hint)
    wrong_color::StyleColor = color_solarized_red
    found_color::StyleColor = color_solarized_green
    lit_delimiter::StyleColor = color_solarized_orange
    font::StyleFont = font_ubuntu_monospace_regular_20
end

# The style field of type `T` of a syntax projection that holds the field `name`
# of the syntax theme: `make_style_field` of `SyntaxTheme`.
_get_syntax_style(theme, ::Type{T}, name::Symbol) where {T} = make_style_field(SyntaxTheme, theme, T, name)
