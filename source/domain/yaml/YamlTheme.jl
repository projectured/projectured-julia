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
    "A null value."
    null_text::ThemeText      = TextRole(:null_literal; font_role = :document_code)
    "A boolean value."
    bool_text::ThemeText      = TextRole(:boolean_literal; font_role = :document_code)
    "A number value."
    number_text::ThemeText    = TextRole(:number_literal; font_role = :document_code)
    "A string value."
    string_text::ThemeText    = TextRole(:string_literal; font_role = :document_code)
    "The key of a mapping entry."
    key_text::ThemeText       = TextRole(:field; font_role = :document_code)
    "The brackets of a flow sequence, the braces of a flow mapping, and the `- ` marker of a block sequence."
    delimiter_text::ThemeText = TextRole(:punctuation; font_role = :document_code, weight = 700)
    "A comma, and the colon of a mapping entry."
    separator_text::ThemeText = TextRole(:punctuation; font_role = :document_code)
end
