# Fragment of `FsmModule` — the theme of the fsm syntax: the keyword, the name
# of a part, a reference to another part, the chrome around them, and the
# label of a state and a transition in a diagram.

"""
    FsmTheme

The theme of the Fsm projections. `@theme` declares it, so `ScaledFsmTheme`
holds each value times its scale, and `FsmTheme()` is the default theme.

- `keyword_text` — `component`, `variable`, `timer`, `event`, `machine`,
  `state`, `initial`, `on`, `when`, `stay`, `ignore`, `entry` and `ignoring
  unhandled`.
- `name_text` — the name of a component, a variable, a timer, an event, a
  machine or a state.
- `reference_text` — a trigger, a target and an `initial`, read from the
  referenced part, and the reference of a transition label in a diagram.
- `chrome_text` — the punctuation around a part, and the chrome of a
  transition label in a diagram.
- `state_label_text` — the name of a state in a diagram.
- `trigger_text` — the keyword of a transition label in a diagram.

A Fsm projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct FsmTheme
    keyword_text::StyleText     = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    name_text::StyleText        = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    reference_text::StyleText   = StyleText(font_ubuntu_monospace_regular_20, color_solarized_violet)
    chrome_text::StyleText      = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    state_label_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_green)
    trigger_text::StyleText     = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
end

# The style field of a Fsm projection that holds the text `name` of the theme
# `theme`: a `FsmTheme`, a scaled one, or `nothing` for the default values.
_get_fsm_style(theme, name::Symbol) = make_style_field(FsmTheme, scale_theme(theme), StyleText, name)
