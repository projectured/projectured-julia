# Fragment of `MessageLogModule` — the theme of the message log: the text of
# its level, its message, and its empty line.

"""
    MessageLogTheme

The fonts and the colors of the Log panel: a message's level, its text and the
line it shows when empty.

The theme of the message log. `@theme` declares it, so `ScaledMessageLogTheme`
holds each value times its scale, and `MessageLogTheme()` is the default theme.

The fields are the text styles of a message's level, one for each kind of
level, its message and the empty line. Each field has a docstring that says what it draws, which the
appearance tab shows under its name.

`make_message_log_projection` gives the projection of a message log its styles
with `get_message_log_style`, from a theme scaled or not; a projection built with
no styles holds the plain values of the default theme.
"""
@theme struct MessageLogTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("DejaVu Sans Mono", 13)
    "The level of a message of information, such as `Info`."
    level_text::TextRole = TextRole(color_solarized_cyan; weight = 700)
    "The level of an error, such as `Error`."
    error_level_text::TextRole = TextRole(color_solarized_red; weight = 700)
    "The level of a warning, such as `Warn`."
    warning_level_text::TextRole = TextRole(color_solarized_yellow; weight = 700)
    "The level of a message for debugging, such as `Debug`."
    debug_level_text::TextRole = TextRole(color_slate_500; weight = 700)
    "The text of the message."
    message_text::TextRole = TextRole(color_slate_700)
    "The line the log shows while it holds no message."
    empty_text::TextRole = TextRole(color_slate_500)
end
