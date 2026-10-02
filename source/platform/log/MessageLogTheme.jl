# Fragment of `MessageLogModule` — the theme of the message log: the text of
# its level, its message, and its empty line.

"""
    MessageLogTheme

The theme of the message log. `@theme` declares it, so `ScaledMessageLogTheme`
holds each value times its scale, and `MessageLogTheme()` is the default theme.

- `level_text` — the level of a message, such as `Info` or `Warn`.
- `message_text` — the message itself.
- `empty_text` — the line the log shows while it holds no message.

A message log reads the scaled theme through its `UntrackedCell` style fields;
with no theme it holds the plain values of the default theme.
"""
@theme struct MessageLogTheme
    level_text::StyleText = StyleText(font_dejavu_monospace_bold_16, color_solarized_cyan)
    message_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_700)
    empty_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
end

# The style field of a message log projection that holds the text `name` of the
# theme `theme`: a `MessageLogTheme`, a scaled one, or `nothing` for the default
# values.
_get_messagelog_style(theme, name::Symbol) =
    make_style_field(MessageLogTheme, scale_theme(theme), StyleText, name)
