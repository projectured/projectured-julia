# Fragment of `BookModule` — the theme of the book syntax: the text of a
# title, an author, a chapter title and its numbering, a paragraph, a
# placeholder, a bullet and a picture's caption.

"""
    BookTheme

The theme of the Book projections. `@theme` declares it, so `ScaledBookTheme`
holds each value times its scale, and `BookTheme()` is the default theme.

The fields are the text styles of a book's title, author, chapter heading,
paragraph, placeholder, bullet and picture caption. Each field has a docstring
that says what it draws, which the appearance tab shows as its tooltip.

A book projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct BookTheme
    "The title of a book."
    title_text::StyleText          = StyleText(font_ubuntu_bold_36, color_solarized_blue)
    "The \"Written by \" that introduces the author."
    author_prefix_text::StyleText  = StyleText(font_ubuntu_italic_20, color_solarized_gray)
    "The author of a book."
    author_text::StyleText         = StyleText(font_ubuntu_italic_20, color_solarized_cyan)
    "The title of a chapter."
    chapter_title_text::StyleText  = StyleText(font_ubuntu_bold_24, color_solarized_blue)
    "The numbering of a chapter."
    numbering_text::StyleText      = StyleText(font_ubuntu_bold_24, color_solarized_magenta)
    "A paragraph, and the blank line between the elements of a book or a chapter."
    paragraph_text::StyleText      = StyleText(font_ubuntu_monospace_regular_20, color_black)
    "The insertion leaf, and a picture with no path yet."
    placeholder_text::StyleText    = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    "The bullet of a list item."
    bullet_text::StyleText         = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    "The caption of a picture."
    picture_text::StyleText        = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

# The style field of a Book projection that holds the text `name` of the
# theme `theme`: a `BookTheme`, a scaled one, or `nothing` for the default
# values.
_get_book_style(theme, name::Symbol) = make_style_field(BookTheme, scale_theme(theme), StyleText; name)
