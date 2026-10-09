# Fragment of `TerminalModule` — the theme of a terminal.

"""
    TerminalTheme

The texts of a terminal: the output of the program, its standard error, a line
that the person sent, a line of the terminal itself, and the command and the
status above them. `@theme` declares it, so `ScaledTerminalTheme` holds each
value times its scale, and `TerminalTheme()` is the default theme.
`make_terminal_projection` gives the projection its styles with
`get_terminal_style`.
"""
@theme struct TerminalTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "A line of the standard output of the program."
    output_text::ThemeText = TextRole(:text)
    "A line of the standard error of the program."
    error_text::ThemeText = TextRole(:error_text)
    "A line that the person sent to the program."
    input_text::ThemeText = TextRole(:text; weight = 700)
    "A line of the terminal itself, such as the exit status, and the command above the lines."
    status_text::ThemeText = TextRole(:text_muted)
    "The height of the pane of the lines."
    lines_height::Int = 200
    "The height of the pane of the input line, which a press hits also when the line is empty."
    input_height::Int = 24
    "The vertical gap between the parts of the terminal."
    gap::Int = 4
end
