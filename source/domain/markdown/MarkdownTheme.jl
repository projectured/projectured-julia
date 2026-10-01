# Fragment of `MarkdownModule` — the theme of the markdown syntax: the text of
# a marker, a heading, a link and a caption, the fonts that a heading, a bold
# run and an italic run take, and the gap between the blocks of a page.

"""
    MarkdownTheme

The theme of the Markdown projections. `@theme` declares it, so
`ScaledMarkdownTheme` holds each value times its scale, and `MarkdownTheme()`
is the default theme.

- `marker_text` — a marker: an insertion placeholder, a tick, a thematic
  break, an emphasis or strong marker, a quote marker, a bullet, a pipe, a
  bracket, a fence.
- `source_text` — the text of the source form, and the root.
- `code_text` — a code span and a code block, in the source form.
- `language_text` — the language of a code block, and the value of an inline
  code span in the rendered form.
- `heading_marker_text` — the `#` marker of a heading, in the source form.
- `url_text` — the url of a link or an image.
- `alt_text` — the alt text of an image.
- `body_text` — the plain prose of the rendered form.
- `bold_font`, `italic_font` — the font a bold or an italic run takes in the
  rendered form.
- `heading_1_font`, `heading_2_font`, `heading_3_font`, `heading_font` — the
  font of a heading in the rendered form, by level (`heading_font` is every
  level past the third).
- `heading_color` — the color of a heading in the rendered form.
- `link_color` — the color of a link in the rendered form.
- `caption_text` — the caption under a rendered image.
- `rendered_marker_text` — a marker of the rendered form: a thematic break
  rule, a quote bar, a code fence's language, a list marker.
- `block_gap` — the gap between the blocks of a markdown page.

A markdown projection reads the scaled theme through its `UntrackedCell`
style fields; with no theme it holds the plain values of the default theme.
"""
@theme struct MarkdownTheme
    marker_text::StyleText          = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    source_text::StyleText          = StyleText(font_ubuntu_monospace_regular_20, color_black)
    code_text::StyleText            = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    language_text::StyleText        = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    heading_marker_text::StyleText  = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    url_text::StyleText             = StyleText(font_ubuntu_monospace_regular_20, color_solarized_violet)
    alt_text::StyleText             = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
    body_text::StyleText            = StyleText(font_ubuntu_regular_20, color_black)
    bold_font::StyleFont            = font_ubuntu_bold_20
    italic_font::StyleFont          = font_ubuntu_italic_20
    heading_1_font::StyleFont       = font_ubuntu_bold_36
    heading_2_font::StyleFont       = font_ubuntu_bold_24
    heading_3_font::StyleFont       = font_ubuntu_bold_22
    heading_font::StyleFont         = font_ubuntu_bold_18
    heading_color::StyleColor       = color_solarized_blue
    link_color::StyleColor          = color_solarized_blue
    caption_text::StyleText         = StyleText(font_ubuntu_italic_20, color_solarized_gray)
    rendered_marker_text::StyleText = StyleText(font_dejavu_monospace_regular_20, color_solarized_gray)
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
