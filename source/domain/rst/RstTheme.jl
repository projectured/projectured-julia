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
    "A marker: an insertion placeholder, a tick, an emphasis or strong mark, a bullet, a transition, a comment, a directive's chrome, or any other marker."
    marker_text::ThemeText          = TextRole(:markup; font_role = :document_code)
    "The text, the root, a value and an argument, in the source form."
    source_text::ThemeText          = TextRole(:text; font_role = :document_code)
    "A literal, a literal block, and a code block's code."
    literal_text::ThemeText         = TextRole(:string_literal; font_role = :document_code)
    "A role name, a target, a path, and a role definition."
    target_text::ThemeText          = TextRole(:link; font_role = :document_code)
    "A role's value and a math block."
    value_text::ThemeText           = TextRole(:string_literal; font_role = :document_code)
    "A reference, a footnote label, a toctree entry, and a section's adornment."
    reference_text::ThemeText       = TextRole(:link; font_role = :document_code)
    "The name of a field of a field list."
    field_text::ThemeText           = TextRole(:field; font_role = :document_code)
    "The name of an option of a directive."
    option_text::ThemeText          = TextRole(:parameter; font_role = :document_code)
    "A substitution reference and the name of a substitution definition."
    substitution_text::ThemeText    = TextRole(:constant; font_role = :document_code)
    "The name of a directive and the language of a code block."
    directive_text::ThemeText       = TextRole(:keyword; font_role = :document_code)
    "The `.. kind::` marker of an admonition."
    admonition_text::ThemeText      = TextRole(:keyword; font_role = :document_code, weight = 700)
    "The title of a section, in the source form."
    title_text::ThemeText           = TextRole(:heading; font_role = :document_code, weight = 700)
    "The plain prose of the rendered form."
    body_text::ThemeText            = TextRole(:text; font_role = :document_text)
    "The font a bold run takes in the rendered form."
    bold_font::ThemeFont            = FontRole(:document_text; weight = 700)
    "The font an italic run takes in the rendered form."
    italic_font::ThemeFont          = FontRole(:document_text; italic = true)
    "The font of a level 1 section title in the rendered form."
    title_1_font::ThemeFont         = FontRole(:heading_1)
    "The font of a level 2 section title in the rendered form."
    title_2_font::ThemeFont         = FontRole(:heading_2)
    "The font of a level 3 section title in the rendered form."
    title_3_font::ThemeFont         = FontRole(:heading_3)
    "The font of a level 4 section title in the rendered form."
    title_4_font::ThemeFont         = FontRole(:heading_4)
    "The font of a level 5 section title in the rendered form."
    title_5_font::ThemeFont         = FontRole(:heading_5)
    "The font of a level 6 section title in the rendered form."
    title_6_font::ThemeFont         = FontRole(:heading_6)
    "The color of a section title in the rendered form."
    title_color::ThemeColor         = ColorRole(:heading)
    "The colour of a level 5 and a level 6 section title in the rendered form."
    minor_title_color::ThemeColor   = ColorRole(:text_muted)
    "The caption under a rendered figure."
    caption_text::ThemeText         = TextRole(:text_muted; font_role = :quiet, italic = true)
    "A marker of the rendered form: a transition rule, and the arrow of a literal include."
    rendered_marker_text::ThemeText = TextRole(:markup; font = StyleFont("DejaVu Sans Mono", 14))
    "The gap between the blocks of an RST page."
    block_gap::Spacing              = Spacing(8)
end
