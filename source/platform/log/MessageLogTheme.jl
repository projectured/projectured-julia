# Fragment of `MessageLogModule` — the theme of the message log: the text of
# its level, its message, and its empty line.

"""
    MessageLogTheme

The fonts and the colors of the Log panel: a message's level, its text and the
line it shows when empty.

The theme of the message log. `@theme` declares it, so `ScaledMessageLogTheme`
holds each value times its scale, and `MessageLogTheme()` is the default theme.

The fields are the text styles of a message's level, its message and the
empty line. Each field has a docstring that says what it draws, which the
appearance tab shows under its name.

A message log reads the scaled theme through its `UntrackedCell` style fields;
with no theme it holds the plain values of the default theme.
"""
@theme struct MessageLogTheme
    "The level of a message, such as `Info` or `Warn`."
    level_text::StyleText = StyleText(StyleFont("DejaVu Sans Mono", 16; weight = 700), color_solarized_cyan)
    "The text of the message."
    message_text::StyleText = StyleText(StyleFont("DejaVu Sans Mono", 16), color_slate_700)
    "The line the log shows while it holds no message."
    empty_text::StyleText = StyleText(StyleFont("DejaVu Sans Mono", 16), color_slate_500)
end

# The style field of a message log projection that holds the text `name` of the
# theme `theme`: a `MessageLogTheme`, a scaled one, or `nothing` for the default
# values.
_get_messagelog_style(theme, name::Symbol) =
    make_style_field(MessageLogTheme, scale_theme(theme), StyleText; name)
