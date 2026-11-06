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
    "The text of a text node."
    content_text::ThemeText         = TextRole(:text; font_role = :document_code)
    "The name of an element's opening and closing tag."
    tag_text::ThemeText             = TextRole(:tag; font_role = :document_code, weight = 700)
    "The angle brackets of a tag."
    delimiter_text::ThemeText       = TextRole(:punctuation; font_role = :document_code)
    "The name of an attribute."
    attribute_name_text::ThemeText  = TextRole(:field; font_role = :document_code)
    "The quotes around an attribute value."
    quote_text::ThemeText           = TextRole(:punctuation; font_role = :document_code)
    "The value of an attribute."
    attribute_value_text::ThemeText = TextRole(:string_literal; font_role = :document_code)
end
