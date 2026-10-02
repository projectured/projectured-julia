# Fragment of `ProcessModule` — the theme of the process syntax: the keyword,
# the name, the text of a step, the chrome, the live run and its breakpoint,
# and the label of a terminal in a diagram.

"""
    ProcessTheme

The theme of the Process projections. `@theme` declares it, so
`ScaledProcessTheme` holds each value times its scale, and `ProcessTheme()` is
the default theme.

- `keyword_text` — `process`, `step`, `if`, `else`, `while`, `for`, `in`,
  `break`, `continue` and `return`, and the keyword of a diagram label.
- `name_text` — the name of a process and a `for`'s variable.
- `action_text` — the description of a step, and the text of a step label in a
  diagram.
- `chrome_text` — the punctuation around a part, an unrefined `<condition>`,
  `<variable>` or `<iterable>` marker, the chrome of a diagram label, and an
  edge label.
- `current_text` — the keyword of the node a debug session is stopped at.
- `breakpoint_text` — the keyword of a node that holds a breakpoint.
- `terminal_text` — the label of the start or the stop terminal in a diagram.

A Process projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct ProcessTheme
    keyword_text::StyleText    = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
    name_text::StyleText       = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    action_text::StyleText     = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
    chrome_text::StyleText     = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    current_text::StyleText    = StyleText(font_ubuntu_monospace_bold_20, color_solarized_orange)
    breakpoint_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_red)
    terminal_text::StyleText   = StyleText(font_ubuntu_monospace_bold_20, color_solarized_green)
end

# The style field of a Process projection that holds the text `name` of the
# theme `theme`: a `ProcessTheme`, a scaled one, or `nothing` for the default
# values.
_get_process_style(theme, name::Symbol) = make_style_field(ProcessTheme, scale_theme(theme), StyleText, name)
