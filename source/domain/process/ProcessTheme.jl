# Fragment of `ProcessModule` — the theme of the process syntax: the keyword,
# the name, the text of a step, the chrome, the live run and its breakpoint,
# and the label of a terminal in a diagram.

"""
    ProcessTheme

The fonts and the colors of a process: its keywords, its names, a step, the
current step of a run and a breakpoint.

The theme of the Process projections. `@theme` declares it, so
`ScaledProcessTheme` holds each value times its scale, and `ProcessTheme()` is
the default theme.

The fields are the text styles of a process's keywords, names, steps, chrome,
the live run and its breakpoint, and the terminal of a diagram. Each field
has a docstring that says what it draws, which the appearance tab shows under
its name.

The builder gives each Process projection its styles with `get_process_style`,
from a theme scaled or not; a projection built with no styles holds the plain
values of the default theme.
"""
@theme struct ProcessTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "`process`, `step`, `if`, `else`, `while`, `for`, `in`, `break`, `continue` and `return`, and the keyword of a diagram label."
    keyword_text::ThemeText    = TextRole(:keyword; weight = 700)
    "The name of a process."
    name_text::ThemeText       = TextRole(:function_name; weight = 700)
    "The description of a step, and the text of a step label in a diagram."
    action_text::ThemeText     = TextRole(:text)
    "The punctuation around a part, an unrefined `<condition>`, `<variable>` or `<iterable>` marker, the chrome of a diagram label, and an edge label."
    chrome_text::ThemeText     = TextRole(:punctuation)
    "The keyword of the node where a debug session stops."
    current_text::ThemeText    = TextRole(:warning_text; weight = 700)
    "The keyword of a node that holds a breakpoint."
    breakpoint_text::ThemeText = TextRole(:error_text; weight = 700)
    "The label of the start or the stop terminal in a diagram."
    terminal_text::ThemeText   = TextRole(:keyword; weight = 700)
end
