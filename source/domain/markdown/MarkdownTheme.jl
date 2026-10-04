# Fragment of `MarkdownModule` — the theme of the markdown syntax: the text of
# a marker, a heading, a link and a caption, the fonts that a heading, a bold
# run and an italic run take, and the gap between the blocks of a page.

"""
    MarkdownTheme

The colors and the fonts of a Markdown document, in its source form and in its
rendered form. They color a heading, a link, a bold run, an italic run and a
code block.

The theme of the Markdown projections. `@theme` declares it, so
`ScaledMarkdownTheme` holds each value times its scale, and `MarkdownTheme()`
is the default theme.

The fields are in two groups: the text and the fonts of the source form, and
the fonts and the colors of the rendered form, plus the gap between the
blocks of a page. Each field has a docstring that says what it draws, which
the appearance tab shows under its name.

The builder gives each Markdown projection its styles with `get_markdown_style`,
from a theme scaled or not; a projection built with no styles holds the plain
values of the default theme. A heading holds the four fonts of its levels,
`heading_1_font` through `heading_font`, as its own fields.
"""
@theme struct MarkdownTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu", 14)
    "The font that the code of this theme follows: its family, its weight and its size."
    code_font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "A marker: an insertion placeholder, a tick, a break, an emphasis mark, a quote mark, a bullet, a pipe, a bracket, a fence."
    marker_text::TextRole          = TextRole(color_solarized_gray; base = :code_font)
    "The text of the source form, and the root."
    source_text::TextRole          = TextRole(color_black; base = :code_font)
    "A code span and a code block, in the source form."
    code_text::TextRole            = TextRole(color_solarized_green; base = :code_font)
    "The language of a code block, and the value of an inline code span in the rendered form."
    language_text::TextRole        = TextRole(color_solarized_magenta; base = :code_font)
    "The `#` marker of a heading, in the source form."
    heading_marker_text::TextRole  = TextRole(color_solarized_blue; base = :code_font, weight = 700)
    "The url of a link or an image."
    url_text::TextRole             = TextRole(color_solarized_violet; base = :code_font)
    "The alt text of an image."
    alt_text::TextRole             = TextRole(color_solarized_cyan; base = :code_font)
    "The plain prose of the rendered form."
    body_text::TextRole            = TextRole(color_black)
    "The font a bold run takes in the rendered form."
    bold_font::FontRole            = FontRole(weight = 700)
    "The font an italic run takes in the rendered form."
    italic_font::FontRole          = FontRole(italic = true)
    "The font of a level 1 heading in the rendered form."
    heading_1_font::FontRole       = FontRole(weight = 700, relative_size = 1.8)
    "The font of a level 2 heading in the rendered form."
    heading_2_font::FontRole       = FontRole(weight = 700, relative_size = 1.2)
    "The font of a level 3 heading in the rendered form."
    heading_3_font::FontRole       = FontRole(weight = 700, relative_size = 1.1)
    "The font of a heading past the third level, in the rendered form."
    heading_font::FontRole         = FontRole(weight = 700, relative_size = 0.9)
    "The color of a heading in the rendered form."
    heading_color::StyleColor       = color_solarized_blue
    "The color of a link in the rendered form."
    link_color::StyleColor          = color_solarized_blue
    "The caption under a rendered image."
    caption_text::TextRole         = TextRole(color_solarized_gray; italic = true)
    "A marker of the rendered form: a thematic break rule, a quote bar, a code fence's language, a list marker."
    rendered_marker_text::TextRole = TextRole(color_solarized_gray; base = :code_font, family = "DejaVu Sans Mono")
    "The gap between the blocks of a markdown page."
    block_gap::Spacing              = Spacing(8)
end
