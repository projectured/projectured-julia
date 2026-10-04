# Fragment of `XmlModule` — the theme of the XML syntax: the text of a text
# node, a tag, a delimiter, an attribute name, a quote, and an attribute value.

"""
    XmlTheme

The fonts and the colors of an XML document: its text, its tags, its
attributes and its delimiters.

The theme of the XML projections. `@theme` declares it, so `ScaledXmlTheme`
holds each value times its scale, and `XmlTheme()` is the default theme.

The fields are the text styles of a text node, a tag, a delimiter, an
attribute name, a quote and an attribute value. Each field has a docstring
that says what it draws, which the appearance tab shows under its name.

An XML projection holds its styles and no theme; its builder gives them with `get_xml_style`,
from a theme scaled or not, and with no theme it holds the plain values of the
default theme.
"""
@theme struct XmlTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "The text of a text node."
    content_text::TextRole         = TextRole(color_black)
    "The name of an element's opening and closing tag."
    tag_text::TextRole             = TextRole(color_solarized_blue; weight = 700)
    "The angle brackets of a tag."
    delimiter_text::TextRole       = TextRole(color_solarized_gray)
    "The name of an attribute."
    attribute_name_text::TextRole  = TextRole(color_solarized_green)
    "The quotes around an attribute value."
    quote_text::TextRole           = TextRole(color_solarized_yellow)
    "The value of an attribute."
    attribute_value_text::TextRole = TextRole(color_solarized_cyan)
end
