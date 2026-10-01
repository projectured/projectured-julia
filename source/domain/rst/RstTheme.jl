# Fragment of `RstModule` — the theme of the RST syntax: the text of a marker,
# a literal, a target, a value, a reference, a directive, an admonition and a
# title, the fonts a title level takes, and the gap between the blocks of a
# page.

"""
    RstTheme

The theme of the RST projections. `@theme` declares it, so `ScaledRstTheme`
holds each value times its scale, and `RstTheme()` is the default theme.

- `marker_text` — a marker: an insertion placeholder, a tick, an emphasis or
  strong marker, a bullet, a transition, a comment, a directive's `.. `
  chrome, and every other marker with no role of its own below.
- `source_text` — the text itself, the root, a value and an argument, all in
  the source form.
- `literal_text` — a literal, a literal block, and a code block's code.
- `target_text` — a role name, a target, a path, and a role definition.
- `value_text` — a role's value and a math block.
- `reference_text` — a reference, a footnote label, a field name, a toctree
  entry, and a section's adornment.
- `substitution_text` — a substitution reference and a substitution
  definition's name.
- `directive_text` — a directive's name and a code block's language.
- `admonition_text` — an admonition's `.. kind::` marker.
- `title_text` — the title of a section, in the source form.
- `body_text` — the plain prose of the rendered form.
- `bold_font`, `italic_font` — the font a bold or an italic run takes in the
  rendered form.
- `title_1_font`, `title_2_font`, `title_3_font`, `title_font` — the font of a
  section title in the rendered form, by level (`title_font` is every level
  past the third).
- `title_color` — the color of a section title in the rendered form.
- `caption_text` — the caption under a rendered figure.
- `rendered_marker_text` — a marker of the rendered form: a transition rule,
  the arrow of a literal include.
- `block_gap` — the gap between the blocks of an RST page.

An RST projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct RstTheme
    marker_text::StyleText          = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    source_text::StyleText          = StyleText(font_ubuntu_monospace_regular_20, color_black)
    literal_text::StyleText         = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    target_text::StyleText          = StyleText(font_ubuntu_monospace_regular_20, color_solarized_violet)
    value_text::StyleText           = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
    reference_text::StyleText       = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
    substitution_text::StyleText    = StyleText(font_ubuntu_monospace_regular_20, color_solarized_orange)
    directive_text::StyleText       = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    admonition_text::StyleText      = StyleText(font_ubuntu_monospace_bold_20, color_solarized_yellow)
    title_text::StyleText           = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    body_text::StyleText            = StyleText(font_ubuntu_regular_20, color_black)
    bold_font::StyleFont            = font_ubuntu_bold_20
    italic_font::StyleFont          = font_ubuntu_italic_20
    title_1_font::StyleFont         = font_ubuntu_bold_36
    title_2_font::StyleFont         = font_ubuntu_bold_24
    title_3_font::StyleFont         = font_ubuntu_bold_22
    title_font::StyleFont           = font_ubuntu_bold_18
    title_color::StyleColor         = color_solarized_blue
    caption_text::StyleText         = StyleText(font_ubuntu_italic_20, color_solarized_gray)
    rendered_marker_text::StyleText = StyleText(font_dejavu_monospace_regular_20, color_solarized_gray)
    block_gap::Spacing              = Spacing(8)
end

# The style field of an RST projection that holds the text `name` of the
# theme `theme`: an `RstTheme`, a scaled one, or `nothing` for the default
# values.
_get_rst_style(theme, name::Symbol) = make_style_field(RstTheme, scale_theme(theme), StyleText, name)

# The font of a section title at `level` (1-based; every level past the third
# takes `title_font`), read from the theme `theme`.
function _title_font(theme, level::Int)
    name = level <= 1 ? :title_1_font :
           level == 2 ? :title_2_font :
           level == 3 ? :title_3_font : :title_font
    make_style_field(RstTheme, scale_theme(theme), StyleFont, name)
end
