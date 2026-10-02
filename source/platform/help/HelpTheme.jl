# Fragment of `HelpModule` — the theme of the Help menu: the text of the two
# lists, and the text of the page about the program.

"""
    HelpTheme

The theme of [`HelpListToSyntax`](@ref) and [`AboutPageToSyntax`](@ref).
`@theme` declares it, so `ScaledHelpTheme` holds each value times its scale, and
`HelpTheme()` is the default theme.

- `heading_text` — the line that says what a list holds.
- `name_text` — the name of a type, in a list.
- `detail_text` — the package of a type and its typed names, in a list; the
  version, the Julia version and the home page, on the page about the program.
- `description_text` — the first paragraph of a type's docstring, in a list; the
  sentence of the page about the program.
- `muted_text` — the line a list shows for a type with no docstring.
- `title_text` — the name of the program, on the page about the program.

A help projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct HelpTheme
    heading_text::StyleText = StyleText(font_dejavu_sans_regular_16, color_slate_600)
    name_text::StyleText = StyleText(font_dejavu_sans_bold_18, color_slate_900)
    detail_text::StyleText = StyleText(font_dejavu_sans_regular_16, color_slate_500)
    description_text::StyleText = StyleText(font_dejavu_sans_regular_16, color_slate_700)
    muted_text::StyleText = StyleText(font_dejavu_sans_italic_16, color_slate_400)
    title_text::StyleText = StyleText(font_dejavu_sans_bold_24, color_slate_900)
end

# The style field of a help projection that holds the text `name` of the theme
# `theme`: a `HelpTheme`, a scaled one, or `nothing` for the default values.
_get_help_style(theme, name::Symbol) = make_style_field(HelpTheme, scale_theme(theme), StyleText, name)
