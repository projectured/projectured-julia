# Fragment of `RstModule` — the theme of the RST syntax: the text of a marker,
# a literal, a target, a value, a reference, a directive, an admonition and a
# title, the fonts a title level takes, and the gap between the blocks of a
# page.

"""
    RstTheme

The theme of the RST projections. `@theme` declares it, so `ScaledRstTheme`
holds each value times its scale, and `RstTheme()` is the default theme.

The fields are in two groups: the text and the fonts of the source form, and
the fonts and the colors of the rendered form, plus the gap between the
blocks of a page. Each field has a docstring that says what it draws, which
the appearance tab shows as its tooltip.

An RST projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct RstTheme
    "A marker: an insertion placeholder, a tick, an emphasis or strong mark, a bullet, a transition, a comment, a directive's chrome, or any other marker."
    marker_text::StyleText          = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    "The text, the root, a value and an argument, in the source form."
    source_text::StyleText          = StyleText(font_ubuntu_monospace_regular_20, color_black)
    "A literal, a literal block, and a code block's code."
    literal_text::StyleText         = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    "A role name, a target, a path, and a role definition."
    target_text::StyleText          = StyleText(font_ubuntu_monospace_regular_20, color_solarized_violet)
    "A role's value and a math block."
    value_text::StyleText           = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
    "A reference, a footnote label, a field name, a toctree entry, and a section's adornment."
    reference_text::StyleText       = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
    "A substitution reference and the name of a substitution definition."
    substitution_text::StyleText    = StyleText(font_ubuntu_monospace_regular_20, color_solarized_orange)
    "The name of a directive and the language of a code block."
    directive_text::StyleText       = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    "The `.. kind::` marker of an admonition."
    admonition_text::StyleText      = StyleText(font_ubuntu_monospace_bold_20, color_solarized_yellow)
    "The title of a section, in the source form."
    title_text::StyleText           = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    "The plain prose of the rendered form."
    body_text::StyleText            = StyleText(font_ubuntu_regular_20, color_black)
    "The font a bold run takes in the rendered form."
    bold_font::StyleFont            = font_ubuntu_bold_20
    "The font an italic run takes in the rendered form."
    italic_font::StyleFont          = font_ubuntu_italic_20
    "The font of a level 1 section title in the rendered form."
    title_1_font::StyleFont         = font_ubuntu_bold_36
    "The font of a level 2 section title in the rendered form."
    title_2_font::StyleFont         = font_ubuntu_bold_24
    "The font of a level 3 section title in the rendered form."
    title_3_font::StyleFont         = font_ubuntu_bold_22
    "The font of a section title past the third level, in the rendered form."
    title_font::StyleFont           = font_ubuntu_bold_18
    "The color of a section title in the rendered form."
    title_color::StyleColor         = color_solarized_blue
    "The caption under a rendered figure."
    caption_text::StyleText         = StyleText(font_ubuntu_italic_20, color_solarized_gray)
    "A marker of the rendered form: a transition rule, and the arrow of a literal include."
    rendered_marker_text::StyleText = StyleText(font_dejavu_monospace_regular_20, color_solarized_gray)
    "The gap between the blocks of an RST page."
    block_gap::Spacing              = Spacing(8)
end

# The style field of an RST projection that holds the text `name` of the
# theme `theme`: an `RstTheme`, a scaled one, or `nothing` for the default
# values.
_get_rst_style(theme, name::Symbol) = make_style_field(RstTheme, scale_theme(theme), StyleText; name)

# The font of a section title at `level` (1-based; every level past the third
# takes `title_font`), read from the theme `theme`.
function _title_font(theme, level::Int)
    name = level <= 1 ? :title_1_font :
           level == 2 ? :title_2_font :
           level == 3 ? :title_3_font : :title_font
    make_style_field(RstTheme, scale_theme(theme), StyleFont; name)
end
