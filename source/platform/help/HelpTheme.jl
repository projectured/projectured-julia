# Fragment of `HelpModule` — the theme of the Help menu: the text of the pages of
# the two trees, and the text of the page about the program.

"""
    HelpTheme

The fonts and the colors of the pages of the help and of the about page: the
line over a table, the name and the docstring of a type, and the program title.

The theme of [`HelpGroupToWidget`](@ref), [`HelpEntryToWidget`](@ref) and
[`AboutPageToSyntax`](@ref).
`@theme` declares it, so `ScaledHelpTheme` holds each value times its scale, and
`HelpTheme()` is the default theme.

The fields are the text styles of the line over the table of a tree or a group,
of the name, the details, the docstring and the muted line of the page of a
type, and of the about page's title. Each field has a docstring
that says what it draws, which the appearance tab shows under its name.

`make_help_group_projection`, `make_help_entry_projection` and
`make_about_page_projection` give their
projection its styles with `get_help_style`, from a theme scaled or not; a
projection built with no styles holds the plain values of the default theme.
"""
@theme struct HelpTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("DejaVu Sans", 13)
    "The line that says what a tree or a group holds, over its table."
    heading_text::ThemeText = TextRole(:text_muted)
    "The name of a type, on its page."
    name_text::ThemeText = TextRole(:heading; weight = 700, relative_size = 1.125)
    "The module and the names to type of a type, on its page; the version, the Julia version and the home page, on the about page."
    detail_text::ThemeText = TextRole(:text_muted)
    "The docstring of a type, on its page; the sentence of the about page."
    description_text::ThemeText = TextRole(:text)
    "The line that the page of a type with no docstring shows."
    muted_text::ThemeText = TextRole(:text_faint; italic = true)
    "The name of the program, on the about page."
    title_text::ThemeText = TextRole(:heading; weight = 700, relative_size = 1.5)
end
