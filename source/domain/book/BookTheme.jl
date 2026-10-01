# Fragment of `BookModule` — the theme of the book syntax: the text of a
# title, an author, a chapter title and its numbering, a paragraph, a
# placeholder, a bullet and a picture's caption.

"""
    BookTheme

The theme of the Book projections. `@theme` declares it, so `ScaledBookTheme`
holds each value times its scale, and `BookTheme()` is the default theme.

- `title_text` — the title of a book.
- `author_prefix_text` — the "Written by " that introduces the author.
- `author_text` — the author of a book.
- `chapter_title_text` — the title of a chapter.
- `numbering_text` — the numbering of a chapter.
- `paragraph_text` — a paragraph, and the blank line between the elements of
  a book or a chapter.
- `placeholder_text` — the insertion leaf, and a picture with no path yet.
- `bullet_text` — the bullet of a list item.
- `picture_text` — the caption of a picture.

A book projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct BookTheme
    title_text::StyleText          = StyleText(font_ubuntu_bold_36, color_solarized_blue)
    author_prefix_text::StyleText  = StyleText(font_ubuntu_italic_20, color_solarized_gray)
    author_text::StyleText         = StyleText(font_ubuntu_italic_20, color_solarized_cyan)
    chapter_title_text::StyleText  = StyleText(font_ubuntu_bold_24, color_solarized_blue)
    numbering_text::StyleText      = StyleText(font_ubuntu_bold_24, color_solarized_magenta)
    paragraph_text::StyleText      = StyleText(font_ubuntu_monospace_regular_20, color_black)
    placeholder_text::StyleText    = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    bullet_text::StyleText         = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    picture_text::StyleText        = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

# The style field of a Book projection that holds the text `name` of the
# theme `theme`: a `BookTheme`, a scaled one, or `nothing` for the default
# values.
_get_book_style(theme, name::Symbol) = make_style_field(BookTheme, scale_theme(theme), StyleText, name)
