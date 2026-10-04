# Fragment of `HelpModule` — the theme of the Help menu: the text of the two
# lists, and the text of the page about the program.

"""
    HelpTheme

The fonts and the colors of the help lists and the about page: a heading, a
name, a description and the program title.

The theme of [`HelpListToSyntax`](@ref) and [`AboutPageToSyntax`](@ref).
`@theme` declares it, so `ScaledHelpTheme` holds each value times its scale, and
`HelpTheme()` is the default theme.

The fields are the text styles of a list's heading, name, detail, description
and muted line, and of the about page's title. Each field has a docstring
that says what it draws, which the appearance tab shows under its name.

`make_help_list_projection` and `make_about_page_projection` give their
projection its styles with `get_help_style`, from a theme scaled or not; a
projection built with no styles holds the plain values of the default theme.
"""
@theme struct HelpTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("DejaVu Sans", 13)
    "The line that says what a list holds."
    heading_text::TextRole = TextRole(:text_muted)
    "The name of a type, in a list."
    name_text::TextRole = TextRole(:heading; weight = 700, relative_size = 1.125)
    "The package and the typed names of a type, in a list; the version, the Julia version and the home page, on the about page."
    detail_text::TextRole = TextRole(:text_muted)
    "The first paragraph of a type's docstring, in a list; the sentence of the about page."
    description_text::TextRole = TextRole(:text)
    "The line a list shows for a type with no docstring."
    muted_text::TextRole = TextRole(:text_faint; italic = true)
    "The name of the program, on the about page."
    title_text::TextRole = TextRole(:heading; weight = 700, relative_size = 1.5)
end
