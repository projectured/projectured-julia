# Fragment of `JsonModule` — the theme of the JSON syntax: the text of each kind
# of value, of a key, and of the brackets and the separators.

"""
    JsonTheme

The theme of the JSON projections. `@theme` declares it, so `ScaledJsonTheme`
holds each value times its scale, and `JsonTheme()` is the default theme.

- `null_text`, `bool_text`, `number_text` and `string_text` — a value of each kind.
- `quote_text` — the quotes around a string.
- `key_text` — the key of an object member, with its quotes.
- `delimiter_text` — the brackets of an array and the braces of an object.
- `separator_text` — a comma, and the colon of a member.

A JSON projection reads the scaled theme through its `UntrackedCell` style fields;
with no theme it holds the plain values of the default theme.
"""
@theme struct JsonTheme
    null_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    bool_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    number_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    string_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    quote_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    key_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
    delimiter_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
    separator_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

# The style field of a JSON projection that holds the text `name` of the theme
# `theme`: a `JsonTheme`, a scaled one, or `nothing` for the default values.
_get_json_style(theme, name::Symbol) = make_style_field(JsonTheme, scale_theme(theme), StyleText, name)
