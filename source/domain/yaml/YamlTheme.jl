# Fragment of `YamlModule` — the theme of the YAML syntax: the text of each
# kind of value, of a key, and of the delimiters and separators.

"""
    YamlTheme

The theme of the YAML projections. `@theme` declares it, so `ScaledYamlTheme`
holds each value times its scale, and `YamlTheme()` is the default theme.

- `null_text`, `bool_text`, `number_text` and `string_text` — a value of each kind.
- `key_text` — the key of a mapping entry.
- `delimiter_text` — the brackets of a flow sequence, the braces of a flow
  mapping, and the `- ` marker of a block sequence.
- `separator_text` — a comma, and the colon of a mapping entry.

A YAML projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct YamlTheme
    null_text::StyleText      = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    bool_text::StyleText      = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    number_text::StyleText    = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    string_text::StyleText    = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    key_text::StyleText       = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
    delimiter_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
    separator_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

# The style field of a YAML projection that holds the text `name` of the theme
# `theme`: a `YamlTheme`, a scaled one, or `nothing` for the default values.
_get_yaml_style(theme, name::Symbol) = make_style_field(YamlTheme, scale_theme(theme), StyleText, name)
