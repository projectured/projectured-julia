# Fragment of `BookModule` — the theme of the book syntax: the text of a
# title, an author, a chapter title and its numbering, a paragraph, a
# placeholder, a bullet and a picture's caption.

"""
    BookTheme

The fonts and the colors of a book: its title, its author, a chapter heading,
a paragraph, a bullet and a picture caption.

The theme of the Book projections. `@theme` declares it, so `ScaledBookTheme`
holds each value times its scale, and `BookTheme()` is the default theme.

The fields are the text styles of a book's title, author, chapter heading,
paragraph, placeholder, bullet and picture caption. Each field has a docstring
that says what it draws, which the appearance tab shows under its name.

The builder gives each Book projection its styles with `get_book_style`, from a
theme scaled or not; a projection built with no styles holds the plain values
of the default theme.
"""
@theme struct BookTheme
    "The title of a book."
    title_text::ThemeText          = TextRole(:heading; font_role = :heading_1)
    "The \"Written by \" that introduces the author."
    author_prefix_text::ThemeText  = TextRole(:text_muted; font_role = :document_text, italic = true)
    "The author of a book."
    author_text::ThemeText         = TextRole(:text; font_role = :document_text, italic = true)
    "The title of a chapter."
    chapter_title_text::ThemeText  = TextRole(:heading; font_role = :heading_2)
    "The numbering of a chapter."
    numbering_text::ThemeText      = TextRole(:text_muted; font_role = :heading_2)
    "A paragraph, and the blank line between the elements of a book or a chapter."
    paragraph_text::ThemeText      = TextRole(:text; font_role = :document_text)
    "The insertion leaf, and a picture with no path yet."
    placeholder_text::ThemeText    = TextRole(:text_faint; font_role = :document_text)
    "The bullet of a list item."
    bullet_text::ThemeText         = TextRole(:markup; font_role = :document_text)
    "The caption of a picture."
    picture_text::ThemeText        = TextRole(:text_muted; font_role = :quiet)
end
