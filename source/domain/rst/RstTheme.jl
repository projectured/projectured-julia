# Fragment of `RstModule` — the theme of the RST syntax: the text of a marker,
# a literal, a target, a value, a reference, a directive, an admonition and a
# title, the fonts a title level takes, and the gap between the blocks of a
# page.

"""
    RstTheme

The colors and the fonts of a reStructuredText document, in its source form
and in its rendered form. They color a section title, a reference, a
directive and an admonition.

The theme of the RST projections. `@theme` declares it, so `ScaledRstTheme`
holds each value times its scale, and `RstTheme()` is the default theme.

The fields are in two groups: the text and the fonts of the source form, and
the fonts and the colors of the rendered form, plus the gap between the
blocks of a page. Each field has a docstring that says what it draws, which
the appearance tab shows under its name.

The builder gives each RST projection its styles with `get_rst_style`, from a
theme scaled or not; a projection built with no styles holds the plain values
of the default theme. A section title holds the font of each level and its
color, picked by the level while it prints.
"""
@theme struct RstTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu", 14)
    "The font that the code of this theme follows: its family, its weight and its size."
    code_font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "A marker: an insertion placeholder, a tick, an emphasis or strong mark, a bullet, a transition, a comment, a directive's chrome, or any other marker."
    marker_text::TextRole          = TextRole(:markup; base = :code_font)
    "The text, the root, a value and an argument, in the source form."
    source_text::TextRole          = TextRole(:text; base = :code_font)
    "A literal, a literal block, and a code block's code."
    literal_text::TextRole         = TextRole(:string_literal; base = :code_font)
    "A role name, a target, a path, and a role definition."
    target_text::TextRole          = TextRole(:link; base = :code_font)
    "A role's value and a math block."
    value_text::TextRole           = TextRole(:string_literal; base = :code_font)
    "A reference, a footnote label, a toctree entry, and a section's adornment."
    reference_text::TextRole       = TextRole(:link; base = :code_font)
    "The name of a field of a field list."
    field_text::TextRole           = TextRole(:field; base = :code_font)
    "The name of an option of a directive."
    option_text::TextRole          = TextRole(:parameter; base = :code_font)
    "A substitution reference and the name of a substitution definition."
    substitution_text::TextRole    = TextRole(:constant; base = :code_font)
    "The name of a directive and the language of a code block."
    directive_text::TextRole       = TextRole(:keyword; base = :code_font)
    "The `.. kind::` marker of an admonition."
    admonition_text::TextRole      = TextRole(:keyword; base = :code_font, weight = 700)
    "The title of a section, in the source form."
    title_text::TextRole           = TextRole(:heading; base = :code_font, weight = 700)
    "The plain prose of the rendered form."
    body_text::TextRole            = TextRole(:text)
    "The font a bold run takes in the rendered form."
    bold_font::FontRole            = FontRole(weight = 700)
    "The font an italic run takes in the rendered form."
    italic_font::FontRole          = FontRole(italic = true)
    "The font of a level 1 section title in the rendered form."
    title_1_font::FontRole         = FontRole(weight = 700, relative_size = 1.8)
    "The font of a level 2 section title in the rendered form."
    title_2_font::FontRole         = FontRole(weight = 700, relative_size = 1.2)
    "The font of a level 3 section title in the rendered form."
    title_3_font::FontRole         = FontRole(weight = 700, relative_size = 1.1)
    "The font of a section title past the third level, in the rendered form."
    title_font::FontRole           = FontRole(weight = 700, relative_size = 0.9)
    "The color of a section title in the rendered form."
    title_color::ThemeColor         = ColorRole(:heading)
    "The caption under a rendered figure."
    caption_text::TextRole         = TextRole(:text_muted; italic = true)
    "A marker of the rendered form: a transition rule, and the arrow of a literal include."
    rendered_marker_text::TextRole = TextRole(:markup; base = :code_font, family = "DejaVu Sans Mono")
    "The gap between the blocks of an RST page."
    block_gap::Spacing              = Spacing(8)
end
