# Fragment of `MarkdownModule` — the theme of the markdown syntax: the text of
# a marker, a heading, a link and a caption, the fonts that a heading, a bold
# run and an italic run take, and the gap between the blocks of a page.

"""
    MarkdownTheme

The theme of the Markdown projections. `@theme` declares it, so
`ScaledMarkdownTheme` holds each value times its scale, and `MarkdownTheme()`
is the default theme.

The fields are in two groups: the text and the fonts of the source form, and
the fonts and the colors of the rendered form, plus the gap between the
blocks of a page. Each field has a docstring that says what it draws, which
the appearance tab shows as its tooltip.

A markdown projection reads the scaled theme through its `UntrackedCell`
style fields; with no theme it holds the plain values of the default theme.
"""
@theme struct MarkdownTheme
    "A marker: an insertion placeholder, a tick, a break, an emphasis mark, a quote mark, a bullet, a pipe, a bracket, a fence."
    marker_text::StyleText          = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    "The text of the source form, and the root."
    source_text::StyleText          = StyleText(font_ubuntu_monospace_regular_20, color_black)
    "A code span and a code block, in the source form."
    code_text::StyleText            = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    "The language of a code block, and the value of an inline code span in the rendered form."
    language_text::StyleText        = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    "The `#` marker of a heading, in the source form."
    heading_marker_text::StyleText  = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    "The url of a link or an image."
    url_text::StyleText             = StyleText(font_ubuntu_monospace_regular_20, color_solarized_violet)
    "The alt text of an image."
    alt_text::StyleText             = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
    "The plain prose of the rendered form."
    body_text::StyleText            = StyleText(font_ubuntu_regular_20, color_black)
    "The font a bold run takes in the rendered form."
    bold_font::StyleFont            = font_ubuntu_bold_20
    "The font an italic run takes in the rendered form."
    italic_font::StyleFont          = font_ubuntu_italic_20
    "The font of a level 1 heading in the rendered form."
    heading_1_font::StyleFont       = font_ubuntu_bold_36
    "The font of a level 2 heading in the rendered form."
    heading_2_font::StyleFont       = font_ubuntu_bold_24
    "The font of a level 3 heading in the rendered form."
    heading_3_font::StyleFont       = font_ubuntu_bold_22
    "The font of a heading past the third level, in the rendered form."
    heading_font::StyleFont         = font_ubuntu_bold_18
    "The color of a heading in the rendered form."
    heading_color::StyleColor       = color_solarized_blue
    "The color of a link in the rendered form."
    link_color::StyleColor          = color_solarized_blue
    "The caption under a rendered image."
    caption_text::StyleText         = StyleText(font_ubuntu_italic_20, color_solarized_gray)
    "A marker of the rendered form: a thematic break rule, a quote bar, a code fence's language, a list marker."
    rendered_marker_text::StyleText = StyleText(font_dejavu_monospace_regular_20, color_solarized_gray)
    "The gap between the blocks of a markdown page."
    block_gap::Spacing              = Spacing(8)
end

# The style field of a Markdown projection that holds the text `name` of the
# theme `theme`: a `MarkdownTheme`, a scaled one, or `nothing` for the default
# values.
_get_markdown_style(theme, name::Symbol) = make_style_field(MarkdownTheme, scale_theme(theme), StyleText, name)

# The font of a heading at `level` (1-based; every level past the third takes
# `heading_font`), read from the theme `theme`.
function _heading_font(theme, level::Int)
    name = level <= 1 ? :heading_1_font :
           level == 2 ? :heading_2_font :
           level == 3 ? :heading_3_font : :heading_font
    make_style_field(MarkdownTheme, scale_theme(theme), StyleFont, name)
end
