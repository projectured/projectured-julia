# Fragment of `YamlModule` — the theme of the YAML syntax: the text of each
# kind of value, of a key, and of the delimiters and separators.

"""
    YamlTheme

The theme of the YAML projections. `@theme` declares it, so `ScaledYamlTheme`
holds each value times its scale, and `YamlTheme()` is the default theme.

The fields are the text styles of a value of each kind, a mapping's key, a
delimiter and a separator. Each field has a docstring that says what it
draws, which the appearance tab shows as its tooltip.

A YAML projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct YamlTheme
    "A null value."
    null_text::StyleText      = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    "A boolean value."
    bool_text::StyleText      = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    "A number value."
    number_text::StyleText    = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    "A string value."
    string_text::StyleText    = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    "The key of a mapping entry."
    key_text::StyleText       = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
    "The brackets of a flow sequence, the braces of a flow mapping, and the `- ` marker of a block sequence."
    delimiter_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
    "A comma, and the colon of a mapping entry."
    separator_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

# The style field of a YAML projection that holds the text `name` of the theme
# `theme`: a `YamlTheme`, a scaled one, or `nothing` for the default values.
_get_yaml_style(theme, name::Symbol) = make_style_field(YamlTheme, scale_theme(theme), StyleText, name)
