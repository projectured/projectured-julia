# Fragment of `XmlModule` — the theme of the XML syntax: the text of a text
# node, a tag, a delimiter, an attribute name, a quote, and an attribute value.

"""
    XmlTheme

The theme of the XML projections. `@theme` declares it, so `ScaledXmlTheme`
holds each value times its scale, and `XmlTheme()` is the default theme.

- `content_text` — the text of a text node.
- `tag_text` — the name of an element's opening and closing tag.
- `delimiter_text` — the angle brackets of a tag.
- `attribute_name_text` — the name of an attribute.
- `quote_text` — the quotes around an attribute value.
- `attribute_value_text` — the value of an attribute.

An XML projection reads the scaled theme through its `UntrackedCell` style fields;
with no theme it holds the plain values of the default theme.
"""
@theme struct XmlTheme
    content_text::StyleText         = StyleText(font_ubuntu_monospace_regular_20, color_black)
    tag_text::StyleText             = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    delimiter_text::StyleText       = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    attribute_name_text::StyleText  = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    quote_text::StyleText           = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    attribute_value_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

# The style field of an XML projection that holds the text `name` of the theme
# `theme`: an `XmlTheme`, a scaled one, or `nothing` for the default values.
_get_xml_style(theme, name::Symbol) = make_style_field(XmlTheme, scale_theme(theme), StyleText, name)
