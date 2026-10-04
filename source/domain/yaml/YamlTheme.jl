# Fragment of `YamlModule` — the theme of the YAML syntax: the text of each
# kind of value, of a key, and of the delimiters and separators.

"""
    YamlTheme

The colors and the fonts of a YAML document: its values, its keys, its
delimiters and its separators.

The theme of the YAML projections. `@theme` declares it, so `ScaledYamlTheme`
holds each value times its scale, and `YamlTheme()` is the default theme.

The fields are the text styles of a value of each kind, a mapping's key, a
delimiter and a separator. Each field has a docstring that says what it
draws, which the appearance tab shows under its name.

The builder gives each YAML projection its styles with `get_yaml_style`, from a
theme scaled or not; a projection built with no styles holds the plain values
of the default theme.
"""
@theme struct YamlTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "A null value."
    null_text::TextRole      = TextRole(color_solarized_magenta)
    "A boolean value."
    bool_text::TextRole      = TextRole(color_solarized_yellow)
    "A number value."
    number_text::TextRole    = TextRole(color_solarized_magenta)
    "A string value."
    string_text::TextRole    = TextRole(color_solarized_green)
    "The key of a mapping entry."
    key_text::TextRole       = TextRole(color_solarized_blue)
    "The brackets of a flow sequence, the braces of a flow mapping, and the `- ` marker of a block sequence."
    delimiter_text::TextRole = TextRole(color_solarized_gray; weight = 700)
    "A comma, and the colon of a mapping entry."
    separator_text::TextRole = TextRole(color_solarized_gray)
end
