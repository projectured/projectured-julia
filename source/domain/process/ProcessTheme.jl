# Fragment of `ProcessModule` — the theme of the process syntax: the keyword,
# the name, the text of a step, the chrome, the live run and its breakpoint,
# and the label of a terminal in a diagram.

"""
    ProcessTheme

The theme of the Process projections. `@theme` declares it, so
`ScaledProcessTheme` holds each value times its scale, and `ProcessTheme()` is
the default theme.

The fields are the text styles of a process's keywords, names, steps, chrome,
the live run and its breakpoint, and the terminal of a diagram. Each field
has a docstring that says what it draws, which the appearance tab shows as
its tooltip.

A Process projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct ProcessTheme
    "`process`, `step`, `if`, `else`, `while`, `for`, `in`, `break`, `continue` and `return`, and the keyword of a diagram label."
    keyword_text::StyleText    = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
    "The name of a process, and a `for`'s variable."
    name_text::StyleText       = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    "The description of a step, and the text of a step label in a diagram."
    action_text::StyleText     = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
    "The punctuation around a part, an unrefined `<condition>`, `<variable>` or `<iterable>` marker, the chrome of a diagram label, and an edge label."
    chrome_text::StyleText     = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    "The keyword of the node where a debug session stops."
    current_text::StyleText    = StyleText(font_ubuntu_monospace_bold_20, color_solarized_orange)
    "The keyword of a node that holds a breakpoint."
    breakpoint_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_red)
    "The label of the start or the stop terminal in a diagram."
    terminal_text::StyleText   = StyleText(font_ubuntu_monospace_bold_20, color_solarized_green)
end

# The style field of a Process projection that holds the text `name` of the
# theme `theme`: a `ProcessTheme`, a scaled one, or `nothing` for the default
# values.
_get_process_style(theme, name::Symbol) = make_style_field(ProcessTheme, scale_theme(theme), StyleText; name)
